#!/bin/bash
set -o pipefail

CURRENT_DIR="$(dirname "$0")"

source "${CURRENT_DIR}/helpers.sh"

CLOUDWATCH_ENABLED=${CLOUDWATCH_ENABLED:-false}
USERNAME=${USERNAME:-"camunda"}
ADMIN_USERNAME=${ADMIN_USERNAME:-"ubuntu"}
MNT_DIR=${MNT_DIR:-"/opt/camunda"}
BROKER_PORT=${BROKER_PORT:-26502}
TERRAFORM_DIR=${TERRAFORM_DIR:-"${CURRENT_DIR}/../terraform/cluster"}

CAMUNDA_DISTRO_USER=${CAMUNDA_DISTRO_USER:-""}
CAMUNDA_DISTRO_PASSWORD=${CAMUNDA_DISTRO_PASSWORD:-""}

# Optional shared download cache (used in CI). When CAMUNDA_DISTRO_CACHE_DIR is set, this
# orchestrator downloads the Camunda distribution + connectors bundle ONCE and stages them on
# every node, instead of each node downloading the same artifacts from Artifactory. This
# removes the per-node (and, because the cache dir persists for the whole job, the per-reinstall)
# duplication that dominates our Artifactory egress.
# Leave it unset for a normal (customer) run: nodes then download individually, exactly as before.
CAMUNDA_DISTRO_CACHE_DIR=${CAMUNDA_DISTRO_CACHE_DIR:-""}
# Where staged files land on each node. Must match camunda-install.sh's CAMUNDA_DISTRO_CACHE_DIR.
REMOTE_DISTRO_CACHE_DIR="/tmp/.camunda-distro-cache"
DISTRO_CACHE_READY=false
# Orchestrator-side cached files for the version currently being installed (empty when not
# cached). Populated by warm_distro_cache, consumed by push_distro_cache_to_node.
CACHED_TARBALL_PATH=""
CACHED_JAR_PATH=""

# Resolve the effective default of a 'VAR=${VAR:-"x"}' (or plain 'VAR=x') assignment in a script.
script_default() {
    local var="$1" file="$2" line
    line=$(grep -E "^${var}=" "${file}" | head -1 || true)
    line=${line#*=}
    if [[ "${line}" =~ :-\"?([^\"\}]*)\"?\} ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        line=${line%\"}
        line=${line#\"}
        printf '%s' "${line}"
    fi
}

# Download the Camunda distribution and connectors bundle once on this orchestrator host so
# every node can reuse them. Files are keyed by version, so the upgrade test (previous -> current
# within the same job) never reuses the wrong artifact. Best-effort: on any failure the cache is
# left empty and nodes fall back to downloading individually.
# NOTE: keep the artifact URLs/resolution in sync with
#       generic/compute/debian/procedure/camunda-install.sh
warm_distro_cache() {
    DISTRO_CACHE_READY=false
    CACHED_TARBALL_PATH=""
    CACHED_JAR_PATH=""

    # Parse the very same script piped to each node below ("ssh ... < camunda-install.sh") so the
    # cached artifacts always match what the nodes install -- including the in-place edits the
    # upgrade test makes to this file. (env vars do NOT cross the SSH boundary; the node uses these
    # defaults too.)
    local install_script="${CURRENT_DIR}/camunda-install.sh"
    local camunda_version connectors_version
    camunda_version=$(script_default "CAMUNDA_VERSION" "${install_script}")
    connectors_version=$(script_default "CAMUNDA_CONNECTORS_VERSION" "${install_script}")

    if [[ -z "${camunda_version}" || -z "${connectors_version}" ]]; then
        echo "[WARN] Could not parse Camunda/Connectors versions from ${install_script}; skipping download cache."
        return 0
    fi

    local netrc_opt="" netrc_file=""
    if [[ -n "${CAMUNDA_DISTRO_USER}" && -n "${CAMUNDA_DISTRO_PASSWORD}" ]]; then
        netrc_file=$(mktemp)
        chmod 600 "${netrc_file}"
        printf 'machine artifacts.camunda.com login %s password %s\n' "${CAMUNDA_DISTRO_USER}" "${CAMUNDA_DISTRO_PASSWORD}" > "${netrc_file}"
        netrc_opt="--netrc-file ${netrc_file}"
    fi

    mkdir -p "${CAMUNDA_DISTRO_CACHE_DIR}" || { echo "[WARN] Cannot create ${CAMUNDA_DISTRO_CACHE_DIR}; skipping download cache."; return 0; }
    local tarball="${CAMUNDA_DISTRO_CACHE_DIR}/camunda-zeebe-${camunda_version}.tar.gz"
    local jar="${CAMUNDA_DISTRO_CACHE_DIR}/connectors-${connectors_version}.jar"

    # --- Camunda distribution ---
    if [[ -f "${tarball}" ]]; then
        echo "[INFO] Reusing cached Camunda distribution at ${tarball}."
    else
        local camunda_url=""
        if [[ "${camunda_version}" =~ SNAPSHOT ]]; then
            local snap=""
            # shellcheck disable=SC2086
            snap=$(curl -sfL ${netrc_opt} "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${camunda_version}/maven-metadata.xml" | grep -A 1 "<extension>tar.gz</extension>" | grep "<value>" | sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//' || true)
            camunda_url="https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${camunda_version}/camunda-zeebe-${snap}.tar.gz"
        else
            camunda_url="https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${camunda_version}/camunda-zeebe-${camunda_version}.tar.gz"
        fi
        echo "[INFO] Caching Camunda distribution ${camunda_version} once for all nodes..."
        # shellcheck disable=SC2086
        if ! curl -fL ${netrc_opt} "${camunda_url}" -o "${tarball}"; then
            echo "[WARN] Failed to cache Camunda distribution; nodes will download it individually."
            rm -f "${tarball}"
        fi
    fi
    [[ -f "${tarball}" ]] && CACHED_TARBALL_PATH="${tarball}"

    # --- Connectors bundle ---
    if [[ -f "${jar}" ]]; then
        echo "[INFO] Reusing cached connectors bundle at ${jar}."
    else
        local jar_url=""
        if [[ "${connectors_version}" =~ SNAPSHOT ]]; then
            local snap=""
            # shellcheck disable=SC2086
            snap=$(curl -sfL ${netrc_opt} "https://artifacts.camunda.com/artifactory/connectors-snapshots/io/camunda/connector/connector-runtime-bundle/${connectors_version}/maven-metadata.xml" | grep -A 1 "<extension>pom</extension>" | grep "<value>" | sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//' || true)
            jar_url="https://artifacts.camunda.com/artifactory/connectors-snapshots/io/camunda/connector/connector-runtime-bundle/${connectors_version}/connector-runtime-bundle-${snap}-with-dependencies.jar"
        else
            jar_url="https://artifacts.camunda.com/artifactory/connectors/io/camunda/connector/connector-runtime-bundle/${connectors_version}/connector-runtime-bundle-${connectors_version}-with-dependencies.jar"
        fi
        echo "[INFO] Caching connectors bundle ${connectors_version} once for all nodes..."
        # shellcheck disable=SC2086
        if ! curl -fL ${netrc_opt} "${jar_url}" -o "${jar}"; then
            echo "[WARN] Failed to cache connectors bundle; nodes will download it individually."
            rm -f "${jar}"
        fi
    fi
    [[ -f "${jar}" ]] && CACHED_JAR_PATH="${jar}"

    [[ -n "${netrc_file}" ]] && rm -f "${netrc_file}"

    if [[ -n "${CACHED_TARBALL_PATH}" || -n "${CACHED_JAR_PATH}" ]]; then
        DISTRO_CACHE_READY=true
    fi
}

# Stage whichever cached artifacts exist onto the current node (${ip}), under the fixed path the
# install script looks at. Best-effort: a failure just means that node downloads it itself.
push_distro_cache_to_node() {
    remote_cmd "mkdir -p ${REMOTE_DISTRO_CACHE_DIR}" || { echo "[WARN] Could not prepare cache dir on ${ip}; it will download individually."; return 0; }

    if [[ -n "${CACHED_TARBALL_PATH}" && -f "${CACHED_TARBALL_PATH}" ]]; then
        if sftp -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" >/dev/null 2>&1 <<EOF
put "${CACHED_TARBALL_PATH}" "${REMOTE_DISTRO_CACHE_DIR}/camunda.tar.gz"
bye
EOF
        then
            remote_cmd "chmod 644 ${REMOTE_DISTRO_CACHE_DIR}/camunda.tar.gz" || true
        else
            echo "[WARN] Failed to stage cached distribution on ${ip}; it will download individually."
        fi
    fi

    if [[ -n "${CACHED_JAR_PATH}" && -f "${CACHED_JAR_PATH}" ]]; then
        if sftp -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" >/dev/null 2>&1 <<EOF
put "${CACHED_JAR_PATH}" "${REMOTE_DISTRO_CACHE_DIR}/connectors.jar"
bye
EOF
        then
            remote_cmd "chmod 644 ${REMOTE_DISTRO_CACHE_DIR}/connectors.jar" || true
        else
            echo "[WARN] Failed to stage cached connectors bundle on ${ip}; it will download individually."
        fi
    fi
}

check_tool_installed "ssh"
check_tool_installed "openssl"
check_tool_installed "sftp"
check_tool_installed "terraform"

echo "[INFO] CloudWatch monitoring is set to: $CLOUDWATCH_ENABLED."

echo "[INFO] Pulling information from the Terraform state file to configure the Camunda 8 environment or check preassigned values."

if [ -z "${IPS+x}" ]; then
    echo "[INFO] IPS was not overwritten via env vars... pulling from Terraform state file."
    IPS_JSON=$(terraform -chdir="$TERRAFORM_DIR" output -json camunda_ips)
    cleaned_str=$(echo "${IPS_JSON}" | tr -d '[]"')
    read -r -a IPS <<< "$(echo "${cleaned_str}" | tr ',' ' ')"
else
    # IPS env var can be supplied as "IP1 IP2 IP3"
    read -r -a IPS <<< "${IPS[@]}"
fi

echo "[INFO] Detected following values for IPS: ${IPS[*]}"

if [ -z "${BASTION_IP+x}" ]; then
    echo "[INFO] BASTION_IP was not overwritten via env vars... pulling from Terraform state file."
    BASTION_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw bastion_ip)
fi

echo "[INFO] Detected following values for the BASTION_IP: ${BASTION_IP}"

if [ -z "${OPENSEARCH_URL+x}" ]; then
    echo "[INFO] OPENSEARCH_URL was not overwritten via env vars... pulling from Terraform state file."
    OPENSEARCH_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw aws_opensearch_domain)
fi

echo "[INFO] Detected following values for the OPENSEARCH_URL: ${OPENSEARCH_URL}"

if [ -z "${GRPC_ENDPOINT+x}" ]; then
    echo "[INFO] GRPC_ENDPOINT was not overwritten via env vars... pulling from Terraform state file."
    GRPC_ENDPOINT=$(terraform -chdir="$TERRAFORM_DIR" output -raw nlb_endpoint)
fi

echo "[INFO] Detected following values for the GRPC_ENDPOINT: ${GRPC_ENDPOINT}"

MNT_DIR="/opt/camunda"

ips_list=""

for ip in "${IPS[@]}"; do
    ips_list+="${ip}:${BROKER_PORT},"
done

ips_list=${ips_list%,}
total_ip_count=${#IPS[@]}

# When a shared cache dir is configured (CI), download the distribution + connectors bundle once
# here so the per-node loop below copies them instead of each node hitting Artifactory.
if [[ -n "${CAMUNDA_DISTRO_CACHE_DIR}" ]]; then
    echo "[INFO] Distribution download cache enabled (CAMUNDA_DISTRO_CACHE_DIR=${CAMUNDA_DISTRO_CACHE_DIR})."
    warm_distro_cache
fi

# Loop over each IP address
# We're using source to call up child scripts with the same variable context
# The idea is to divide the logic into smaller scripts for better readability and maintainability
for index in "${!IPS[@]}"; do
    ip=${IPS[$index]}

    # Write credentials to a temp file on the remote host via stdin to avoid
    # leaking them in process listings or CI logs. The install script reads and
    # deletes this file. A separate SSH call is used so that the install script's
    # stdin remains clean (the script uses a heredoc internally).
    if [[ -n "${CAMUNDA_DISTRO_USER}" && -n "${CAMUNDA_DISTRO_PASSWORD}" ]]; then
        printf '%s\n%s\n' "${CAMUNDA_DISTRO_USER}" "${CAMUNDA_DISTRO_PASSWORD}" | \
            ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" \
            'cat > /tmp/.camunda-distro-credentials && chmod 600 /tmp/.camunda-distro-credentials'
    fi

    # Stage the pre-downloaded artifacts on the node. Always start from a clean node cache so a
    # previous install round (e.g. the upgrade test's other version) is never reused. No-op when
    # the cache is disabled.
    if [[ -n "${CAMUNDA_DISTRO_CACHE_DIR}" ]]; then
        remote_cmd "rm -rf ${REMOTE_DISTRO_CACHE_DIR}" || true
        if [[ "${DISTRO_CACHE_READY}" == "true" ]]; then
            push_distro_cache_to_node
        fi
    fi

    ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" < "${CURRENT_DIR}/camunda-install.sh"

    echo "[INFO] Attempting to connect to ${ip} to configure the Camunda 8 environment."

    # Creates temporary dynamic config file
    source "${CURRENT_DIR}/camunda-configure.sh"

    # Copy final config and enable all services
    source "${CURRENT_DIR}/camunda-services.sh"

    # Optionally install CloudWatch Agent
    if [[ $CLOUDWATCH_ENABLED == 'true' ]]; then
        ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" < "${CURRENT_DIR}/cloudwatch-install.sh"
        source "${CURRENT_DIR}/cloudwatch-configure.sh"
    fi
done

for ip in "${IPS[@]}"; do
    echo "[INFO] Doing final checks on the Camunda 8 environment on ${ip}."
    ssh -J "${ADMIN_USERNAME}@${BASTION_IP}" "${ADMIN_USERNAME}@${ip}" < "${CURRENT_DIR}/camunda-checks.sh"
    code=$?
    if [[ "$code" -ne 0 ]]; then
        echo "[FAIL] The Camunda 8 environment on ${ip} is not healthy."
        exit 1
    fi
done

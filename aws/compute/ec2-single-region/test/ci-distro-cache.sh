# shellcheck shell=bash
# CI-only helpers for caching the Camunda distribution + connectors bundle.
#
# This file is NOT part of the customer-facing reference procedure. It is sourced by
# aws/compute/ec2-single-region/procedure/all-in-one-install.sh ONLY when CAMUNDA_DISTRO_CACHE_LIB
# points at it (our CI sets that env var). It keeps the reference install scripts free of any
# download-caching plumbing.
#
# Why: the EC2 tests install Camunda on every node (x3) and on every install round (initial,
# CloudWatch, upgrade previous + current). Downloading the distribution tarball and the connectors
# uber-jar from Artifactory each time dominates the InfraEx Artifactory egress. Here we download
# each artifact ONCE on the orchestrator and stage it on every node instead.
#
# It relies on variables/functions provided by the sourcing script (all-in-one-install.sh):
#   CURRENT_DIR, BASTION_IP, ADMIN_USERNAME, CAMUNDA_DISTRO_USER, CAMUNDA_DISTRO_PASSWORD, remote_cmd
# and on CAMUNDA_DISTRO_CACHE_DIR (orchestrator-side cache dir) from the environment.
# shellcheck disable=SC2154  # BASTION_IP/ADMIN_USERNAME/CAMUNDA_DISTRO_* come from the sourcing script

# Where staged files land on each node. Must match camunda-install.sh's CAMUNDA_DISTRO_CACHE_DIR.
REMOTE_DISTRO_CACHE_DIR="/tmp/.camunda-distro-cache"

# Orchestrator-side cached files for the version currently being installed (empty when not cached).
CACHED_TARBALL_PATH=""
CACHED_JAR_PATH=""
DISTRO_CACHE_READY=false

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

# Download the Camunda distribution and connectors bundle once into CAMUNDA_DISTRO_CACHE_DIR.
# Files are keyed by version, so the upgrade test (previous -> current within the same job) never
# reuses the wrong artifact. Best-effort: on any failure the cache is left empty and nodes fall
# back to downloading individually.
# NOTE: keep the artifact URLs/resolution in sync with
#       generic/compute/debian/procedure/camunda-install.sh
warm_distro_cache() {
    DISTRO_CACHE_READY=false
    CACHED_TARBALL_PATH=""
    CACHED_JAR_PATH=""

    if [[ -z "${CAMUNDA_DISTRO_CACHE_DIR:-}" ]]; then
        return 0
    fi
    echo "[INFO] Distribution download cache enabled (CAMUNDA_DISTRO_CACHE_DIR=${CAMUNDA_DISTRO_CACHE_DIR})."

    # Parse the very same script piped to each node ("ssh ... < camunda-install.sh") so the cached
    # artifacts always match what the nodes install -- including the in-place edits the upgrade test
    # makes to this file. (env vars do NOT cross the SSH boundary; the node uses these defaults too.)
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
        echo "[INFO] Reusing cached Camunda distribution ${camunda_version} at ${tarball}."
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
        echo "[INFO] Reusing cached connectors bundle ${connectors_version} at ${jar}."
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

# Stage the cached artifacts (for the version currently being installed) onto a node, under the
# fixed path camunda-install.sh looks at. Always clears the node cache first so a previous install
# round (e.g. the upgrade test's other version) is never reused. Best-effort.
# Usage: push_distro_cache_to_node <node-ip>
push_distro_cache_to_node() {
    local ip="$1"

    remote_cmd "rm -rf ${REMOTE_DISTRO_CACHE_DIR} && mkdir -p ${REMOTE_DISTRO_CACHE_DIR}" \
        || { echo "[WARN] Could not prepare cache dir on ${ip}; it will download individually."; return 0; }

    if [[ "${DISTRO_CACHE_READY}" != "true" ]]; then
        return 0
    fi

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

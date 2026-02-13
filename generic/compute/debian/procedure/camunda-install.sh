#!/bin/bash
set -euo pipefail

# This script installs Java, Camunda 8 and Connectors on a remote server.
# The script assumes that the remote server is running a Debian-based operating system.

# Example usage via jump host
# ssh -J admin@BASTION_IP admin@CAMUNDA_IP < ./camunda-install.sh
# Or wget the script on the remote host and execute it directly

# Executed on remote host, defaults should be set here or env vars preconfigured on remote host
OPENJDK_VERSION=${OPENJDK_VERSION:-"21"}
# renovate: datasource=github-releases depName=camunda/camunda versioning=regex:^8\.8?(\.(?<patch>\d+))?$
CAMUNDA_VERSION=${CAMUNDA_VERSION:-"8.8.11"}
# TODO: [release-duty] adjust renovate comment to bump the minor version to the new stable release
# renovate: datasource=github-releases depName=camunda/connectors versioning=regex:^8\.8?(\.(?<patch>\d+))?$
CAMUNDA_CONNECTORS_VERSION=${CAMUNDA_CONNECTORS_VERSION:-"8.8.7"}

MNT_DIR=${MNT_DIR:-"/opt/camunda"}
USERNAME=${USERNAME:-"camunda"}
JAVA_OPTS="${JAVA_OPTS:- -Xmx512m}" # Default Java options, required to run commands as remote user
CAMUNDA_SNAPSHOT_VERSION=""
CONNECTORS_SNAPSHOT_VERSION=""

# Check that the operating system is Debian-based
if ! grep -qE "ID=(debian|ubuntu)" /etc/os-release && ! grep -q "ID_LIKE=.*debian" /etc/os-release; then
    echo "[FAIL] The operating system is not Debian-based."
    exit 1
fi

# Install Temuring OpenJDK
sudo apt-get update
sudo apt-get install -y wget apt-transport-https gpg
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list

sudo apt-get update
sudo apt-get install -y "temurin-${OPENJDK_VERSION}-jdk"

JAVA_VERSION=$(java -version 2>&1 | awk -F[\"_] '/version/ {print $2}')

# Check if the Java version matches the expected OpenJDK version
if [[ ! "$JAVA_VERSION" =~ $OPENJDK_VERSION ]]; then
    echo "[FAIL] Java version does not match the expected version."
    echo "Expected: $OPENJDK_VERSION, but found: $JAVA_VERSION"
    exit 1
fi

# Create extra user and group for Camunda
if ! id -u "$USERNAME" &>/dev/null; then
    sudo useradd -m "$USERNAME"
fi

if ! getent group "$USERNAME" &>/dev/null; then
    sudo groupadd "$USERNAME"
fi

if id -nG "$USERNAME" | grep -qw "$USERNAME"; then
    sudo usermod -aG "$USERNAME" "$USERNAME"
fi

# Configs will automatically be newly generated etc. based on this repo / customer changes.
# Upgrade will explicitly remove the old libs and replace all files with the new ones.

sudo chown -R "${USERNAME}:${USERNAME}" "${MNT_DIR}/"

if [[ "${CAMUNDA_VERSION}" =~ "SNAPSHOT" ]]; then
    echo "[INFO] Fetching the latest snapshot version of Camunda ${CAMUNDA_VERSION}."
    CAMUNDA_SNAPSHOT_VERSION=$(curl -s "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/maven-metadata.xml" | grep -A 1 "<extension>tar.gz</extension>" | \
        grep "<value>" | \
        sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//')
    echo "[INFO] Latest snapshot version is ${CAMUNDA_SNAPSHOT_VERSION}."
fi

if [[ "${CAMUNDA_CONNECTORS_VERSION}" =~ "SNAPSHOT" ]]; then
    echo "[INFO] Fetching the latest snapshot version of Camunda Connectors ${CAMUNDA_CONNECTORS_VERSION}."
    CONNECTORS_SNAPSHOT_VERSION=$(curl -s "https://artifacts.camunda.com/artifactory/connectors-snapshots/io/camunda/connector/connector-runtime-bundle/${CAMUNDA_CONNECTORS_VERSION}/maven-metadata.xml" | grep -A 1 "<extension>pom</extension>" | \
        grep "<value>" | \
        sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//')
    echo "[INFO] Latest snapshot version is ${CONNECTORS_SNAPSHOT_VERSION}."
fi

sudo -u "${USERNAME}" bash <<EOF

if [ -d "${MNT_DIR}/camunda/" ]; then
    echo "[INFO] Detected existing Camunda installation. Stopping Camunda services if running."
    sudo systemctl stop camunda || true
    sudo systemctl stop camunda-connectors || true

    echo "[INFO] Removing existing JARs and overwriting / recreating configuration files."
    rm -rf "${MNT_DIR}/camunda/lib/"
fi

# Install Camunda 8

if [[ "${CAMUNDA_VERSION}" =~ "SNAPSHOT" ]]; then
    curl -L "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/camunda-zeebe-${CAMUNDA_SNAPSHOT_VERSION}.tar.gz" -o "${MNT_DIR}/camunda.tar.gz"
else
    curl -L "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/camunda-zeebe-${CAMUNDA_VERSION}.tar.gz" -o "${MNT_DIR}/camunda.tar.gz"
fi

mkdir -p "${MNT_DIR}/camunda"
tar -xzvf "${MNT_DIR}/camunda.tar.gz" -C "${MNT_DIR}/camunda" --strip-components=1
rm -rf "${MNT_DIR}/camunda.tar.gz"

# Install Connectors

mkdir -p "${MNT_DIR}/connectors/"

if [[ "${CAMUNDA_CONNECTORS_VERSION}" =~ "SNAPSHOT" ]]; then
    curl -L "https://artifacts.camunda.com/artifactory/connectors-snapshots/io/camunda/connector/connector-runtime-bundle/${CAMUNDA_CONNECTORS_VERSION}/connector-runtime-bundle-${CONNECTORS_SNAPSHOT_VERSION}-with-dependencies.jar" -o "${MNT_DIR}/connectors/connectors.jar"
else
    curl -L "https://artifacts.camunda.com/artifactory/connectors/io/camunda/connector/connector-runtime-bundle/${CAMUNDA_CONNECTORS_VERSION}/connector-runtime-bundle-${CAMUNDA_CONNECTORS_VERSION}-with-dependencies.jar" -o "${MNT_DIR}/connectors/connectors.jar"
fi

curl -L https://raw.githubusercontent.com/camunda/connectors/main/bundle/default-bundle/start.sh -o "${MNT_DIR}/connectors/start.sh"
chmod +x "${MNT_DIR}/connectors/start.sh"

# shellcheck disable=SC2016
sed -i '$ s@.*@java ${JAVA_OPTS} -cp "'"${MNT_DIR}/connectors/*"'" "io.camunda.connector.runtime.app.ConnectorRuntimeApplication"@' "${MNT_DIR}/connectors/start.sh"
EOF

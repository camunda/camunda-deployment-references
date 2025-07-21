#!/bin/bash
set -euo pipefail

# This script installs Java, Camunda 8 and Connectors on a remote server.
# The script assumes that the remote server is running a Debian-based operating system.

# Example usage via jump host
# ssh -J admin@BASTION_IP admin@CAMUNDA_IP < ./camunda-install.sh

# Executed on remote host, defaults should be set here or env vars preconfigured on remote host
OPENJDK_VERSION=${OPENJDK_VERSION:-"21"}
# renovate: datasource=github-releases depName=camunda/camunda versioning=regex:^8\.6?(\.(?<patch>\d+))?$
CAMUNDA_VERSION=${CAMUNDA_VERSION:-"8.8.0-alpha6"}
# renovate: datasource=github-releases depName=camunda/connectors versioning=regex:^8\.6?(\.(?<patch>\d+))?$
CAMUNDA_CONNECTORS_VERSION=${CAMUNDA_CONNECTORS_VERSION:-"8.8.0-alpha6"}
MNT_DIR=${MNT_DIR:-"/opt/camunda"}
USERNAME=${USERNAME:-"camunda"}
JAVA_OPTS="${JAVA_OPTS:- -Xmx512m}" # Default Java options, required to run commands as remote user
VERSION=""

# Check that the operating system is Debian
if ! grep -q "ID=debian" /etc/os-release; then
    echo "[FAIL] The operating system is not Debian."
    exit 1
fi

# Install Temuring OpenJDK
sudo apt update
sudo apt install -y wget apt-transport-https gpg
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list

sudo apt update
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
# The following may be enough already, will need proper Camunda alpha versions to test it.
# Backup of data folder may be useless since the new version will migrate the database and render any older version usless.

sudo chown -R "${USERNAME}:${USERNAME}" "${MNT_DIR}/"

if [[ "${CAMUNDA_VERSION}" =~ "SNAPSHOT" ]]; then
    echo "[INFO] Fetching the latest snapshot version of Camunda ${CAMUNDA_VERSION}."
    VERSION=$(curl -s "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/maven-metadata.xml" | grep -A 1 "<extension>tar.gz</extension>" | \
        grep "<value>" | \
        sed -e 's/<[^>]*>//g' -e 's/^[ \t]*//')
fi

sudo -u "${USERNAME}" bash <<EOF

if [ -d "${MNT_DIR}/camunda/" ]; then
    echo "[INFO] Detected existing Camunda installation. Removing existing JARs and overwriting / recreating configuration files."
    rm -rf "${MNT_DIR}/camunda/lib/"
fi

# Install Camunda 8

if [[ "${CAMUNDA_VERSION}" =~ "SNAPSHOT" ]]; then
    curl -L "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/camunda-zeebe-${VERSION}.tar.gz" -o "${MNT_DIR}/camunda.tar.gz"
else
    curl -L "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/camunda-zeebe-${CAMUNDA_VERSION}.tar.gz" -o "${MNT_DIR}/camunda.tar.gz"
fi

mkdir -p "${MNT_DIR}/camunda"
tar -xzvf "${MNT_DIR}/camunda.tar.gz" -C "${MNT_DIR}/camunda" --strip-components=1
rm -rf "${MNT_DIR}/camunda.tar.gz"

# Install Connectors

mkdir -p "${MNT_DIR}/connectors/"

curl -L "https://artifacts.camunda.com/artifactory/connectors/io/camunda/connector/connector-runtime-bundle/${CAMUNDA_CONNECTORS_VERSION}/connector-runtime-bundle-${CAMUNDA_CONNECTORS_VERSION}-with-dependencies.jar" -o "${MNT_DIR}/connectors/connectors.jar"
curl -L https://raw.githubusercontent.com/camunda/connectors/main/bundle/default-bundle/start.sh -o "${MNT_DIR}/connectors/start.sh"
chmod +x "${MNT_DIR}/connectors/start.sh"

# shellcheck disable=SC2016
sed -i '$ s@.*@java ${JAVA_OPTS} -cp "'"${MNT_DIR}/connectors/*"'" "io.camunda.connector.runtime.app.ConnectorRuntimeApplication"@' "${MNT_DIR}/connectors/start.sh"
EOF

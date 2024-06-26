#!/bin/bash

# This script installs Java, Camunda 8 and Connectors on a remote server.
# The script assumes that the remote server is running a Debian-based operating system.

# Example usage via jump host
# ssh -J admin@3.68.92.82 admin@10.200.9.113 < ./camunda-install.sh

OPENJDK_VERSION=${OPENJDK_VERSION:-"21"}
CAMUNDA_VERSION=${CAMUNDA_VERSION:-"8.6.0-alpha2"}
CAMUNDA_CONNECTORS_VERSION=${CAMUNDA_CONNECTORS_VERSION:-"8.6.0-alpha2.1"}
MNT_DIR=${MNT_DIR:-"/camunda"}

# Check that the operating system is Debian

if ! grep -q "ID=debian" /etc/os-release; then
    echo "The operating system is not Debian."
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
    echo "Java version does not match the expected version."
    echo "Expected: $OPENJDK_VERSION, but found: $JAVA_VERSION"
    exit 1
fi

# TODO: Introduce update procedure for C8 and Connectors. Backup files, delete jars etc. Otherwise one can continue with the same procedure.
# Configs will automatically be newly generated etc. based on this repo / customer changes.
# The following may be enough already, will need proper Camunda alpha versions to test it.
# Backup of data folder may be useless since the new version will migrate the database and render any older version usless.

if [ -d "${MNT_DIR}/camunda/" ]; then
    echo "Detected existing Camunda installation. Removing existing JARs and overwriting / recreating configuration files."
    rm -rf "${MNT_DIR}/camunda/lib/"
fi

# Install Camunda 8

curl -L "https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/camunda-zeebe-${CAMUNDA_VERSION}.tar.gz" -o "${MNT_DIR}/camunda.tar.gz"

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

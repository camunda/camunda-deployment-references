#!/bin/bash

# Example usage via jump host
# ssh -A -J admin@3.68.92.82 admin@10.200.9.113 < ./camunda-install.sh

OPENJDK_VERSION=21
CAMUNDA_VERSION=8.6.0-alpha2
MNT_DIR="/camunda"

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
sudo apt-get install -y temurin-${OPENJDK_VERSION}-jdk

JAVA_VERSION=$(java -version 2>&1 | awk -F[\"_] '/version/ {print $2}')

# Check if the Java version matches the expected OpenJDK version
if [[ ! "$JAVA_VERSION" =~ $OPENJDK_VERSION ]]; then
    echo "Java version does not match the expected version."
    echo "Expected: $OPENJDK_VERSION, but found: $JAVA_VERSION"
    exit 1
fi

# TODO: check if camunda exists if maybe put in different folder, otherwise download and unpack

curl -L https://artifacts.camunda.com/artifactory/zeebe/io/camunda/camunda-zeebe/${CAMUNDA_VERSION}/camunda-zeebe-${CAMUNDA_VERSION}.tar.gz -o ${MNT_DIR}/camunda.tar.gz

mkdir ${MNT_DIR}/camunda
tar -xzvf ${MNT_DIR}/camunda.tar.gz -C ${MNT_DIR}/camunda --strip-components=1
rm -rf ${MNT_DIR}/camunda.tar.gz

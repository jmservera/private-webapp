#!/bin/bash
set -e

echo "Installing required packages."

# Update package lists
apt-get update && apt-get upgrade -y

# Install required packages
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  jq \
  git \
  unzip \
  nodejs \
  npm \
  libicu70 \
  libssl3

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Add user to docker group
gpasswd -a $USER docker

# Print completion message
echo "Package installation completed successfully!"
RUNAS="sudo -iu $USER"

$RUNAS bash<<_
set -e
echo "Installing the self-hosted runner..."
# Create a folder
if [ -d "actions-runner" ]; then
  echo "actions-runner already exist, installer not needed."
  exit 0
else
  mkdir actions-runner && cd actions-runner
  # Download the latest runner package
  curl -O -L https://github.com/actions/runner/releases/download/v2.320.1/actions-runner-linux-x64-2.320.1.tar.gz
  # Extract the installer
  tar xzf ./actions-runner-linux-x64-2.320.1.tar.gz

  echo "Runner package extracted successfully!"

  #
  #    Review how to get the runner PAT from the GitHub pat using the reg token
  #    //         "name": "REGISTRATION_TOKEN_API_URL",
  #    //         "value": "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/registration-token"
  #

  echo "Configuring the self-hosted runner with user ${USER}..."
  ./config.sh --url "https://github.com/${REPO_OWNER}/${REPO_NAME}" --token "${GITHUB_REPO_TOKEN}" --labels  self-hosted --unattended
  echo "Runner configured successfully!"
  echo "Installing the self-hosted runner as a service..."
  sudo ./svc.sh install
  echo "Runner installed successfully!"
  echo "Starting the self-hosted runner service..."
  sudo ./svc.sh start
  echo "Runner service started successfully!"
fi
_

echo "Self-hosted runner installation completed successfully!"

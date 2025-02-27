#!/bin/bash
set -e

ORIGINAL_USR=$(whoami)
echo "Installing required packages."

# Update package lists
apt-get update

# Install required packages
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  docker.io \
  jq \
  git \
  unzip \
  nodejs \
  npm \
  libicu70 \
  libssl3
# Enable and start Docker
systemctl enable docker
systemctl start docker


# Print completion message
echo "Package installation completed successfully for user ${ORIGINAL_USR}!"

# Create a folder
mkdir actions-runner && cd actions-runner
# Download the latest runner package
curl -O -L https://github.com/actions/runner/releases/download/v2.320.1/actions-runner-linux-x64-2.320.1.tar.gz
# Extract the installer
tar xzf ./actions-runner-linux-x64-2.320.1.tar.gz

echo "Runner package extracted successfully!"

echo "Configuring the self-hosted runner with user ${USER}..."
sudo -u $USER bash -c "config.sh --url \"https://github.com/$REPO_OWNER/$REPO_NAME\" --token \"$GITHUB_PAT\""

echo "Runner configured successfully!"
echo "Installing the self-hosted runner as a service..."
./svc.sh install
echo "Runner installed successfully!"
echo "Starting the self-hosted runner service..."
./svc.sh start
echo "Runner service started successfully!"
#!/bin/bash
set -e

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
echo "Package installation completed successfully!"

# Create a folder
mkdir actions-runner && cd actions-runner
# Download the latest runner package
curl -O -L https://github.com/actions/runner/releases/download/v2.320.1/actions-runner-linux-x64-2.320.1.tar.gz
# Extract the installer
tar xzf ./actions-runner-linux-x64-2.320.1.tar.gz

./config.sh --url https://github.com/$REPO_OWNER/$REPO_NAME --token $GITHUB_PAT  --labels  self-hosted,oracle-vm-runner

./svc.sh install
./svc.sh start
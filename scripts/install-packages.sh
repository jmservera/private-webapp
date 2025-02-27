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
  unzip

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Install GitHub runner dependencies
apt-get install -y \
  libicu70 \
  libssl3

# Print completion message
echo "Package installation completed successfully!"
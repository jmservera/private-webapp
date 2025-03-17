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

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# Add user to docker group
gpasswd -a $USER docker

# Install GitHub CLI if not already installed
if ! command -v gh &> /dev/null; then
  echo "Installing GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install gh -y
fi

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# create folder if not exist
if [ ! -d "/home/$USER/.ssh" ]; then
  mkdir -p /home/$USER/.ssh
  chmod 700 /home/$USER/.ssh
fi

echo "Package installation completed successfully!"

echo "GitHub Login"
# login to GitHub
echo "${GITHUB_PAT}" | gh auth login --with-token  

# in NUM_RUNNERS is not set, default to 2
NUM_RUNNERS=${NUM_RUNNERS:-2}
# loop n times
for i in $(seq 1 $NUM_RUNNERS); do
  echo "Installing the self-hosted runner for ${REPO_OWNER}/${REPO_NAME}... for user ${USER}"

  # get the runner token
  export GITHUB_RUNNER_TOKEN=$(gh api -X POST "/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/registration-token" -q .token)
  export GITHUB_RUNNER_NAME="${REPO_NAME}-runner-${i}"  
  # Keep in mind that all the bash variables are replaced before running the script
  # as the script is generated in-place, replacing all the variables before sending it
  # to bash. If you need to use any variable that is assigned in the script, escape the $ sign.
  sudo -iu $USER bash<<_
set -e
echo "Installing the self-hosted runner for ${REPO_OWNER}/${REPO_NAME}... for user ${USER}"
if [ ! -d "${GITHUB_RUNNER_NAME}" ]; then
  mkdir ${GITHUB_RUNNER_NAME}
  cd ${GITHUB_RUNNER_NAME}  

  # Download the latest runner package
  curl -O -L https://github.com/actions/runner/releases/download/v2.320.1/actions-runner-linux-x64-2.320.1.tar.gz

  # TODO: create as many runners as needed
  # Extract the installer
  tar xzf ./actions-runner-linux-x64-2.320.1.tar.gz

  echo "Runner package extracted successfully!"

  echo "Configuring the self-hosted runner with user ${USER}..."
  ./config.sh --url "https://github.com/${REPO_OWNER}/${REPO_NAME}" --token "${GITHUB_RUNNER_TOKEN}" --name "${GITHUB_RUNNER_NAME}" --labels  self-hosted --unattended --replace
  echo "Runner configured successfully!"
  echo "Installing the self-hosted runner as a service..."
  sudo ./svc.sh install
  echo "Runner installed successfully!"
  echo "Starting the self-hosted runner service..."
  sudo ./svc.sh start
  echo "Runner service started successfully!"
  # echo "GITHUB_RUNNER_TOKEN=${GITHUB_RUNNER_TOKEN}" > ~/.env
fi
_

done

cd /home/$USER

if [ -f ".env" ]; then
  echo "Sourcing .env file..."
  set -a
  source .env
  set +a  
  cat .env
  echo "Self-hosted runner installation completed successfully!"
  echo "#DATA ${GITHUB_RUNNER_TOKEN} #DATA"
else
  echo ".env file not found, installer may have failed..."
fi

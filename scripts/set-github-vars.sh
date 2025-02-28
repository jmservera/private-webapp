#!/bin/bash

# This script sets up GitHub repository variables needed for the workflow

# Check if required environment variables are set
if [ -z "$GITHUB_PAT" ] || [ -z "$REPO_OWNER" ] || [ -z "$REPO_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
  echo "Error: Required environment variables not set."
  echo "Please set GITHUB_PAT, REPO_OWNER, REPO_NAME, and RESOURCE_GROUP."
  exit 1
fi

# Get ACR name from Azure
ACR_NAME=$(az acr list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)

# Get web app names
FRONTEND_APP_NAME=$(az webapp list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'frontend')].name" -o tsv)
BACKEND_APP_NAME=$(az webapp list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'backend')].name" -o tsv)

if [ -z "$ACR_NAME" ] || [ -z "$FRONTEND_APP_NAME" ] || [ -z "$BACKEND_APP_NAME" ]; then
  echo "Error: Could not retrieve all necessary resources from Azure."
  exit 1
fi

# Set GitHub repository variables using GitHub CLI
# First, install GitHub CLI if not already installed
if ! command -v gh &> /dev/null; then
  echo "Installing GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install gh -y
fi

# Login to GitHub
echo $GITHUB_PAT | gh auth login --with-token

# Set variables
echo "Setting GitHub repository variables..."
gh variable set RESOURCE_GROUP -b "$RESOURCE_GROUP" --repo $REPO_OWNER/$REPO_NAME
gh variable set ACR_NAME -b "$ACR_NAME" --repo $REPO_OWNER/$REPO_NAME
gh variable set FRONTEND_APP_NAME -b "$FRONTEND_APP_NAME" --repo $REPO_OWNER/$REPO_NAME
gh variable set BACKEND_APP_NAME -b "$BACKEND_APP_NAME" --repo $REPO_OWNER/$REPO_NAME

echo "GitHub variables set successfully!"

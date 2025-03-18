# WebApp with Private Backend and Database

This repository demonstrates deploying a secure web application architecture on Azure, featuring a publicly accessible frontend, a private backend, and a private SQL database. It leverages Azure private endpoints, VNet integration, managed identities, and GitHub Actions for CI/CD automation.

## Architecture Overview

The solution deploys the following Azure resources:

- **Virtual Network (VNet)** with four subnets:
  - **App subnet**: Hosts frontend and backend web apps with VNet integration.
  - **Private subnet**: Dedicated to private endpoints for secure internal communication.
  - **VM subnet**: Hosts the GitHub Actions self-hosted runner VM.
  - **CI subnet**: Used by deployment scripts running in Azure Container Instances.
- **Frontend Web App**: Publicly accessible, communicates securely with the backend via private endpoints.
- **Backend Web App**: Private access only, uses a user-assigned managed identity for secure database access.
- **Azure SQL Database**: Private access via private endpoint, initialized with custom scripts.
- **Azure Container Registry (ACR)**: Stores Docker images for frontend and backend applications.
- **GitHub Runner VM**: Self-hosted runner for secure CI/CD within the private network.
- **Application Insights**: Integrated telemetry and monitoring for frontend and backend applications.

### Network Architecture

The solution uses a single VNet with clearly defined subnets and private endpoints to secure internal communication:

- **Frontend Web App**: Publicly accessible, connects securely to the backend via private endpoints.
- **Backend Web App**: Not publicly accessible, communicates securely with the SQL database via private endpoints.
- **GitHub Runner VM**: Deployed within the same VNet, enabling secure CI/CD operations and access to private resources.

## Prerequisites

Before deploying, ensure you have:

1. Azure CLI installed and authenticated.
1. [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/) extension installed.
2. GitHub repository for your application code.
3. GitHub Personal Access Token (PAT) with appropriate permissions:
    * Actions Access: Read-only
    * Administration Access: Read and write
    * Metadata Access: Read-only
    * Secrets Access: Read and write
    * Variables Access: Read and write



## Deployment

Use the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/) to deploy the solution:

```bash
az login
azd up
```

You'll be prompted for:

- Environment name (prefix for resources)
- Azure region for deployment
- SQL administrator username and password
- GitHub repository owner and name
- GitHub PAT for GitHub Actions


## GitHub Actions Runner Setup

The GitHub Actions runner is automatically configured during deployment via a custom VM extension script ([`scripts/install-packages.sh`](scripts/install-packages.sh)). This script:

- Installs required packages (Docker, Azure CLI, GitHub CLI).
- Registers the VM as a self-hosted runner in your GitHub repository.
- Configures multiple runner instances for parallel CI/CD jobs.

To verify or manage runners:

1. Navigate to your GitHub repository.
2. Go to **Settings** > **Actions** > **Runners**.
3. Confirm the self-hosted runners are online and correctly configured.

## Database Initialization

The SQL database is initialized automatically during deployment using a custom Azure deployment script ([`scripts/create-sql-user.sh`](scripts/create-sql-user.sh)). This script:

- Creates a database user linked to the backend's managed identity.
- Assigns appropriate database roles (`db_datareader`, `db_datawriter`, `db_ddladmin`).
- Creates the required tables (`Value_Store`) if they don't exist.

Ensure the deployment script is correctly referenced in your Bicep files ([`infra/modules/sqlDatabase.bicep`](infra/modules/sqlDatabase.bicep)).

## Telemetry and Monitoring

Both frontend and backend applications integrate with Azure Application Insights for comprehensive telemetry:

- **Backend** ([`src/backend/app.py`](src/backend/app.py)):
  - Uses OpenTelemetry instrumentation for Flask and database interactions.
  - Sends logs, metrics, and traces to Application Insights.

- **Frontend** ([`src/frontend/app.py`](src/frontend/app.py)):
  - Uses OpenTelemetry instrumentation for Flask.
  - Captures user interactions, HTTP requests, and errors.

Telemetry is configured via the `APPLICATIONINSIGHTS_CONNECTION_STRING` environment variable, automatically set during deployment.

## Security Features

- **HTTPS and TLS 1.2** enforced on all web apps.
- **Private endpoints** for secure internal communication between frontend, backend, and database.
- **Firewall rules** restrict external access to sensitive resources.
- **Managed identities** used for secure, passwordless authentication.
- **VNet integration** ensures secure network isolation and communication.

## Scripts Overview

The repository includes several scripts to automate setup and management tasks:

- [`scripts/install-packages.sh`](scripts/install-packages.sh): Installs dependencies and configures GitHub Actions runners on the VM. By default, it creates two runner instances for parallel CI/CD jobs.
- [`scripts/create-sql-user.sh`](scripts/create-sql-user.sh): Initializes the SQL database and configures the managed identity access. Uses a trick to avoid needing a highly privileged user for adding the managed identity to the database.
- [`scripts/set-github-vars.sh`](scripts/set-github-vars.sh): Sets GitHub repository variables required for CI/CD workflows after running `azd up`. Then it launches the CI/CD pipeline.


These scripts are automatically executed during deployment and VM provisioning.

## Next Steps

- Customize the frontend and backend applications as needed.
- Regularly review and update dependencies using Dependabot ([`.github/dependabot.yml`](.github/dependabot.yml)).

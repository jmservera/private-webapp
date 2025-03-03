# WebApp with private backend and database

This is an example deployment where you have a web app with a Frontend that has a public endpoint, but the backend and database are private. It makes use of private endpoints and vnet integration.
As the backend and database are private, the frontend needs to be able to communicate with them. This is done by using a private endpoint for the backend and a private link for the database.
To be able to deploy the source code to the backend using GitHub Actions, you need to setup a GitHub runner in the same vnet as the backend. This is done by using a self-hosted runner configured by a custom script that runs during the VM setup.
For the database, we also need to run an initialization script to create the database and tables. This is done by using a custom script that will run during initialization using a Microsoft.Resources/deploymentScripts definition, which is a part of the ARM template. This script will run once when the database is created.

## Architecture

This solution deploys the following components:

- **Virtual Network** with three subnets:
  - App subnet (for web app integration)
  - Private subnet (for private endpoints)
  - VM subnet (for GitHub runner)
- **Frontend Web App** with public access
- **Backend Web App** with private access and managed identity
- **SQL Database** with private endpoint
- **Container Registry** for storing Docker images
- **GitHub Runner VM** for CI/CD automation
- **Application Insights** for monitoring

### Network Architecture

The solution uses a hub-and-spoke network architecture with private endpoints to secure communication:

1. The Frontend Web App is publicly accessible but connects to the backend through private endpoints
2. The Backend Web App is not publicly accessible and communicates with the database through private endpoints
3. The GitHub Runner VM is deployed within the same VNet to access private resources

## Prerequisites

Before deploying, you'll need:

1. Azure CLI installed and authenticated
2. GitHub repository for your application code
3. GitHub Personal Access Token (PAT) with appropriate permissions
4. SSH public key for the GitHub runner VM authentication

## Deployment

You can use the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/) to deploy this example. First, you need to login to your Azure account:

```bash
az login
```

Then you can run the following command to deploy the resources:

```bash
azd up
```

The deployment will prompt you for the following parameters:

- Environment name (used as prefix for resources)
- Location for deployment
- SQL administrator username and password
- GitHub repository owner and name
- GitHub PAT and token for GitHub Actions
- SSH public key for VM authentication

## Setting up GitHub Runner

To deploy the source code to the backend using GitHub Actions, you need to set up a GitHub runner in the same VNet as the backend. This is done by using a self-hosted runner configured by a custom script that runs during the VM setup.

1. Navigate to your GitHub repository.
2. Go to **Settings** > **Actions** > **Runners**.
3. Follow the instructions to add a new self-hosted runner.
4. Ensure the runner is configured to run in the same VNet as the backend.

## Initializing the Database

To initialize the database and create the necessary tables, a custom script will run during the initialization using a `Microsoft.Resources/deploymentScripts` definition, which is part of the ARM template.

1. Ensure the deployment script is defined in your Bicep files.
2. The script will automatically run once when the database is created.
3. Verify the database and tables are created successfully.

## Managed Identities

This solution uses user-assigned managed identities for:

1. **Backend Web App** - To securely connect to the SQL database using Azure AD authentication
2. **GitHub Runner VM** - To manage deployments and interact with Azure resources

These identities are granted specific RBAC permissions to minimize access based on the principle of least privilege.

## Security Features

- All services use HTTPS and TLS 1.2
- Private endpoints for backend and database connections
- Firewall rules limiting access to resources
- Managed identities for authentication instead of passwords where possible
- VNET integration for secure network communication

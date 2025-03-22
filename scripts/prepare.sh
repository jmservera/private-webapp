#!/bin/sh
echo "Setting up environment variables..."
azd env set CLIENT_IP_ADDRESS $(curl ifconfig.me 2>/dev/null | tr -d '\r')

FALLBACK_CONTAINER="DOCKER|mcr.microsoft.com/appsvc/staticsite:latest"
AZURE_ENV_NAME=$(azd env get-value "AZURE_ENV_NAME")

FRONTEND_APP_NAME="${AZURE_ENV_NAME}-frontend"
BACKEND_APP_NAME="${AZURE_ENV_NAME}-backend"

LASTSTATUS=$?
if [ $LASTSTATUS -ne 0 ]; then
echo "Error: Could not get environment variables"
fi

RESOURCE_GROUP=$(azd env get-value "RESOURCE_GROUP" || echo "ERROR")
case "$RESOURCE_GROUP" in
*ERROR*) RESOURCE_GROUP=""
    echo "Error: Could not get resource group" 
    ;;
*) FRONTEND_CONTAINER_IMAGE=$(azd env get-value "FRONTEND_CONTAINER_IMAGE" || echo "ERROR")
    case "$FRONTEND_CONTAINER_IMAGE" in
    *ERROR*) FRONTEND_CONTAINER_IMAGE="";;
    esac

    BACKEND_CONTAINER_IMAGE=$(azd env get-value "BACKEND_CONTAINER_IMAGE" || echo "ERROR")

    case "$BACKEND_CONTAINER_IMAGE" in
    *ERROR*) BACKEND_CONTAINER_IMAGE="";;
    esac

    if [ -z "$FRONTEND_CONTAINER_IMAGE" ]; then FRONTEND_CONTAINER_IMAGE=$FALLBACK_CONTAINER; fi
    if [ -z "$BACKEND_CONTAINER_IMAGE" ]; then BACKEND_CONTAINER_IMAGE=$FALLBACK_CONTAINER; fi

    FRONTEND_CONTAINER_IMAGE=$(az webapp show --resource-group "${RESOURCE_GROUP}" --name "${FRONTEND_APP_NAME}" --query "siteConfig.linuxFxVersion" -o tsv || echo $FRONTEND_CONTAINER_IMAGE)
    BACKEND_CONTAINER_IMAGE=$(az webapp show --resource-group "${RESOURCE_GROUP}" --name "${BACKEND_APP_NAME}" --query "siteConfig.linuxFxVersion" -o tsv || echo $BACKEND_CONTAINER_IMAGE)

    azd env set FRONTEND_CONTAINER_IMAGE $FRONTEND_CONTAINER_IMAGE
    azd env set BACKEND_CONTAINER_IMAGE $BACKEND_CONTAINER_IMAGE 
    ;;
esac

echo "Done"
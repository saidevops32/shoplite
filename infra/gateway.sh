#!/usr/bin/env bash
# Creates the Application Gateway. Run it in Cloud Shell after the apps are deployed. Safe to re-run.
set -euo pipefail

RG=shoplite-rg
VNET=shoplite-vnet
ENV_NAME=shoplite-env
GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DOMAIN=$(az containerapp env show -g $RG -n $ENV_NAME --query properties.defaultDomain -o tsv)
echo "Apps domain: $DOMAIN"

echo ">> Checking the template (nothing is created yet)"
az deployment group validate -g $RG --template-file infra/gateway.bicep --parameters vnetName=$VNET appsDomain=$DOMAIN -o none

echo ">> Creating the gateway (8 to 10 minutes)"
IP=$(az deployment group create -g $RG -n shoplite-gateway --template-file infra/gateway.bicep --parameters vnetName=$VNET appsDomain=$DOMAIN --query properties.outputs.ip.value -o tsv)

gh variable set APP_URL --repo $GH_REPO --body "http://$IP"
echo
echo "Gateway ready: http://$IP"
echo "Test it:  bash infra/smoke.sh http://$IP"

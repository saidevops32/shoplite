#!/usr/bin/env bash
# ShopLite infrastructure. Safe to re-run: every step checks before it creates.
set -euo pipefail

LOC=${LOC:-southeastasia}
RG=shoplite-rg
VNET=shoplite-vnet
ENV_NAME=shoplite-env
GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
GH_OWNER=${GH_REPO%%/*}
GH_NAME=${GH_REPO##*/}

SUFFIX=${SUFFIX:-}
if [ -z "$SUFFIX" ]; then SUFFIX=$(az acr list -g $RG --query "[0].name" -o tsv 2>/dev/null | sed 's/^shopliteacr//') || true; fi
if [ -z "$SUFFIX" ]; then SUFFIX=$(openssl rand -hex 3); fi
ACR=shopliteacr$SUFFIX
PG=shoplite-pg-$SUFFIX
MYSQL=shoplite-mysql-$SUFFIX
IDENTITY=id-shoplite-$SUFFIX
PG_DNS=shoplite-pg.postgres.database.azure.com
MYSQL_DNS=shoplite-my.mysql.database.azure.com
PG_PASSWORD=$(openssl rand -hex 24)
MYSQL_PASSWORD=$(openssl rand -hex 24)
RABBIT_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$(openssl rand -hex 32)

step() { echo; echo ">> $*"; }

ensure_role() {
  local who=$1 role=$2 scope=$3 n i
  n=$(az role assignment list --assignee "$who" --role "$role" --scope "$scope" --query "length(@)" -o tsv)
  if [ "$n" != "0" ]; then return; fi
  for i in 1 2 3 4 5; do
    if az role assignment create --assignee-object-id "$who" --assignee-principal-type ServicePrincipal --role "$role" --scope "$scope" -o none; then return; fi
    echo "role assignment not ready, retrying in 15s"
    sleep 15
  done
  echo "could not assign $role"; exit 1
}

mk_subnet() {
  local name=$1 prefix=$2 deleg=${3:-}
  if az network vnet subnet show -g $RG --vnet-name $VNET -n $name >/dev/null 2>&1; then return; fi
  if [ -n "$deleg" ]; then
    az network vnet subnet create -g $RG --vnet-name $VNET -n $name --address-prefixes $prefix --delegations $deleg -o none
  else
    az network vnet subnet create -g $RG --vnet-name $VNET -n $name --address-prefixes $prefix -o none
  fi
}

mk_dns() {
  local zone=$1 link=$2
  az network private-dns zone show -g $RG -n $zone >/dev/null 2>&1 || az network private-dns zone create -g $RG -n $zone -o none
  az network private-dns link vnet show -g $RG -z $zone -n $link >/dev/null 2>&1 || az network private-dns link vnet create -g $RG -z $zone -n $link -v $VNET --registration-enabled false -o none
}

step "Extensions and providers"
az extension add --name containerapp --upgrade -y 2>/dev/null || true
for p in Microsoft.App Microsoft.OperationalInsights Microsoft.Network Microsoft.DBforPostgreSQL Microsoft.DBforMySQL Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do az provider register --namespace $p --wait; done

step "Subscription limit check (free trial allows one Container Apps environment)"
OTHER=$(az containerapp env list --query "[?name!='$ENV_NAME'].name" -o tsv 2>/dev/null || true)
if [ -n "$OTHER" ]; then echo "Another Container Apps environment exists: $OTHER"; echo "Delete its resource group first, then re-run."; exit 1; fi

step "Resource group and network"
az group create -n $RG -l $LOC -o none
az network vnet show -g $RG -n $VNET >/dev/null 2>&1 || az network vnet create -g $RG -n $VNET -l $LOC --address-prefixes 10.0.0.0/16 -o none
mk_subnet aca-subnet 10.0.0.0/23 Microsoft.App/environments
mk_subnet agw-subnet 10.0.2.0/24
mk_subnet pg-subnet 10.0.3.0/24 Microsoft.DBforPostgreSQL/flexibleServers
mk_subnet mysql-subnet 10.0.4.0/24 Microsoft.DBforMySQL/flexibleServers
ACA_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name $VNET -n aca-subnet --query id -o tsv)
PG_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name $VNET -n pg-subnet --query id -o tsv)
MYSQL_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name $VNET -n mysql-subnet --query id -o tsv)
RG_ID=$(az group show -n $RG --query id -o tsv)

step "Container Registry and managed identity"
az acr show -n $ACR >/dev/null 2>&1 || az acr create -g $RG -n $ACR --sku Basic --admin-enabled false -o none
ACR_ID=$(az acr show -n $ACR --query id -o tsv)
az acr repository show -n $ACR --image rabbitmq:3.13-alpine >/dev/null 2>&1 || az acr import -n $ACR --source docker.io/library/rabbitmq:3.13-alpine --image rabbitmq:3.13-alpine
az identity show -g $RG -n $IDENTITY >/dev/null 2>&1 || az identity create -g $RG -n $IDENTITY -o none
IDENTITY_ID=$(az identity show -g $RG -n $IDENTITY --query id -o tsv)
IDENTITY_PRINCIPAL=$(az identity show -g $RG -n $IDENTITY --query principalId -o tsv)
sleep 20
ensure_role $IDENTITY_PRINCIPAL AcrPull $ACR_ID

step "PostgreSQL server (databases: authdb, ordersdb)"
mk_dns $PG_DNS pg-link
PG_DNS_ID=$(az network private-dns zone show -g $RG -n $PG_DNS --query id -o tsv)
if az postgres flexible-server show -g $RG -n $PG >/dev/null 2>&1; then
  az postgres flexible-server update -g $RG -n $PG --admin-password "$PG_PASSWORD" -o none
else
  az postgres flexible-server create -g $RG -n $PG -l $LOC --admin-user pgadmin --admin-password "$PG_PASSWORD" --sku-name Standard_B1ms --tier Burstable --version 16 --storage-size 32 --subnet $PG_SUBNET_ID --private-dns-zone $PG_DNS_ID --yes -o none
fi
for db in authdb ordersdb; do
  if [ -z "$(az postgres flexible-server db list -g $RG -s $PG --query "[?name=='$db'].name" -o tsv)" ]; then az postgres flexible-server db create -g $RG -s $PG -n $db -o none; fi
done
PG_HOST=$(az postgres flexible-server show -g $RG -n $PG --query fullyQualifiedDomainName -o tsv)

step "MySQL server (database: cataloguedb)"
mk_dns $MYSQL_DNS mysql-link
MYSQL_DNS_ID=$(az network private-dns zone show -g $RG -n $MYSQL_DNS --query id -o tsv)
if az mysql flexible-server show -g $RG -n $MYSQL >/dev/null 2>&1; then
  az mysql flexible-server update -g $RG -n $MYSQL --admin-password "$MYSQL_PASSWORD" -o none
else
  az mysql flexible-server create -g $RG -n $MYSQL -l $LOC --admin-user mysqladmin --admin-password "$MYSQL_PASSWORD" --sku-name Standard_B1ms --tier Burstable --version 8.0.21 --storage-size 32 --subnet $MYSQL_SUBNET_ID --private-dns-zone $MYSQL_DNS_ID --yes -o none
fi
if [ -z "$(az mysql flexible-server db list -g $RG -s $MYSQL --query "[?name=='cataloguedb'].name" -o tsv)" ]; then
  az mysql flexible-server db create -g $RG -s $MYSQL --database-name cataloguedb -o none || az mysql flexible-server db create -g $RG -s $MYSQL -n cataloguedb -o none
fi
MYSQL_HOST=$(az mysql flexible-server show -g $RG -n $MYSQL --query fullyQualifiedDomainName -o tsv)

step "Container Apps environment (internal only, the one allowed environment)"
if ! az containerapp env show -g $RG -n $ENV_NAME >/dev/null 2>&1; then
  az containerapp env create -g $RG -n $ENV_NAME -l $LOC --infrastructure-subnet-resource-id $ACA_SUBNET_ID --internal-only true --no-wait -o none
fi
STATE=unknown
for i in $(seq 1 60); do
  STATE=$(az containerapp env show -g $RG -n $ENV_NAME --query properties.provisioningState -o tsv 2>/dev/null || echo missing)
  echo "environment state: $STATE"
  if [ "$STATE" = "Succeeded" ]; then break; fi
  if [ "$STATE" = "Failed" ]; then echo "Environment failed"; exit 1; fi
  sleep 30
done
if [ "$STATE" != "Succeeded" ]; then echo "Timed out waiting for the environment"; exit 1; fi
DOMAIN=$(az containerapp env show -g $RG -n $ENV_NAME --query properties.defaultDomain -o tsv)
STATIC_IP=$(az containerapp env show -g $RG -n $ENV_NAME --query properties.staticIp -o tsv)
mk_dns $DOMAIN aca-link
for rec in '*' '@'; do az network private-dns record-set a add-record -g $RG -z $DOMAIN -n "$rec" -a $STATIC_IP -o none || true; done

step "GitHub OIDC identity (passwordless login for the pipeline)"
APP_NAME="gh-$GH_OWNER-$GH_NAME"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv); fi
az ad sp show --id $APP_ID >/dev/null 2>&1 || az ad sp create --id $APP_ID -o none
SP_OBJ=$(az ad sp show --id $APP_ID --query id -o tsv)
sleep 20
ensure_role $SP_OBJ Contributor $RG_ID
ensure_role $SP_OBJ AcrPush $ACR_ID
OWNER_ID=$(gh api repos/$GH_REPO --jq .owner.id)
REPO_ID=$(gh api repos/$GH_REPO --jq .id)
add_cred() {
  local name=$1 subject=$2
  if [ -n "$(az ad app federated-credential list --id $APP_ID --query "[?name=='$name'].name" -o tsv)" ]; then
    az ad app federated-credential delete --id $APP_ID --federated-credential-id $name
  fi
  az ad app federated-credential create --id $APP_ID --parameters "{\"name\":\"$name\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"$subject\",\"audiences\":[\"api://AzureADTokenExchange\"]}" -o none
}
add_cred github-main "repo:${GH_OWNER}@${OWNER_ID}/${GH_NAME}@${REPO_ID}:ref:refs/heads/main"
add_cred github-main-classic "repo:${GH_REPO}:ref:refs/heads/main"

step "Saving GitHub secrets and variables"
gh secret set AZURE_CLIENT_ID --repo $GH_REPO --body "$APP_ID"
gh secret set AZURE_TENANT_ID --repo $GH_REPO --body "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID --repo $GH_REPO --body "$(az account show --query id -o tsv)"
gh secret set PG_PASSWORD --repo $GH_REPO --body "$PG_PASSWORD"
gh secret set MYSQL_PASSWORD --repo $GH_REPO --body "$MYSQL_PASSWORD"
gh secret set RABBIT_PASSWORD --repo $GH_REPO --body "$RABBIT_PASSWORD"
gh secret set JWT_SECRET --repo $GH_REPO --body "$JWT_SECRET"
gh variable set ACR_NAME --repo $GH_REPO --body "$ACR"
gh variable set AZURE_RG --repo $GH_REPO --body "$RG"
gh variable set ACA_ENV --repo $GH_REPO --body "$ENV_NAME"
gh variable set IDENTITY_ID --repo $GH_REPO --body "$IDENTITY_ID"
gh variable set PG_HOST --repo $GH_REPO --body "$PG_HOST"
gh variable set MYSQL_HOST --repo $GH_REPO --body "$MYSQL_HOST"

echo
echo "DONE. Infrastructure ready."
echo "PostgreSQL: $PG_HOST (authdb, ordersdb)"
echo "MySQL:      $MYSQL_HOST (cataloguedb)"
echo "Apps domain: $DOMAIN"

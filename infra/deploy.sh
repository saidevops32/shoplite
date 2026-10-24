#!/usr/bin/env bash
# Creates or updates the seven Container Apps. GitHub Actions runs this after the images are pushed.
set -euo pipefail

: "${RG:?}" "${ENV_NAME:?}" "${ACR_NAME:?}" "${IDENTITY_ID:?}" "${PG_HOST:?}" "${MYSQL_HOST:?}" "${TAG:?}"
: "${PG_PASSWORD:?}" "${MYSQL_PASSWORD:?}" "${RABBIT_PASSWORD:?}" "${JWT_SECRET:?}"

az config set extension.use_dynamic_install=yes_without_prompt >/dev/null 2>&1 || true
REG="$ACR_NAME.azurecr.io"
ID_ARGS="--user-assigned $IDENTITY_ID --registry-server $REG --registry-identity $IDENTITY_ID"

exists() { az containerapp show -g "$RG" -n "$1" >/dev/null 2>&1; }

# upsert NAME IMAGE CPU MEMORY MIN MAX INGRESS SECRETS ENVS
# INGRESS: gateway = reachable from the Application Gateway, tcp = RabbitMQ, none = no network access
upsert() {
  local name=$1 image=$2 cpu=$3 mem=$4 min=$5 max=$6 ingress=$7 secrets=$8 envs=$9
  local size="--cpu $cpu --memory $mem --min-replicas $min --max-replicas $max"
  echo ">> $name"
  if exists "$name"; then
    if [ -n "$secrets" ]; then az containerapp secret set -g "$RG" -n "$name" --secrets $secrets -o none; fi
    az containerapp update -g "$RG" -n "$name" --image "$image" $size ${envs:+--set-env-vars $envs} -o none
    return
  fi
  local ing=""
  case $ingress in
    gateway) ing="--ingress external --target-port 8080" ;;
    tcp) ing="--ingress internal --transport tcp --target-port 5672 --exposed-port 5672" ;;
  esac
  az containerapp create -g "$RG" -n "$name" --environment "$ENV_NAME" --image "$image" $ID_ARGS $size $ing ${secrets:+--secrets $secrets} ${envs:+--env-vars $envs} -o none
  if [ "$ingress" = "gateway" ]; then az containerapp ingress update -g "$RG" -n "$name" --allow-insecure true -o none; fi
}

PGBASE="PGHOST=$PG_HOST PGUSER=pgadmin PGSSL=true PGPASSWORD=secretref:pgpass PORT=8080"
MQENV="RABBITMQ_HOST=rabbitmq RABBITMQ_USER=app RABBITMQ_PASS=secretref:rabbitpass"

# Sizes stay small: a free trial allows 10 cores in total for the environment.
upsert rabbitmq "$REG/rabbitmq:3.13-alpine" 0.5 1.0Gi 1 1 tcp "rabbitpass=$RABBIT_PASSWORD" "RABBITMQ_DEFAULT_USER=app RABBITMQ_DEFAULT_PASS=secretref:rabbitpass"
upsert auth "$REG/auth:$TAG" 0.25 0.5Gi 1 1 gateway "pgpass=$PG_PASSWORD jwt=$JWT_SECRET" "$PGBASE PGDATABASE=authdb JWT_SECRET=secretref:jwt"
upsert catalogue "$REG/catalogue:$TAG" 0.5 1.0Gi 1 1 gateway "mysqlpass=$MYSQL_PASSWORD" "MYSQL_HOST=$MYSQL_HOST MYSQL_USER=mysqladmin MYSQL_PASSWORD=secretref:mysqlpass"
upsert checkout "$REG/checkout:$TAG" 0.25 0.5Gi 1 1 gateway "pgpass=$PG_PASSWORD jwt=$JWT_SECRET rabbitpass=$RABBIT_PASSWORD" "$PGBASE PGDATABASE=ordersdb JWT_SECRET=secretref:jwt $MQENV CATALOGUE_URL=http://catalogue"
upsert notify "$REG/notify:$TAG" 0.25 0.5Gi 1 1 gateway "jwt=$JWT_SECRET rabbitpass=$RABBIT_PASSWORD" "PORT=8080 JWT_SECRET=secretref:jwt $MQENV"
upsert worker "$REG/worker:$TAG" 0.25 0.5Gi 1 3 none "rabbitpass=$RABBIT_PASSWORD" "$MQENV"
upsert web "$REG/web:$TAG" 0.25 0.5Gi 1 2 gateway "" ""

echo
az containerapp list -g "$RG" --query "[].{name:name,status:properties.runningStatus}" -o table
echo "Deployed tag $TAG"

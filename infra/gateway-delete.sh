#!/usr/bin/env bash
# Deletes the gateway and its public IP so that billing for them stops.
set -euo pipefail

RG=shoplite-rg
GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
az network application-gateway delete -g $RG -n shoplite-agw
az network public-ip delete -g $RG -n shoplite-agw-pip
gh variable delete APP_URL --repo $GH_REPO || true
echo "Gateway deleted. Run infra/gateway.sh to create it again."

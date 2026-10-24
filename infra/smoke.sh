#!/usr/bin/env bash
# Tests the whole system through the gateway.  Usage: bash infra/smoke.sh http://<gateway-address>
set -euo pipefail

BASE=${1:?usage: smoke.sh http://gateway-address}
BASE=${BASE%/}
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; exit 1; }

wait_for() {
  local path=$1 i
  for i in $(seq 1 60); do
    if curl -fsS -m 5 -o /dev/null "$BASE$path" 2>/dev/null; then ok "$path is up"; return; fi
    sleep 5
  done
  fail "$path did not come up within 5 minutes"
}

# expect_contains PATH TEXT WHO : each path must reach its own service, so look for that service's fingerprint
expect_contains() {
  local path=$1 text=$2 who=$3 body
  body=$(curl -sS -m 10 "$BASE$path") || fail "$path unreachable"
  case "$body" in *"$text"*) ok "$path reaches $who" ;; *) fail "$path did not reach $who (got: ${body:0:80})" ;; esac
}

echo "== 1. every route is alive =="
for p in /healthz /api/auth/health /api/catalogue/health /api/checkout/health /api/notify/health; do wait_for "$p"; done

echo "== 2. path-based routing: each path reaches the right service =="
expect_contains "/" '<div id="root">' "web (default route)"
expect_contains "/api/auth/me" "Please log in" "auth"
expect_contains "/api/checkout/orders" "Please log in" "checkout"
expect_contains "/api/catalogue/products" "Wireless Earbuds" "catalogue (Java + MySQL)"
expect_contains "/socket.io/?EIO=4&transport=polling" '"sid"' "notify (Socket.IO)"

echo "== 3. register and log in =="
EMAIL="smoke$(date +%s)$RANDOM@example.com"
REG=$(curl -fsS -m 20 -X POST "$BASE/api/auth/register" -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"name\":\"Smoke Test\",\"password\":\"password12345\"}") || fail "register"
TOKEN=$(echo "$REG" | jq -r .token)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then fail "register returned no token"; fi
ok "registered $EMAIL"
LOGIN=$(curl -fsS -m 20 -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"password12345\"}") || fail "login"
if [ "$(echo "$LOGIN" | jq -r .user.email)" != "$EMAIL" ]; then fail "login returned the wrong user"; fi
ok "logged in"

echo "== 4. place an order and wait for the Erlang worker =="
wait_status() {
  local id=$1 want=$2 i s
  for i in $(seq 1 40); do
    s=$(curl -sS -m 10 "$BASE/api/checkout/orders/$id" -H "Authorization: Bearer $TOKEN" | jq -r .status || true)
    if [ "$s" = "$want" ]; then return 0; fi
    sleep 1
  done
  return 1
}
ORDER=$(curl -fsS -m 30 -X POST "$BASE/api/checkout/orders" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"items":[{"productId":1,"quantity":2},{"productId":8,"quantity":1}]}') || fail "create order"
ID=$(echo "$ORDER" | jq -r .id)
TOTAL=$(echo "$ORDER" | jq -r .totalCents)
if [ "$TOTAL" != "8797" ]; then fail "order total is $TOTAL, expected 8797 (prices come from the catalogue)"; fi
ok "order $ID created, total 8797 priced by the catalogue"
if wait_status "$ID" PAID; then ok "order $ID became PAID (RabbitMQ and the Erlang worker work)"; else fail "order $ID never became PAID"; fi

echo "== 5. a declined payment =="
BIG=$(jq -nc '{items: [range(1;13) | {productId: ., quantity: 20}]}')
ORDER2=$(curl -fsS -m 30 -X POST "$BASE/api/checkout/orders" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$BIG") || fail "create large order"
ID2=$(echo "$ORDER2" | jq -r .id)
if wait_status "$ID2" FAILED; then ok "order $ID2 became FAILED as expected (over the card limit)"; else fail "order $ID2 never became FAILED"; fi

echo "== 6. security checks =="
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$BASE/api/checkout/orders")
if [ "$CODE" != "401" ]; then fail "orders without a login returned $CODE, expected 401"; fi
ok "orders without a login are refused (401)"

echo
echo "ALL CHECKS PASSED"

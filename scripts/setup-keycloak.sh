#!/usr/bin/env bash
set -euo pipefail

# Hard-coded settings per request
REALM_NAME="todo-app"
CLIENT_ID="todo-app"
CLIENT_SECRET="upEi5EJf36okjxogLG6RXWSZVmrRvd3E"
REDIRECT_URI="http://todo.local/*"
WEB_ORIGINS="*"
TEST_USER="nkwenti"
TEST_PASS="password"

NS_KC="keycloak-system"
NS_APP="todo-app"

# Admin credentials (master realm)
ADMIN_USER="nkwenti"
ADMIN_PASS="password"

# Find Keycloak pod
KC_POD=$(vagrant ssh k3s-master -c "kubectl get pods -n $NS_KC -l app=keycloak -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null | tr -d '\r')
if [[ -z "$KC_POD" ]]; then
  echo "Keycloak pod not found in namespace $NS_KC" >&2
  exit 1
fi

# Use a shared config file inside the container so auth persists
KCADM_CONFIG="/tmp/kcadm.config"

# Helper to run kcadm with server+config specified
a_kc() {
  vagrant ssh k3s-master -c "kubectl -n $NS_KC exec $KC_POD -- /opt/keycloak/bin/kcadm.sh --server http://localhost:8080 --config $KCADM_CONFIG $*"
}

echo "Waiting for Keycloak to be ready..."
vagrant ssh k3s-master -c "kubectl -n $NS_KC wait --for=condition=ready --timeout=300s pod/$KC_POD" >/dev/null

echo "Logging into Keycloak admin (master realm) as $ADMIN_USER..."
if ! a_kc "config credentials --realm master --user $ADMIN_USER --password $ADMIN_PASS" >/dev/null 2>&1; then
  echo "Warning: initial login attempt returned non-zero; continuing and will verify with a GET..."
fi
# Verify login by querying serverinfo
if ! a_kc "get serverinfo --realm master" >/dev/null 2>&1; then
  echo "Error: Unable to contact Keycloak with provided admin credentials." >&2
  exit 1
fi

echo "Ensuring realm $REALM_NAME exists..."
if ! a_kc "get realms/$REALM_NAME" >/dev/null 2>&1; then
  a_kc "create realms -s realm=$REALM_NAME -s enabled=true" >/dev/null
fi

echo "Ensuring client $CLIENT_ID exists..."
if ! a_kc "get clients -r $REALM_NAME -q clientId=$CLIENT_ID" | grep -q '\"clientId\"'; then
  a_kc "create clients -r $REALM_NAME -s clientId=$CLIENT_ID -s enabled=true -s publicClient=false -s directAccessGrantsEnabled=true -s 'redirectUris=[\"$REDIRECT_URI\"]' -s 'webOrigins=[\"$WEB_ORIGINS\"]'" >/dev/null
fi

CLIENT_UUID=$(a_kc "get clients -r $REALM_NAME -q clientId=$CLIENT_ID --fields id" | sed -n 's/.*\"id\" *: *\"\([^\"]*\)\".*/\1/p' | tr -d '\r')
if [[ -z "$CLIENT_UUID" ]]; then
  echo "Failed to resolve client UUID" >&2
  exit 1
fi

echo "Setting client secret..."
a_kc "update clients/$CLIENT_UUID -r $REALM_NAME -s secret=$CLIENT_SECRET" >/dev/null

echo "Ensuring test user $TEST_USER exists..."
if ! a_kc "get users -r $REALM_NAME -q username=$TEST_USER" | grep -q "$TEST_USER"; then
  a_kc "create users -r $REALM_NAME -s username=$TEST_USER -s enabled=true -s emailVerified=true -s email=$TEST_USER@example.com" >/dev/null
fi
USER_ID=$(a_kc "get users -r $REALM_NAME -q username=$TEST_USER --fields id" | sed -n 's/.*\"id\" *: *\"\([^\"]*\)\".*/\1/p' | tr -d '\r')
if [[ -n "$USER_ID" ]]; then
  a_kc "set-password -r $REALM_NAME --userid $USER_ID --new-password $TEST_PASS" >/dev/null
  a_kc "update users/$USER_ID -r $REALM_NAME -s emailVerified=true -s enabled=true -s firstName=Test -s lastName=User" >/dev/null
fi

echo "Updating application deployment envs..."
ISSUER_URL="http://keycloak.keycloak-system.svc.cluster.local/realms/$REALM_NAME"
JWKS_URL="$ISSUER_URL/protocol/openid-connect/certs"
vagrant ssh k3s-master -c "kubectl set env deployment/todo-app -n $NS_APP KEYCLOAK_REALM=$REALM_NAME KEYCLOAK_CLIENT_ID=$CLIENT_ID KEYCLOAK_CLIENT_SECRET=$CLIENT_SECRET KEYCLOAK_ISSUER_URL=$ISSUER_URL KEYCLOAK_JWKS_URL=$JWKS_URL" >/dev/null
vagrant ssh k3s-master -c "kubectl rollout restart deployment/todo-app -n $NS_APP" >/dev/null

echo "Keycloak setup complete for realm=$REALM_NAME, client=$CLIENT_ID. App updated and restarted."

#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Keycloak Automation Script
# ============================================================================
# This script automates the setup of Keycloak realm, client, and test user
# for the Todo application using the Keycloak Admin CLI (kcadm).
#
# Prerequisites:
# - Keycloak must be deployed and running in Kubernetes (via Helm chart)
# - kubectl access to the cluster (via vagrant ssh)
# - Keycloak admin credentials
#
# Usage: ./setup-keycloak.sh
# ============================================================================

echo "🚀 Starting Keycloak automation setup..."

# Configuration
REALM_NAME="todo-app"
CLIENT_ID="todo-app"
CLIENT_SECRET="AR10DzMjGrWK8lzE8xSdzxEWe84HxRFh"
TEST_USER="nkwenti"
TEST_PASS="password"

# Deployment settings
NS_KC="keycloak"
KEYCLOAK_URL="http://keycloak.local"
VM_NAME="cloud-gauntlet"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# ============================================================================
# Helper Functions
# ============================================================================

# Function to execute kcadm commands in the Keycloak pod
kcadm() {
    vagrant ssh "$VM_NAME" -c "kubectl exec -n $NS_KC deployment/keycloak -- /opt/keycloak/bin/kcadm.sh $*"
}

# ============================================================================
# Main Setup Process
# ============================================================================

echo "🔍 Finding Keycloak pod in namespace $NS_KC..."

# Check if Keycloak pod is running
if ! vagrant ssh "$VM_NAME" -c "kubectl get pods -n $NS_KC -l app.kubernetes.io/name=keycloak" | grep -q Running; then
    echo "❌ Keycloak pod not found or not running in namespace $NS_KC"
    echo "💡 Make sure Keycloak is deployed and running"
    exit 1
fi

echo "✅ Keycloak pod is running"

echo "🔐 Authenticating with Keycloak admin using kcadm..."
if ! kcadm config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASS" >/dev/null 2>&1; then
    echo "❌ Failed to authenticate with Keycloak admin"
    echo "💡 Check admin credentials: $ADMIN_USER / $ADMIN_PASS"
    exit 1
fi

echo "✅ Successfully authenticated as admin"

# ============================================================================
# 1. Create Realm
# ============================================================================

echo "🏰 Setting up realm: $REALM_NAME..."

# Check if realm exists
if kcadm get realms/$REALM_NAME >/dev/null 2>&1; then
    echo "✅ Realm '$REALM_NAME' already exists"
else
    echo "📝 Creating realm '$REALM_NAME'..."
    kcadm create realms \
        -s realm="$REALM_NAME" \
        -s enabled=true \
        -s registrationAllowed=true \
        -s registrationEmailAsUsername=false \
        -s rememberMe=false \
        -s verifyEmail=false \
        -s loginWithEmailAllowed=false \
        -s duplicateEmailsAllowed=false \
        -s resetPasswordAllowed=false \
        -s editUsernameAllowed=false \
        -s bruteForceProtected=true
    echo "✅ Realm '$REALM_NAME' created successfully"
fi

# ============================================================================
# 2. Create Client
# ============================================================================

echo "🔧 Setting up client: $CLIENT_ID..."

# Check if client exists
if kcadm get clients -r "$REALM_NAME" --query clientId="$CLIENT_ID" | grep -q "clientId"; then
    echo "✅ Client '$CLIENT_ID' already exists"
else
    echo "📝 Creating client '$CLIENT_ID' for Direct Access Grant (password flow)..."
    kcadm create clients -r "$REALM_NAME" \
        -s clientId="$CLIENT_ID" \
        -s enabled=true \
        -s publicClient=false \
        -s standardFlowEnabled=false \
        -s directAccessGrantsEnabled=true \
        -s secret="$CLIENT_SECRET"
    echo "✅ Client '$CLIENT_ID' created successfully"
fi

# ============================================================================
# 3. Create Test User
# ============================================================================

echo "👤 Setting up test user: $TEST_USER..."

# Check if user exists
if kcadm get users -r "$REALM_NAME" --query username="$TEST_USER" | grep -q "username"; then
    echo "✅ User '$TEST_USER' already exists"
else
    echo "📝 Creating user '$TEST_USER'..."
    kcadm create users -r "$REALM_NAME" \
        -s username="$TEST_USER" \
        -s enabled=true \
        -s emailVerified=true \
        -s firstName="Nkwenti" \
        -s lastName="Severian" \
        -s email="$TEST_USER@example.com"

    # Set password for the user
    kcadm set-password -r "$REALM_NAME" --username "$TEST_USER" --new-password "$TEST_PASS"
    echo "✅ User '$TEST_USER' created successfully"
fi

# ============================================================================
# 4. Final Configuration Summary
# ============================================================================

echo ""
echo "🎉 Keycloak setup completed successfully!"
echo ""
echo "📋 Configuration Summary:"
echo "=========================="
echo "Realm:           $REALM_NAME"
echo "Client ID:       $CLIENT_ID"
echo "Client Secret:   [Hidden for security]"
echo "Grant Type:      Direct Access Grant (password flow)"
echo "Test User:       $TEST_USER"
echo "Test Password:   [Hidden for security]"
echo ""
echo "🔗 Keycloak URLs:"
echo "Admin Console:   $KEYCLOAK_URL/admin/"
echo "Realm Console:   $KEYCLOAK_URL/admin/master/console/#/realms/$REALM_NAME"
echo "Auth Endpoint:   $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/auth"
echo "Token Endpoint:  $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/token"
echo "JWKS Endpoint:   $KEYCLOAK_URL/realms/$REALM_NAME/protocol/openid-connect/certs"
echo ""
echo "✅ Features Enabled:"
echo "- User Registration: ✓"
echo "- Direct Access Grants (Password): ✓"
echo "- Client Authentication: ✓"
echo "--------------------------"
echo "❌ Features Disabled:"
echo "- Standard Flow (Authorization Code): ✗ (not needed for API)"
echo "- Remember Me: ✗"
echo "- Password Reset: ✗"
echo "- Login with Email: ✗"
echo ""
echo "🚀 Your Todo app is now ready to integrate with Keycloak!"

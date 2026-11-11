#!/usr/bin/env bash
set -euo pipefail
set +x  # Prevent shell tracing of credentials

BOLD_CYAN='\033[1;36m'
BOLD_GREEN='\033[1;32m'
BOLD_BLUE='\033[1;34m'
BOLD_RED='\033[1;31m'
NC='\033[0m'

ARO_CLUSTER="moodle-aro-cluster"
ARO_RESOURCE_GROUP="rg-moodle-aro"
ARO_API_URL="https://api.moodle-aro.centralus.aroapp.io:6443"
ARO_NAMESPACE="moodle"
ACR_NAME="moodlearoregistry"

echo -e "${BOLD_GREEN}=== Step 1: Input & Validate Credentials ===${NC}"

: "${MYSQL_ROOT_PASSWORD:?MySQL root password is missing}"
echo -e "${BOLD_BLUE}PASS: MySQL root password is available${NC}"

: "${MOODLE_DB_PASSWORD:?Moodle database password is missing}"
echo -e "${BOLD_BLUE}PASS: Moodle database password is available${NC}"

: "${MOODLE_ADMIN_PASSWORD:?Moodle administrator password is missing}"
echo -e "${BOLD_BLUE}PASS: Moodle administrator password is available${NC}"

# Your interactive snippet for the service principal credentials
export TF_VAR_aro_client_id="cbeed451-4fa3-46ee-9998-4cc098459a5b"

read -s -p "Enter ARO service principal secret: " TF_VAR_aro_client_secret
echo
export TF_VAR_aro_client_secret

test -n "$TF_VAR_aro_client_id" && echo -e "${BOLD_BLUE}PASS: ARO client ID is set${NC}"
test -n "$TF_VAR_aro_client_secret" && echo -e "${BOLD_BLUE}PASS: ARO client secret is set${NC}"


echo -e "${BOLD_GREEN}=== Step 2: Retrieve ARO Credentials ===${NC}"

ARO_USER=$(az aro list-credentials \
  --name "$ARO_CLUSTER" \
  --resource-group "$ARO_RESOURCE_GROUP" \
  --query kubeadminUsername -o tsv)

ARO_PASSWORD=$(az aro list-credentials \
  --name "$ARO_CLUSTER" \
  --resource-group "$ARO_RESOURCE_GROUP" \
  --query kubeadminPassword -o tsv)

: "${ARO_USER:?ARO username retrieval failed}"
echo -e "${BOLD_BLUE}PASS: ARO username retrieved${NC}"

: "${ARO_PASSWORD:?ARO password retrieval failed}"
echo -e "${BOLD_BLUE}PASS: ARO password retrieved${NC}"


echo -e "${BOLD_GREEN}=== Step 3: Login to Azure Container Registry ===${NC}"
az acr login --name "$ACR_NAME"
echo -e "${BOLD_BLUE}PASS: Successfully logged into ACR ($ACR_NAME)${NC}"


echo -e "${BOLD_GREEN}=== Step 4: Login to ARO & Initialize Project ===${NC}"

oc login "$ARO_API_URL" \
  -u "$ARO_USER" \
  -p "$ARO_PASSWORD"

unset ARO_PASSWORD

oc whoami >/dev/null
echo -e "${BOLD_BLUE}PASS: OpenShift authentication successful${NC}"

# Create the project/namespace (OpenShift equivalent of a project scope)
if oc get project "$ARO_NAMESPACE" >/dev/null 2>&1; then
  echo "PASS: Project $ARO_NAMESPACE already exists"
  oc project "$ARO_NAMESPACE" >/dev/null
else
  oc new-project "$ARO_NAMESPACE"
  echo -e "${BOLD_BLUE}PASS: Created and switched to project $ARO_NAMESPACE{NC}"
fi


echo -e "${BOLD_GREEN}=== Step 5: Create MySQL Secret ===${NC}"

oc create secret generic mysql-secret \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --from-literal=mysql-database="moodle" \
  --from-literal=mysql-user="moodleuser" \
  --from-literal=moodleuser-password="$MOODLE_DB_PASSWORD" \
  --dry-run=client -o yaml | oc apply -n "$ARO_NAMESPACE" -f -

echo -e "${BOLD_GREEN}=== Step 6: Create PHP Secret ===${NC}"

oc create secret generic php-secret \
  --from-literal=db-password="$MOODLE_DB_PASSWORD" \
  --dry-run=client -o yaml | oc apply -n "$ARO_NAMESPACE" -f -


echo -e "${BOLD_GREEN}=== Step 7: Create & Link ACR Pull Secret ===${NC}"


# Create ServiceAccount in the ARO project if it does not exist
oc create serviceaccount moodle-aro-sa \
  -n "$ARO_NAMESPACE" \
  --dry-run=client -o yaml | oc apply -f -

# Create or update the ACR pull Secret
oc create secret docker-registry acr-pull-secret \
  --docker-server=moodlearoregistry.azurecr.io \
  --docker-username="$TF_VAR_aro_client_id" \
  --docker-password="$TF_VAR_aro_client_secret" \
  --dry-run=client -o yaml | oc apply -n "$ARO_NAMESPACE" -f -

# Link the pull Secret to the ServiceAccount
oc secrets link moodle-aro-sa acr-pull-secret \
  --for=pull \
  -n "$ARO_NAMESPACE"

echo -e "${BOLD_GREEN}=== Step 8: Verify Kubernetes Secrets & Configuration ===${NC}"

# Verify ServiceAccount exists
oc get serviceaccount moodle-aro-sa \
  -n "$ARO_NAMESPACE" -o name >/dev/null

echo -e "${BOLD_BLUE}PASS: moodle-aro-sa exists in $ARO_NAMESPACE${NC}"

# Verify Kubernetes Secrets exist
for secret in mysql-secret php-secret acr-pull-secret; do
  oc get secret "$secret" -n "$ARO_NAMESPACE" -o name >/dev/null
  echo -e "${BOLD_BLUE}PASS: $secret exists in $ARO_NAMESPACE${NC}"
done

# Verify MySQL Secret keys
for key in root-password moodleuser-password; do
  value=$(oc get secret mysql-secret -n "$ARO_NAMESPACE" \
    -o "go-template={{index .data \"$key\"}}")

  if [[ -z "$value" ]]; then
    echo -e "${BOLD_RED}FAIL: mysql-secret missing $key${NC}"
    exit 1
  fi

  echo -e "${BOLD_BLUE}PASS: mysql-secret contains $key${NC}"
done

# Verify PHP Secret key
value=$(oc get secret php-secret -n "$ARO_NAMESPACE" \
  -o 'go-template={{index .data "db-password"}}')

if [[ -z "$value" ]]; then
  echo -e "${BOLD_RED}FAIL: php-secret missing db-password${NC}"
  exit 1
fi

echo -e "${BOLD_BLUE}PASS: php-secret contains db-password${NC}"

# Verify ACR pull Secret is linked to ServiceAccount
if ! oc get serviceaccount moodle-aro-sa \
  -n "$ARO_NAMESPACE" \
  -o jsonpath='{.imagePullSecrets[*].name}' |
  tr ' ' '\n' | grep -qx 'acr-pull-secret'; then

  echo -e "${BOLD_RED}FAIL: acr-pull-secret is not linked to moodle-aro-sa${NC}"
  exit 1
fi

echo -e "${BOLD_BLUE}PASS: acr-pull-secret linked to moodle-aro-sa${NC}"

echo
echo -e "${BOLD_BLUE}SUCCESS: ARO project initialization, Secrets, and ACR pull configuration verified.${NC}"

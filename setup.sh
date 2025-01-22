#!/bin/bash

if [ $# -ne 3 ]; then
  echo "Usage: $0 <OPENSHIFT_URL> <USERNAME> <PASSWORD>"
  exit 1
fi

OPENSHIFT_URL=$1
USERNAME=$2
PASSWORD=$3

RED='\033[1;31m' 
GREEN='\033[1;32m' 
YELLOW='\033[1;33m' 
BLUE='\033[1;34m'
NC='\033[0m' # No color

OC_COMMAND=$(command -v oc)
RETRIES=30
DELAY=5

OPENLDAP_NAMESPACE=openldap
PHPLDAPADMIN_NAMESPACE=phpldapadmin
AUTOMATION_NAMESPACE=ansible-automation
SEALED_SECRETS_NAMESPACE=sealed-secrets

delete_project_if_exists() {
  for namespace in "$OPENLDAP_NAMESPACE" "$PHPLDAPADMIN_NAMESPACE" "$AUTOMATION_NAMESPACE" "$SEALED_SECRETS_NAMESPACE"; do
    if oc get project "$namespace" &>/dev/null; then
      echo -e "${BLUE}Deleting existing project $namespace...${NC}"
      oc delete project "$namespace" --grace-period=0 --force &>/dev/null
    fi
  done
}

check_oc_installed() {
  if [ -z "$OC_COMMAND" ]; then
    echo -e "${RED}✘ 'oc' command not found. Please install the OpenShift CLI.${NC}"
    exit 1
  fi
}

login_to_openshift() {
  echo -e "${BLUE}Logging in to OpenShift...${NC}"

  if ! oc login "$OPENSHIFT_URL" -u "$USERNAME" -p "$PASSWORD" --insecure-skip-tls-verify &>/dev/null; then
    echo -e "${RED}✘ Failed to log in to OpenShift.${NC}"
    exit 1
  fi
  echo -e "${GREEN}✔ Successfully logged in to OpenShift.${NC}"
}

apply_kustomize_resource() {
  local resource_path=$1
  echo -e "${BLUE}Applying resources from $resource_path...${NC}"

  if oc create -k "$resource_path"; then
    echo -e "${GREEN}✔ Successfully applied resources from $resource_path.${NC}"
  else
    echo -e "${RED}✘ Failed to apply resources from $resource_path. Exiting.${NC}"
    exit 1
  fi
}

install_sealed_secret() {
  apply_kustomize_resource "deployments/sealed-secrets/"
}

create_openldap_server() {
  apply_kustomize_resource "deployments/openldap/"
}

create_phpldapadmin() {
  apply_kustomize_resource "deployments/phpldapadmin/"
}

wait_for_ldap_server() {
  echo -e "${BLUE}Waiting for OpenLDAP server pods to be in 'Running' state...${NC}"
  for ((i=1; i<=RETRIES; i++)); do
    if oc -n "$OPENLDAP_NAMESPACE" get pods --selector deployment=openldap -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
      echo -e "${GREEN}✔ All OpenLDAP pods are running.${NC}"
      return 0
    fi

    echo -e "${YELLOW}🛆 Attempt $i/${RETRIES}: Not all pods are running. Retrying in $DELAY seconds...${NC}"
    sleep $DELAY
  done

  echo -e "${RED}✘ Timed out waiting for OpenLDAP pods to reach 'Running' state. Cannot continue.${NC}"
  exit 1
}

populate_ldap_server() {
  apply_kustomize_resource "deployments/ansible-automation-env/"
  echo -e "${BLUE}Waiting for Ansible automation job to complete...${NC}"

  if oc wait --for=condition=complete job/ansible -n "$AUTOMATION_NAMESPACE" --timeout=$((RETRIES * DELAY))s; then
    echo -e "${GREEN}✔ Automation job completed successfully. LDAP server populated.${NC}"
    oc delete project "$AUTOMATION_NAMESPACE"
  else
    echo -e "${RED}✘ Automation job did not complete within the expected time. Exiting.${NC}"
    exit 1
  fi
}


check_oc_installed
login_to_openshift
delete_project_if_exists
create_openldap_server
create_phpldapadmin
wait_for_ldap_server
populate_ldap_server

echo -e "${GREEN}✔ Setup completed successfully.${NC}"

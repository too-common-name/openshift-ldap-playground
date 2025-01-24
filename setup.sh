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

OPENLDAP_NAMESPACE=openldap
PHPLDAPADMIN_NAMESPACE=phpldapadmin
AUTOMATION_NAMESPACE=ansible-automation
SEALED_SECRETS_NAMESPACE=sealed-secrets

OC_COMMAND=$(command -v oc)
LOG_FILE="deployment.log"

handle_error() {
  local exit_code=${2:-$?} # Use the second argument or the exit status of the last command if not provided
  if [ $exit_code -ne 0 ]; then
    echo -e "${RED} ✘ $1${NC}"
    echo "ERROR: $1" >> $LOG_FILE
    exit $exit_code
  fi
}

cleanup() {
  echo "Starting components installation" > $LOG_FILE

  echo -e "${YELLOW} ⚠ Deleting resources for OpenLDAP from template...${NC}"
  oc process -f deployments/openldap/openldap-template.yaml -p OPENLDAP_NAMESPACE=$OPENLDAP_NAMESPACE | oc delete -f - &>> $LOG_FILE

  echo -e "${YELLOW} ⚠ Deleting resources for phpLDAPadmin from template...${NC}"
  oc process -f deployments/phpldapadmin/phpldapadmin-template.yaml -p PHPLDAPADMIN_NAMESPACE=$PHPLDAPADMIN_NAMESPACE -p OPENLDAP_NAMESPACE=$OPENLDAP_NAMESPACE -p OPENLDAP_APP_SVC=$OPENLDAP_NAMESPACE | oc delete -f - &>> $LOG_FILE

  echo -e "${YELLOW} ⚠ Deleting resources for Ansible Automation Environment from template...${NC}"
  oc process -f deployments/ansible-automation-env/ansible-automation-env-template.yaml -p ANSIBLE_NAMESPACE=$AUTOMATION_NAMESPACE | oc delete -f - &>> $LOG_FILE

  echo -e "${YELLOW} ⚠ Deleting Sealed Secrets resources using Kustomize...${NC}"
  oc delete -k deployments/sealed-secrets &>> $LOG_FILE
  oc delete project "$SEALED_SECRETS_NAMESPACE" --grace-period=0 --force &>> $LOG_FILE
}

check_oc_installed() {
  if [ -z "$OC_COMMAND" ]; then
    echo -e "${RED} ✘ 'oc' command not found. Please install the OpenShift CLI.${NC}"
    exit 1
  fi
}

login_to_openshift() {
  echo -e "${BLUE} ➜ Logging in to OpenShift...${NC}"
  oc login "$OPENSHIFT_URL" -u "$USERNAME" -p "$PASSWORD" --insecure-skip-tls-verify &>> $LOG_FILE
  handle_error "Failed to log in to OpenShift"
  echo -e "${GREEN} ✔ Successfully logged in to OpenShift.${NC}"
}

install_sealed_secret() {
  echo -e "${BLUE} ➜ Creating Sealed Secrets namespace...${NC}"
  oc new-project $SEALED_SECRETS_NAMESPACE &>> $LOG_FILE
  handle_error "Failed to create Sealed Secrets project"
  
  echo -e "${BLUE} ➜ Installing Sealed Secrets...${NC}"
  oc create -k deployments/sealed-secrets/ &>> $LOG_FILE
  handle_error "Failed to install Sealed Secrets"
}

create_openldap_server() {
  echo -e "${BLUE} ➜ Processing OpenLDAP Template...${NC}"
  oc process -f deployments/openldap/openldap-template.yaml -p OPENLDAP_NAMESPACE=$OPENLDAP_NAMESPACE | oc apply -f - &>> $LOG_FILE
  handle_error "Failed to deploy OpenLDAP from template"
  
  echo -e "${BLUE} ➜ Waiting for LDAP server to be deployed...${NC}"
  oc wait --for=condition=available --timeout=100s deployment/openldap -n openldap &>> $LOG_FILE
  handle_error "LDAP server not deployed successfully"
}

create_phpldapadmin() {
  echo -e "${BLUE} ➜ Processing phpLDAPadmin Template...${NC}"
  oc process -f deployments/phpldapadmin/phpldapadmin-template.yaml -p PHPLDAPADMIN_NAMESPACE=$PHPLDAPADMIN_NAMESPACE -p OPENLDAP_NAMESPACE=$OPENLDAP_NAMESPACE -p OPENLDAP_APP_SVC=$OPENLDAP_NAMESPACE | oc apply -f - &>> $LOG_FILE
  handle_error "Failed to deploy phpLDAPadmin from template"
}

populate_ldap_server() {
  echo -e "${BLUE} ➜ Processing automation environment Template...${NC}"
  oc process -f deployments/ansible-automation-env/ansible-automation-env-template.yaml -p ANSIBLE_NAMESPACE=$AUTOMATION_NAMESPACE | oc apply -f - &>> $LOG_FILE
  handle_error "Failed to deploy automation environment from template"

  echo -e "${BLUE} ➜ Waiting for automation job to complete...${NC}"
  oc wait --for=condition=complete --timeout=200s job/ansible -n $AUTOMATION_NAMESPACE &>> $LOG_FILE
  handle_error "Ansible job did not complete successfully"
}

# Start the deployment process
check_oc_installed
login_to_openshift
cleanup
install_sealed_secret
create_phpldapadmin
create_openldap_server
populate_ldap_server

echo -e "${GREEN} ✔ Setup completed successfully.${NC}"

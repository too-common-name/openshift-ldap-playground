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

OC_COMMAND=$(command -v oc)
RETRIES=20
DELAY=5
OPENLDAP_NAMESPACE=openldap
PHPLDAPADMIN_NAMESPACE=phpldapadmin
AUTOMATION_NAMESPACE=ansible-automation

check_oc_installed() {
  if [ -z "$OC_COMMAND" ]; then
    echo -e "${RED} ✘ 'oc' command not found. Please install the OpenShift CLI."
    exit 1
  fi
}

login_to_openshift() {
  echo -e "${BLUE} Logging in to OpenShift..."

  if ! oc login "$OPENSHIFT_URL" -u "$USERNAME" -p "$PASSWORD" --insecure-skip-tls-verify &>/dev/null; then
    echo -e "${RED} ✘ Failed to log in to OpenShift."
    exit 1
  fi
}

create_openldap_server() {
  if ! oc get namespace $OPENLDAP_NAMESPACE &>/dev/null; then
    echo -e "${BLUE} Creating resources for project $OPENLDAP_NAMESPACE..."

    echo -e "${BLUE} Creating namespace $OPENLDAP_NAMESPACE..."
    oc new-project $OPENLDAP_NAMESPACE &>/dev/null

    echo -e "${BLUE} Creating secrets for OpenLDAP..."
    oc create secret generic openldap-admin \
      --from-literal=LDAP_ADMIN_PASSWORD=admin123 &>/dev/null
    oc create secret generic openldap-readonly \
      --from-literal=LDAP_READONLY_USER_PASSWORD=readonly123 &>/dev/null

    echo -e "${BLUE} Creating ConfigMap for OpenLDAP..."
    oc create cm openldap-conf \
      --from-literal=LDAP_BASE_DN='dc=wayneenterprises,dc=org' \
      --from-literal=LDAP_DOMAIN='wayneenterprises.org' \
      --from-literal=LDAP_READONLY_USER='true' &>/dev/null

    echo -e "${BLUE} Creating service account for OpenLDAP..."
    oc create sa openldap &>/dev/null
    oc adm policy add-scc-to-user anyuid -z openldap &>/dev/null

    echo -e "${BLUE} Deploying OpenLDAP application..."
    oc new-app --name=openldap --image=docker.io/osixia/openldap &>/dev/null

    echo -e "${BLUE} Configuring environment variables for OpenLDAP..."
    oc set env deploy/openldap --from=cm/openldap-conf &>/dev/null
    oc set env deploy/openldap --from=secret/openldap-admin &>/dev/null
    oc set env deploy/openldap --from=secret/openldap-readonly &>/dev/null

    echo -e "${BLUE} Associating service account with OpenLDAP deployment..."
    oc set sa deploy/openldap openldap &>/dev/null
  else 
    echo -e "${YELLOW} 🛆 Namespace $OPENLDAP_NAMESPACE already exists. Skipping creation of resources."
  fi
}

create_phpldapadmin() {
  if ! oc get namespace $PHPLDAPADMIN_NAMESPACE &>/dev/null; then
    echo -e "${BLUE} Creating resources for project $PHPLDAPADMIN_NAMESPACE..."

    echo -e "${BLUE} Creating namespace $PHPLDAPADMIN_NAMESPACE..."
    oc new-project $PHPLDAPADMIN_NAMESPACE &>/dev/null

    echo -e "${BLUE} Creating service account for phpLDAPadmin..."
    oc create sa phpldap-sa &>/dev/null
    oc adm policy add-scc-to-user anyuid -z phpldap-sa &>/dev/null

    echo -e "${BLUE} Deploying phpLDAPadmin application..."
    oc new-app --image=docker.io/osixia/phpldapadmin \
      --env=PHPLDAPADMIN_HTTPS='false' \
      --env=PHPLDAPADMIN_LDAP_HOSTS='openldap.openldap.svc.cluster.local' &>/dev/null

    echo -e "${BLUE} Associating service account with phpLDAPadmin deployment..."
    oc set sa deploy/phpldapadmin phpldap-sa &>/dev/null

    echo -e "${BLUE} Creating route for phpLDAPadmin..."
    oc create route edge phpldapadmin --service=phpldapadmin &>/dev/null
  else 
    echo -e "${YELLOW} 🛆 Namespace $PHPLDAPADMIN_NAMESPACE already exists. Skipping creation of resources."
  fi
}


wait_for_ldap_server() {
  echo -e "${BLUE} Waiting for OpenLDAP server pods to be in 'Running' state..."
  for ((i=1; i<=RETRIES; i++)); do
    pod_status=$(oc -n $OPENLDAP_NAMESPACE get pods --selector deployment=openldap -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -v '^Running$')

    if [ -z "$pod_status" ]; then
      echo -e "${GREEN} ✔ All OpenLDAP pods are running."
      return 0
    fi

    echo -e "${YELLOW} 🛆 Attempt $i/${RETRIES}: Not all pods are running. Retrying in $DELAY seconds..."
    sleep $DELAY
  done

  echo -e "${RED} ✘ Timed out waiting for OpenLDAP pods to reach 'Running' state. Cannot continue with script."
  exit 1
}

populate_ldap_server() {
  oc new-project $AUTOMATION_NAMESPACE
  echo -e "${BLUE} Populating LDAP server using Ansible..."
  oc create -f ansible-automation-env/vault-secret.yaml &>/dev/null
  oc create -f ansible-automation-env/ansible-job.yaml &>/dev/null
  echo -e "${BLUE} Waiting for automation to complete..."
  for ((i=1; i<=RETRIES; i++)); do
    job_status=$(oc get job ansible -n $AUTOMATION_NAMESPACE -o jsonpath='{.status.conditions[*].type}')

    if [[ "$job_status" == *"Complete"* ]]; then
      echo -e "${GREEN} ✔ Automation completed, LDAP server populated."
      oc delete project $AUTOMATION_NAMESPACE
      return 0
    fi

    echo -e "${YELLOW} 🛆 Attempt $i/${RETRIES}: Automation is running. Retrying in $DELAY seconds..."
    sleep $DELAY
  done

  echo -e "${RED} ✘ Timed out waiting for automation job to reach 'Complete' state. Cannot continue with script."
  exit 1
}

check_oc_installed
login_to_openshift
create_openldap_server
create_phpldapadmin
wait_for_ldap_server
populate_ldap_server
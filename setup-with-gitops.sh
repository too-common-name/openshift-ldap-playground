#!/bin/bash

# Check for required inputs
if [ $# -ne 3 ]; then
  echo "Usage: $0 <OPENSHIFT_URL> <USERNAME> <PASSWORD>"
  exit 1
fi

# Colors 
RED='\033[1;31m' 
GREEN='\033[1;32m' 
YELLOW='\033[1;33m' 
BLUE='\033[1;34m'

# Input variables
OPENSHIFT_URL=$1
USERNAME=$2
PASSWORD=$3

# Configuration variables
OC_COMMAND=$(command -v oc)
SUBSCRIPTION_FILE="argocd-operator.yml"
NAMESPACE="openshift-operators"
RETRIES=20
DELAY=10

# Function to check if `oc` is installed
check_oc_installed() {
  if [ -z "$OC_COMMAND" ]; then
    echo -e "${RED} ✘ 'oc' command not found. Please install the OpenShift CLI."
    exit 1
  fi
}

# Function to log in to OpenShift
login_to_openshift() {
  echo -e "${BLUE} Logging in to OpenShift..."

  if ! oc login "$OPENSHIFT_URL" -u "$USERNAME" -p "$PASSWORD" --insecure-skip-tls-verify &>/dev/null; then
    echo -e "${RED} ✘ Failed to log in to OpenShift."
    exit 1
  fi
}

# Function to apply the subscription
apply_subscription() {
  echo -e "${BLUE} Applying ArgoCD subscription..."

  if ! oc apply -f "$SUBSCRIPTION_FILE" &>/dev/null; then
    echo -e "${RED} ✘ Failed to apply subscription."
    exit 1
  fi
}

# Function to wait for the CSV to reach Succeeded state
wait_for_csv_succeeded() {
  echo -e "${BLUE} Waiting for ArgoCD operator to reach 'Succeeded' state..."
  
  for ((i=1; i<=RETRIES; i++)); do
    # Get the CSV name
    CSV_NAME=$(oc get csv -n $NAMESPACE -o name | grep openshift-gitops-operator)

    if [ -n "$CSV_NAME" ]; then
      # Check the status of the CSV
      STATUS=$(oc get "$CSV_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
      
      if [ "$STATUS" == "Succeeded" ]; then
        echo -e "${GREEN} ✔ ArgoCD operator installation succeeded!"
        return 0
      else
        echo -e "${YELLOW} 🛆 Current status: $STATUS. Retrying in $DELAY seconds..."
      fi
    else
      echo -e "${YELLOW} 🛆 CSV for ArgoCD operator not found. Retrying in $DELAY seconds..."
    fi
    
    sleep "$DELAY"
  done

  echo -e "${RED} ✘ ArgoCD operator failed to reach 'Succeeded' state within the timeout."
  exit 1
}

# Main script execution
check_oc_installed
login_to_openshift
apply_subscription
wait_for_csv_succeeded

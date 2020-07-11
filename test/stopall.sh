#!/bin/bash
# Remove all CRD, CRs and operator

dir=`dirname $0`
DEPLOY=$dir/../deploy

# Delete all CRs
kubectl delete myapp --all --wait=false

# Remove service account, role and binding
kubectl delete -f $DEPLOY/service_account.yaml
kubectl delete -f $DEPLOY/role.yaml
kubectl delete -f $DEPLOY/role_binding.yaml

# Delete the operator
#kubectl delete -f deploy/operator.yaml
oc delete po bash-operator --now 

# Refresh the CRD 
kubectl delete -f $DEPLOY/crd-myapp.yaml

# Delete other pods
kubectl delete pods --all --now


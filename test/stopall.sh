#!/bin/bash
# Remove all CRD, CRs and operator

# Delete any CRs
kubectl delete myapp --all --wait=false

sleep 2

# Remove service account, role and binding
kubectl delete -f deploy/service_account.yaml
kubectl delete -f deploy/role.yaml
kubectl delete -f deploy/role_binding.yaml

# Delete the operator
#kubectl delete -f deploy/operator.yaml
oc delete po bash-operator --now 

# Refresh the CRD 
kubectl delete -f test/crd-myapp.yaml

# Delete other pods
kubectl delete pods --all --now

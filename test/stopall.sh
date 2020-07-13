#!/bin/bash
# Remove all CRD, CRs and operator.  Due to "finalizers", all objects need to be removed in the correct order.

dir=`dirname $0`
DEPLOY=$dir/../deploy

# Delete all CRs
kubectl delete myapp --all #--wait=false  # Must delete all of the CRs and cleanup before the CRD can be deleted

# Delete the operator
oc delete po bash-operator --now 

# Remove service account, role and binding
kubectl delete -f $DEPLOY/service_account.yaml
kubectl delete -f $DEPLOY/role.yaml
kubectl delete -f $DEPLOY/role_binding.yaml

# Refresh the CRD 
kubectl delete -f $DEPLOY/crd-myapp.yaml


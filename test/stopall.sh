#!/bin/bash
# Remove all CRD, CRs and operator.  Due to "finalizers", all objects need to be removed in the correct order.

dir=`dirname $0`
DEPLOY=$dir/../deploy
CRD_NAME=myapp

CRs=`kubectl get $CRD_NAME --no-headers | awk '{print $1}'`

for cr in $CRs
do
	kubectl patch $CRD_NAME $cr --type=merge -p '{"metadata": {"finalizers":null}}' >/dev/null
done

kubectl delete pods --selector=$CRD_NAME --wait=false

# Delete all CRs
# Must delete all of the CRs and cleanup before the CRD can be deleted
#kubectl delete $CRD_NAME --all 

# Delete the operator
kubectl delete pod bash-operator --now 

# Remove service account, role and binding
kubectl delete -f $DEPLOY/service_account.yaml
kubectl delete -f $DEPLOY/role.yaml
kubectl delete -f $DEPLOY/role_binding.yaml

# Refresh the CRD 
kubectl delete -f $DEPLOY/crd-myapp.yaml || \
  ( sed "s/\/v1/\/v1beta1/" $DEPLOY/crd-myapp.yaml | kubectl delete -f - ) # needed on older versions of kube


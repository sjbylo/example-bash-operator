#!/bin/bash
# Remove all CRD, CRs and operator.  Due to "finalizers", all objects need to be removed in the correct order.

dir=`dirname $0`
DEPLOY=$dir/../deploy

if ! kubectl get pod bash-operator --no-headers
then
	CRs=`kubectl get myapp --no-headers | awk '{print $1}'`

	for cr in $CRs
	do
		kubectl patch myapp $cr --type=merge -p '{"metadata": {"finalizers":null}}' >/dev/null
	done

	kubectl delete pods --selector=crd=myapp --wait=false
else
	# Delete all CRs
	# Must delete all of the CRs and cleanup before the CRD can be deleted
	kubectl delete myapp --all #--wait=false

	# Delete the operator
	oc delete po bash-operator --now 
fi

# Remove service account, role and binding
kubectl delete -f $DEPLOY/service_account.yaml
kubectl delete -f $DEPLOY/role.yaml
kubectl delete -f $DEPLOY/role_binding.yaml

# Refresh the CRD 
kubectl delete -f $DEPLOY/crd-myapp.yaml


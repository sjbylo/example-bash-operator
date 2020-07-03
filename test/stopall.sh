#!/bin/bash
# Remove all CRD, CRs and operator

# Refresh the CRD 
kubectl delete -f $dir/crd-myapp.yaml 2>/dev/null

# Delete any CRs
kubectl delete myapp --all --wait=false

# Restart the operator
kubectl get pod bash-operator 2>/dev/null && \
	kubectl delete pod bash-operator --now=true # --grace-period=0 --force 


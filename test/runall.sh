#!/bin/bash
# Test operator script

cnt=${1-3} 	# number of concurrent tests, default ia 3
tag=${2-latest}	# which image tag? dev or latest
d=${3-}		# debug output of operator or not (default is info, 1 is some 2 is full)

dir=`dirname $0`

watch_opts="--watch --no-headers --ignore-not-found"

trap stop_all INT
trap stop_all TERM

function stop_all() {
	trap "" INT
	echo
	echo Stopping tests ...

	#kubectl delete myapp --all --wait=false && sleep 2
	#kubectl delete po bash-operator --wait=false 

	l=`jobs -p`; [ "$l" ] && kill $l 2>/dev/null
	sleep 1
	l=`jobs -p`; [ "$l" ] && kill $l 2>/dev/null

	exit 
}

# Set up
kubectl replace -f deploy/service_account.yaml
kubectl replace -f deploy/role.yaml
kubectl replace -f deploy/role_binding.yaml

# Refresh the CRD 
kubectl delete -f $dir/crd-myapp.yaml 2>/dev/null
kubectl create -f $dir/crd-myapp.yaml

# Delete any CRs
kubectl delete myapp --all --wait=false

# Create the deployment 
kubectl replace -f deploy/operator.yaml

# Restart the operator
#kubectl get pod bash-operator 2>/dev/null && \
#	kubectl delete pod bash-operator --grace-period=5 # --force 
	#kubectl delete pod bash-operator --now=true --wait=false # --grace-period=0 --force 

#echo Starting operator from quay.io/sjbylo/bash-operator:$tag ...
#kubectl run bash-operator --env=LOGLEVEL=$d --generator=run-pod/v1 \
	#--image-pull-policy=Always --image=quay.io/sjbylo/bash-operator:$tag || exit 1
	#--image-pull-policy=Never --image=quay.io/sjbylo/bash-operator:$tag || exit 1

kubectl rollout restart deployment/bash-operator 

sleep 0.5

echo -n "Waiting for operator to start ... "
while ! kubectl get pod | grep -q "bash-operator.*\bRunning\b" 
do
	sleep 2
done
echo running

i=1
while [ $i -le $cnt ]
do
	#cat $dir/cr-myapp1.yaml | sed "s/myapp1/myapp$i/" | oc delete -f -
	cat $dir/cr-myapp1.yaml | sed "s/myapp1/myapp$i/" | oc create -f -
	$dir/test.sh myapp$i 3 10 &   # If the cluster is slow, increase 12s to wait longer for test results
	let i=$i+1
done

wait
stop_all 

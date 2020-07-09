#!/bin/bash
# Test operator script

cnt=${1-3} 	# number of concurrent tests, default ia 3
tag=${2-latest}	# which image tag? dev or latest
wait_time=${3-15}  # wait time for each test
loglevel=${4-}	# debug output of operator or not (default is info, 1 is some 2 is full)

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
kubectl create -f deploy/service_account.yaml
kubectl create -f deploy/role.yaml
kubectl create -f deploy/role_binding.yaml

# Refresh the CRD 
#kubectl delete -f $dir/crd-myapp.yaml 2>/dev/null
kubectl create -f $dir/crd-myapp.yaml

# Delete any CRs
kubectl delete myapp --all --wait=false

# Create the deployment 
###sed "s/:latest/:$tag/" deploy/operator.yaml | kubectl create -f -
#kubectl set env deployment/bash-operator INTERVAL_MS=6000
#kubectl set env deployment/bash-operator LOGLEVEL=$loglevel

# Restart the operator
#kubectl get pod bash-operator 2>/dev/null && \
#	kubectl delete pod bash-operator --grace-period=5 # --force 
	#kubectl delete pod bash-operator --now=true --wait=false # --grace-period=0 --force 

echo Starting operator from quay.io/sjbylo/bash-operator:$tag ...
kubectl run bash-operator --env=LOGLEVEL=$loglevel --env=INTERVAL_MS=6000 --generator=run-pod/v1 \
	--image-pull-policy=Always --image=quay.io/sjbylo/bash-operator:$tag || exit 1
	#--image-pull-policy=Never --image=quay.io/sjbylo/bash-operator:$tag || exit 1

sleep 1

echo -n "Waiting for operator to start ... "
while ! kubectl get pod | grep -q "bash-operator.*\bRunning\b" 
do
	sleep 2
done
echo running

sleep 1

i=1
while [ $i -le $cnt ]
do
	cat $dir/cr-myapp1.yaml | sed "s/myapp1/myapp$i/" | oc create -f -
	$dir/test.sh myapp$i 999 $wait_time &   # If the cluster is slow, increase 12s to wait longer for test results
	let i=$i+1
done

wait
stop_all 


#!/bin/bash
# Test operator script

cnt=${1-2} 	# number of concurrent tests, default is 2
tag=${2-latest}	# which image tag? dev or latest
wait_time=${3-15}  # wait time for each test
loglevel=${4-}	# debug output of operator or not (default is info, 1 is some 2 is full)

dir=`dirname $0`
DEPLOY=$dir/../deploy

watch_opts="--watch --no-headers --ignore-not-found"

trap stop_all INT
trap stop_all TERM

function stop_all() {
	trap "" INT
	echo
	echo Stopping tests ...

	# Note: Must delete all CRs before can delete the CRD
	#kubectl delete myapp --all --wait=false && sleep 2
	#kubectl delete po bash-operator --wait=false --now

	l=`jobs -p`; [ "$l" ] && kill $l 
	sleep 1
	l=`jobs -p`; [ "$l" ] && kill $l 

	exit 
}

# Set up
kubectl create -f $DEPLOY/service_account.yaml
kubectl create -f $DEPLOY/role.yaml
kubectl create -f $DEPLOY/role_binding.yaml

# Refresh the CRD 
kubectl create -f $DEPLOY/crd-myapp.yaml || \
  ( sed "s/\/v1/\/v1beta1/" $DEPLOY/crd-myapp.yaml | kubectl create -f - ) # needed on older versions of kube

# Delete any CRs
#kubectl delete myapp --all --wait=false

# Create the deployment 
###sed "s/:latest/:$tag/" deploy/operator.yaml | kubectl create -f -
#kubectl set env deployment/bash-operator INTERVAL_MS=6000
#kubectl set env deployment/bash-operator LOGLEVEL=$loglevel

# Restart the operator
#kubectl get pod bash-operator 2>/dev/null && \
#	kubectl delete pod bash-operator --grace-period=5 # --force 
	#kubectl delete pod bash-operator --now=true --wait=false # --grace-period=0 --force 

#kubectl delete pod bash-operator --now

if ! kubectl get pod bash-operator; then
	echo Starting operator from quay.io/sjbylo/bash-operator:$tag ...
	#kubectl run bash-operator --env=LOGLEVEL=$loglevel --env=INTERVAL_MS=6000 \
	kubectl run bash-operator --generator=run-pod/v1 --env=LOGLEVEL=$loglevel --serviceaccount=bash-operator \
        	--image-pull-policy=Always --image=quay.io/sjbylo/bash-operator:$tag || exit 1

	#kubectl run bash-operator --generator=run-pod/v1 --env=LOGLEVEL=$loglevel --serviceaccount=bash-operator \
	#        --image-pull-policy=Never --image=quay.io/sjbylo/bash-operator:$tag || exit 1

	sleep 1

	echo -n "Waiting for operator to start ... "
	while ! kubectl get pod | grep -q "bash-operator.*\bRunning\b" 
	do
		sleep 2
	done
	echo running
fi

sleep 1

i=1
while [ $i -le $cnt ]
do
	# Create each CR and start the tests ...
	cat $DEPLOY/cr-myapp1.yaml | sed "s/myapp1/myapp$i/" | kubectl create -f -
	$dir/test.sh myapp$i 999 $wait_time &   # If the cluster is slow, increase 12s to wait longer for test results
	#sleep $(($RANDOM % 5 + 1)) # Start tests at random times
	let i=$i+1
done

wait
stop_all 


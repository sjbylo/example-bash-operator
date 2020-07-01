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

	kubectl delete myapp --all --wait=false && sleep 2
	kubectl delete po bash-operator --wait=false 

	l=`jobs -p`; [ "$l" ] && kill $l 2>/dev/null
	sleep 1
	l=`jobs -p`; [ "$l" ] && kill $l 2>/dev/null

	exit 
}

echo Starting operator from quay.io/sjbylo/bash-operator:$tag ...
kubectl run bash-operator --env=LOGLEVEL=$d --generator=run-pod/v1 \
	--image-pull-policy=Always --image=quay.io/sjbylo/bash-operator:$tag || exit 1

echo -n "Waiting for operator to start ... "
while ! kubectl get pod bash-operator | grep -q "\bRunning\b" 
do
	sleep 2
done
echo running

i=1
while [ $i -le $cnt ]
do
	#echo Starting test $i ...
	cat $dir/cr-myapp1.yaml | sed "s/myapp1/myapp$i/" | oc create -f -
	$dir/test.sh myapp$i 3 12 &   # If the cluster is slow, increase 12s to wait longer for test results
	let i=$i+1
done

wait
stop_all 


#!/bin/bash
# Test operator script

if [ "$1" ]
then
	cr=$1		# the custom resource to test, e.g. myapp1
	rep=${2-99999}	# number of test rounds, default is continious
	w=${3-15}	# time to wait for each test succeed or fail
else
       echo "Usage `basename $0` <cr object name> <repetitions> <wait time>"
       echo "Example: `basename $0` myapp1 1 10"
       exit 1
fi

dir=`dirname $0`
DEPLOY=$dir/../deploy

function addCR {
  log="$log:adding CR $cr "
  cat $DEPLOY/cr-myapp1.yaml | sed "s/myapp1/$cr/" | kubectl create -f - >/dev/null
}

function delCR {
  log="$log:deleting CR $cr "
  kubectl delete myapp $cr --now >/dev/null
}

function setReplica {
  log="$log:setting replica to $1 "
  kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/spec/replica", "value": '$1'}]' >/dev/null
}

function checkReplica {
  test $1 -eq `kubectl get po --selector=myapp=$cr 2>/dev/null| grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | wc -l`
}

function delPod {
  log="$log:deleteing $1 pod(s) "
  kubectl get po --selector=myapp=$cr --no-headers 2>/dev/null | \
    grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | tail -$1 | awk '{print $1}' | \
    xargs kubectl delete po --wait=false >/dev/null 2>/dev/null
}

theImage=busybox

function addPod {
  log="$log:adding $1 pod(s) "
  local i=0
  while [ $i -lt $1 ]
  do
      kubectl run $cr-$RANDOM --wait=false --restart=Never --image=$theImage -l myapp=$cr -- sleep 99999999 >/dev/null 2>&1
      #kubectl run $cr-$RANDOM --wait=false --restart=Never --image=$theImage -l myapp=$cr --image-pull-policy=Never -- sleep 99999999 >/dev/null 2>&1
      let i=$i+1
  done
}

function toggleImage {
	if [ "$theImage" = "busybox" ]
	then
		kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/spec/image", "value": "docker/whalesay"}]' >/dev/null
		theImage=docker/whalesay
else
		kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/spec/image", "value": "busybox"}]' >/dev/null
		theImage=busybox
	fi
	log="$log:switching image to $theImage "
}

function stop {
  echo $log FAIL
  exit 1
}

#set -x 

echo Wait time is ${w}s for myapp/$cr ...

cat $DEPLOY/cr-myapp1.yaml | sed "s/myapp1/$cr/" | kubectl create -f - >/dev/null 2>&1

i=1
while [ $i -le $rep ]
do
  echo
  echo Starting round $i of $rep tests for myapp/$cr ...
  log=$cr;r=`echo $(( RANDOM % 3+1))`;setReplica $r; sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;r=0                        ;delCR $r;      sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;r=2                        ;addCR $r;      sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;p=`echo $(( RANDOM % 2+1))`;delPod $p;     sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;p=`echo $(( RANDOM % 3+1))`;addPod $p;     sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;r=`echo $(( RANDOM % 4+1))`;setReplica $r; sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;p=`echo $(( RANDOM % 2+1))`;delPod $p;     sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;p=`echo $(( RANDOM % 1+1))`;toggleImage;   sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;p=`echo $(( RANDOM % 1+1))`;delPod $p;     sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  log=$cr;r=`echo $(( RANDOM % 6  ))`;setReplica $r; sleep $w;checkReplica $r && log="$log PASS" || stop; echo $log
  let i=$i+1
  sleep $(( RANDOM % 10 ))
  echo
done


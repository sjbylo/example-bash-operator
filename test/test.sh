#!/bin/bash
# Test operator script

if [ "$1" ]
then
	cr=$1		# the custom resource to test, e.g. myapp1
	rep=${2-99999}	# number of test rounds, default is continious
	w=${3-10}	# time to wait for each test succeed or fail
else
       echo "Usage `basename $0` <cr object name>"
       echo "Example: `basename $0` myapp1"
       exit 1
fi

function setReplica {
  log="$log:setting replica to $1 "
  kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/spec/replica", "value": '$1'}]' >/dev/null
}

function checkReplica {
  test $1 -eq `kubectl get po --selector=operator=$cr 2>/dev/null| grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | wc -l`
}

function delPod {
  log="$log:deleteing $1 pod(s) "
  kubectl get po --selector=operator=$cr --no-headers 2>/dev/null | \
    grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | tail -$1 | awk '{print $1}' | \
    xargs kubectl delete po --wait=false >/dev/null 2>/dev/null
}

function addPod {
  log="$log:adding $1 pod(s) "
  local i=0
  while [ $i -lt $1 ]
  do
      kubectl run $cr-$RANDOM --generator=run-pod/v1 --wait=false --image=busybox -l operator=$cr -- sleep 9999999 >/dev/null 2>&1
      #kubectl run $cr-$RANDOM --generator=run-pod/v1 --wait=false --image=busybox -l operator=$cr --image-pull-policy=Never -- sleep 9999999 >/dev/null 2>&1
      let i=$i+1
  done
}

function stop {
  echo $log FAIL
  exit 1
}

#set -x 

i=1
while [ $i -le $rep ]
do
  echo
  echo Starting round $i of $rep tests for myapp/$cr ...
  log=$cr;x=`echo $(( RANDOM % 5 ))`; setReplica $x; sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;x=`echo $(( RANDOM % 5 ))`; setReplica $x; sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;y=`echo $(( RANDOM % 3+1))`;addPod $y;     sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;x=`echo $(( RANDOM % 5 ))`; setReplica $x; sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  log=$cr;x=`echo $(( RANDOM % 10))`; setReplica $x; sleep $w;checkReplica $x && log="$log PASS" || stop; echo $log
  let i=$i+1
  echo
done


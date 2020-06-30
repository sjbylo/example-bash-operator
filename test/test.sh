#!/bin/bash
# Test operator script

if [ "$1" ]
then
       cr=$1
else
       echo "Usage `basename $0` <cr object name>"
       echo "Example: `basename $0` myapp1"
       exit 1
fi

function setReplica {
  echo -n "Setting replica to $1 "
  kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/spec/replica", "value": '$1'}]' >/dev/null
}

function checkReplica {
  test $1 -eq `kubectl get po --selector=operator=$cr 2>/dev/null| grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | wc -l`
}

function delPod {
  echo -n "Deleteing $1 pod(s) "
  kubectl get po --selector=operator=$cr --no-headers 2>/dev/null | \
    grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | tail -$1 | awk '{print $1}' | \
    xargs kubectl delete po --wait=false >/dev/null 2>/dev/null
}

function addPod {
  echo -n "Adding $1 pod(s) "
  i=0
  while [ $i -lt $1 ]
  do
      $kubectl run $cr-$RANDOM --generator=run-pod/v1 --wait=false --image=busybox -l operator=$cr -- sleep 9999999 >/dev/null 2>&1
      kubectl run $cr-$RANDOM --wait=false --image=busybox -l operator=$cr -- sleep 9999999 >/dev/null 2>&1
      let i=$i+1
  done
}

function stop {
  echo FAIL
  exit 1
}

#set -x 

while true
do
  echo
  echo Starting tests ... 
  x=`echo $(( RANDOM % 5 ))`; setReplica $x; sleep 10;checkReplica $x && echo PASS || stop
  x=`echo $(( RANDOM % 5 ))`; setReplica $x; sleep 10;checkReplica $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep 10;checkReplica $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep 10;checkReplica $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;addPod $y;     sleep 10;checkReplica $x && echo PASS || stop 
  x=`echo $(( RANDOM % 5 ))`; setReplica $x; sleep 10;checkReplica $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep 10;checkReplica $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y;     sleep 10;checkReplica $x && echo PASS || stop
  x=`echo $(( RANDOM % 10))`; setReplica $x; sleep 10;checkReplica $x && echo PASS || stop
  echo
done


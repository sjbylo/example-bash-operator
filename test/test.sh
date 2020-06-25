#!/bin/bash
# Test operator script

cr=$1 

function setReplicas {
  echo -n "setting replica to $1 "
  oc patch myapp $cr --type=json -p '[{"op": "replace", "path": "/spec/replica", "value": '$1'}]' >/dev/null
}

function checkReplicas {
  test $1 -eq `oc get po --selector=operator=$cr | grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | wc -l`
}

function delPod {
  echo -n "deleteing $1 pod(s) "
  oc get po --selector=operator=$cr --no-headers | \
    grep -e "\bRunning\b" -e "\bContainerCreating\b" -e "\bPending\b" | tail -$1 | awk '{print $1}' | \
    xargs oc delete po --wait=false >/dev/null 2>/dev/null
}

function addPod {
  echo -n "adding $1 pod(s) "
  i=0
  while [ $i -lt $1 ]
  do
      oc run $cr-$RANDOM --wait=false --image=busybox --generator=run-pod/v1 \
        -l operator=$cr -- sleep 9999999 >/dev/null
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
  x=`echo $(( RANDOM % 5 ))`;  setReplicas $x;sleep 6;checkReplicas $x && echo PASS || stop
  x=`echo $(( RANDOM % 5 ))`;  setReplicas $x;sleep 6;checkReplicas $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y     ;sleep 6;checkReplicas $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y     ;sleep 6;checkReplicas $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;addPod $y     ;sleep 6;checkReplicas $x && echo PASS || stop 
  x=`echo $(( RANDOM % 5 ))`;  setReplicas $x;sleep 6;checkReplicas $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y     ;sleep 6;checkReplicas $x && echo PASS || stop
  y=`echo $(( RANDOM % 3+1))`;delPod $y     ;sleep 6;checkReplicas $x && echo PASS || stop
  x=`echo $(( RANDOM % 10))`;  setReplicas $x;sleep 6;checkReplicas $x && echo PASS || stop
  echo
done


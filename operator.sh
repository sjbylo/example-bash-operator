#!/bin/bash 
# MyApp Operator

cr_name=myapp 

#set -Eeuo pipefail
#set -o pipefail

base=`basename $0`

rm -f .mypipe*
rm -f /tmp/.$base.pids

function cleanup {
	if [ "$1" ]
	then
		# CR deleted
		rm -f .mypipe.$1.$$
	else
		# Clean up everything
		rm -f .mypipe.*
		/tmp/.$base.pid
	fi
}

function make_random_str {
	len=${1-6}
	cat /dev/urandom | tr -dc 'a-z0-9' | fold -w $len | head -n 1
}

function testeval {
	[ ! "$@" ] && echo "Missing arg(s)" && exit 1
}

function save_pid {
	testeval "$@"
	echo $@ >> /tmp/.$base.pids
}

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
        echo "** Trapped CTRL-C"

	cleanup

	echo Killing subprocesses `cat /tmp/.$base.pids` ...
	kill `cat /tmp/.$base.pids` 2>/dev/null

	##sleep 1 ; kill -9 `cat /tmp/.$base.pids`

	echo Operator $base exiting now ...
	exit 0
}

function reconcile {
  cr=$1
  #before=`date +%s%3N`
  #declare -A times
  #declare -A lastlines

  backlog=

  while true
  do
	#read line 
	echo "read -t1 line" >&2
	#[ "$backlog" ] && read -t1 line || read line 
	read -t1 line   # We check every 2 seconds if there's a "skipped event" to process
	ret=$?
	echo "line=[$line] ret=$ret" >&2 

	#obj=`echo $line | awk '{print $1}'`
  	#times["$obj"]=`date +%s%3N`

	if [ $ret -eq 142 ]
	then
		echo -n \|
		if [ "$backlog" ]
		then
			echo -n R #>&2
			line=$backlog
		else
			echo -n S #>&3
			continue
		fi
	elif [ $ret -gt 1 ]
	#if [ $ret -gt 1 ]
	then
		echo READ ERROR $? exiting ... >&2  # Should never get here
		exit 1
	fi

  	now=`date +%s%3N`
	#echo `expr $now - 3000 - $before` >&2

	# If still within 3s from the last execution?...
	if [ $before -gt `expr $now - 3000` ]
	then
		backlog=$line
		echo -n . #>&2
		continue
	fi

	before=$now
	backlog=
	echo

	line=`echo $line | tr -s " "`
	#type=`echo $line | cut -d: -f1`
	#ma=`echo $line | cut -d: -f2-`
	obj=`echo $line | awk '{print $1}'`

	#log="$type "
	log=
	log=$log"event=[$line] "

	# Get the required state from the spec

	spec=`oc get myapp $cr -o json`
	if [ $? -eq 1 ]
	then
		# If the main CR is deleted kill all and quit
		pods_running=`oc get po --selector=operator=$cr --no-headers --ignore-not-found |awk '{print $1}'`
		for f in $pods_running
		do
			oc delete pod $f --wait=false  2>/dev/null
		done
		echo myapp/$cr deleted exiting controller for myapp/$cr ...
		exit 
	fi	
		
	spec_replica=`echo "$spec" | jq '.spec.replica' | tr -d \"`
	spec_image=`echo "$spec" | jq '.spec.image' | tr -d \"`
	spec_cmd=`echo "$spec" | jq '.spec.command' | tr -d \"`

	log=$log"[$spec_replica] [$spec_image] [$spec_cmd] "

	if [ ! "$spec_replica" ] 
	then
		echo EXIT spec_replica missing
		exit 
	fi

	# Get actual state

	pods_running=`oc get po --selector=operator=$cr --ignore-not-found | \
		grep -e "\bRunning\b" -e "\bPending\b" -e "\bContainerCreating\b"| \
		awk '{print $1}' | sort -n`
	if [ "$pods_running" ]
	then
		stat_replica=`echo "$pods_running" | wc -l`
	else
		stat_replica=0
	fi

	if [ $spec_replica -lt $stat_replica ]
	then
		# Delete pods
		start=`expr $spec_replica - $stat_replica`
		log=$log"Adjusting pod count by [$start]"
		todel=`echo "$pods_running" | tail $start`
		oc delete --wait=false po $todel >/dev/null
	elif [ $spec_replica -gt $stat_replica ]
	then
		# Start pods
		start=`expr $spec_replica - $stat_replica`
		log=$log"Adjusting pod count by [$start]"
		while [ $start -gt 0 ]
		do
			oc run $cr-`make_random_str` --wait=false --image=$spec_image --generator=run-pod/v1 -l operator=$cr -- $spec_cmd >/dev/null
			let start=$start-1
		done
		stat_image=$spec_image
		stat_cmd=$spec_cmd
	else
		log=$log"Nothing to do"
	fi

	# write the status into the cr
	#oc patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/image", "value": "$stat_image"}]'
	#oc patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/command", "value": "$stat_cmd"}]'
	#oc patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/replica", "value": "$stat_replica"}]'
	
	echo "$cr:$log"
  done < .mypipe.$$.$cr
}

# Start Operator

rm -f /tmp/.cr-$cr_name
#mylockclear

watch_opts="--watch --no-headers --ignore-not-found"

cr_list=`oc get $cr_name --no-headers` 
while [ ! "$cr_list" ]
do
	sleep 5  # Wait for CRs to be created
	cr_list=`oc get $cr_name --no-headers` 
done

function operator_exit {
	echo "$@" >&2
	exit 1
}

P=
# Start the watches ... pipe events into the reconcile function
for cr in `echo "$cr_list" | awk '{print $1}'`
do
	echo "Starting controller for CR $cr"

	PIPE=.mypipe.$$.$cr
	mkfifo $PIPE

	( 
		while true
		do
			echo "Starting oc get myapp $cr $watch_opts" `date` >&2
			if ! kubectl get myapp $cr $watch_opts
			then
				echo oc get myapp quit with $ret >&2
			fi
		done > $PIPE
		echo myapp/$cr watch stopping ...
		ctrl_c  # just for testing
	) &
	save_pid $!

	sleep 1

	(
		while true
		do
			echo Starting oc get pod --selector=operator=$cr $watch_opts `date` >&2
			if ! kubectl get pod --selector=operator=$cr $watch_opts 
			then
				echo oc get pod quit with $? >&2
			fi
		done > $PIPE
		echo pod watch stopping ...
		ctrl_c  # just for testing
	) &
	save_pid $!
done

for cr in `echo "$cr_list" | awk '{print $1}'`
do
	echo Starting reconcile function for $cr
	reconcile $cr &
done

#cr_list_stat=`oc get $cr_name --no-headers` 
#while true
#do
	#if [ "$cr_list_stat" != "cr_list_spec" ]
	#then
		#sleep 5  # Wait for CRs to be created
		#cr_list=`oc get $cr_name --no-headers` 
#done

wait

echo Execution should never reach here ... quitting
exit 1


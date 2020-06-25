#!/bin/bash 
# MyApp Operator

# Set the name of the CRDs
cr_name=myapp 

#set -Eeuo pipefail
#set -o pipefail

base=`basename $0`

function cleanup {
	if [ "$1" ]
	then
		# CR deleted
		rm -f .mypipe.$1.$$
	else
		# Clean up everything
		rm -f .mypipe.*
		rm -f /tmp/.$base.pid
	fi
}

cleanup

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

	echo Stopping watch subprocesses ...
	kill `cat /tmp/.$base.pids` 2>/dev/null

	echo Operator $base exiting now ...
	exit 0
}

function reconcile {
  cr=$1
  before=`date +%s%3N`
  backlog=

  # Loop through all the events from the watched objects.  Supress events if they come fast (withing 3 seconds)
  while true
  do
	#[ "$backlog" ] && read -t1 line || read line 
	read -t1 line   # We check every second if there's a "skipped event" to process
	ret=$?
	echo "line=[$line] ret=$ret" >&2 

	# If read timed out
	if [ $ret -eq 142 ]
	then
		# If there is a backlog event that could be processed
		echo -n \| >&2
		if [ "$backlog" ]
		then
			# Process the backlog
			echo -n R >&2
			line=$backlog
		else
			# Do nothing this time
			echo -n S >&3
			continue
		fi
	elif [ $ret -gt 1 ]
	then
		echo READ ERROR $? exiting ... >&2  # Should never get here
		exit 1
	fi

	# Remember the time now in ms
  	now=`date +%s%3N`

	# If still within 3s from the last processing? ...
	if [ $before -gt `expr $now - 3000` ]
	then
		# Remember the event and skip
		backlog=$line
		echo -n . >&2
		continue
	fi

	before=$now
	backlog=
	echo >&2

	line=`echo $line | tr -s " "`
	obj=`echo $line | awk '{print $1}'`

	log=
	log=$log"event=[$line] "

	# Now, reconcile the state

	# Get the required state from the CR's spec
	spec=`kubectl get myapp $cr -o json`
	if [ $? -eq 1 ]
	then
		# If the main CR is deleted kill all and quit this controller
		pods_running=`kubectl get po --selector=operator=$cr --no-headers --ignore-not-found |awk '{print $1}'`
		for pod in $pods_running
		do
			kubectl delete pod $pod --wait=false  2>/dev/null
		done
		echo myapp/$cr deleted exiting controller for myapp/$cr ...
		exit 
	fi	
		
	spec_replica=`echo "$spec" | jq '.spec.replica' | tr -d \"`
	spec_image=`echo "$spec" | jq '.spec.image' | tr -d \"`
	spec_cmd=`echo "$spec" | jq '.spec.command' | tr -d \"`

	log=$log"spec=[$spec_replica, $spec_image, $spec_cmd] "

	# If this is missing, really there's a problem!
	if [ ! "$spec_replica" ] 
	then
		echo "EXIT spec_replica missing!!"
		exit 
	fi

	# Get actual state (i.e. number of pods)
	pods_running=`kubectl get po --selector=operator=$cr --ignore-not-found | \
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
		kubectl delete --wait=false po $todel >/dev/null
	elif [ $spec_replica -gt $stat_replica ]
	then
		# Start pods
		start=`expr $spec_replica - $stat_replica`
		log=$log"Adjusting pod count by [$start]"
		while [ $start -gt 0 ]
		do
			kubectl run $cr-`make_random_str` --wait=false --image=$spec_image --generator=run-pod/v1 -l operator=$cr -- $spec_cmd >/dev/null
			let start=$start-1
		done
		#stat_image=$spec_image
		#stat_cmd=$spec_cmd
	else
		log=$log"Nothing to do"
	fi

	# write the status into the cr
	#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/image", "value": "$stat_image"}]'
	#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/command", "value": "$stat_cmd"}]'
	#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/replica", "value": "$stat_replica"}]'
	
	echo "$log"

  done < .mypipe.$$.$cr
}

# Start Operator

rm -f /tmp/.cr-$cr_name

watch_opts="--watch --no-headers --ignore-not-found"

# Wait for related CRs to be created
cr_list=`kubectl get $cr_name --no-headers` 
while [ ! "$cr_list" ]
do
	sleep 5  # Wait for CRs to be created
	cr_list=`kubectl get $cr_name --no-headers` 
done

function operator_exit {
	echo "$@" >&2
	exit 1
}

P=
# Start the event watches ... pipe events into the reconcile function
for cr in `echo "$cr_list" | awk '{print $1}'`
do
	echo "Starting controller for CR $cr"

	# All events are passed through this named pipe
	PIPE=.mypipe.$$.$cr
	mkfifo $PIPE

	( 
		while true
		do
			echo "Starting kubectl get myapp $cr $watch_opts" `date` >&2
			if ! kubectl get myapp $cr $watch_opts
			then
				echo kubectl get myapp quit with $ret >&2  # sometimes this can happen
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
			echo Starting kubectl get pod --selector=operator=$cr $watch_opts `date` >&2
			if ! kubectl get pod --selector=operator=$cr $watch_opts 
			then
				echo kubectl get pod quit with $? >&2  # sometimes this can happen
			fi
		done > $PIPE
		echo pod watch stopping ...
		ctrl_c  # just for testing
	) &
	save_pid $!
done

for cr in `echo "$cr_list" | awk '{print $1}'`
do
	echo Starting reconcile function for Custom Resource:$cr
	reconcile $cr &
done

# Need to build a CR manager which looks out for new CRs and deleted CRs.
# If a new CR appears, then a new controller should be created
#cr_list_stat=`kubectl get $cr_name --no-headers` 
#while true
#do
	#if [ "$cr_list_stat" != "cr_list_spec" ]
	#then
		#sleep 5  # Wait for CRs to be created
		#cr_list=`kubectl get $cr_name --no-headers` 
#done

wait

echo Execution should never reach here ... quitting
exit 1


#!/bin/bash 
# MyApp Operator

# Set the name of the CRDs
cr_name=myapp 

#set -Eeuo pipefail
#set -o pipefail

base=`basename $0`

tempfile=/tmp/.operator.$cr_name.$$

function cleanup {
	# $1 is cr
	if [ "$1" ]
	then
		# CR deleted - clean up only the CR related files
		rm -f $tempfile.$1.pipe
		rm -f $tempfile.$1.pids
	else
		# Clean up everything
		rm -f $tempfile.*
	fi
}

cleanup

function make_random_str {
	len=${1-6}
	cat /dev/urandom | tr -dc 'a-z0-9' | fold -w $len | head -n 1
}

#function testeval {
#	[ ! "$@" ] && echo "Missing arg(s)" && xit 1
#}

function save_pid {
	# $1 is cr name
	# $2 is PID
	echo $2 >> $tempfile.$1.pids
}

function get_pids {
	# $1 is cr name
	cat $tempfile.$1.pids
}

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
trap ctrl_c TERM

function ctrl_c() {
	echo "CTRL-C trapped"

	#kill $$
	#sleep 2

	echo Terminating all watch subprocesses ...
	kill `cat $tempfile.*.pids` 
	sleep 1
	kill `cat $tempfile.*.pids` 
	sleep 3
	kill -9 `cat $tempfile.*.pids` 

	cleanup

	echo Operator $base exiting now ...
	exit 0
}

function my_exit {
	cleanup
	exit $1
}

function reconcile {
	local cr=$1
	local before=`date +%s%3N`
	local backlog=
	local PIPE=$tempfile.$cr.pipe

	# Loop through all the events from the watched objects.  Suppress events if they come fast (within 3 seconds)
	while true
		do
		#[ "$backlog" ] && read -t1 line || read line 
		read -t1 line   # We check every second if there's a "skipped event" to process
		ret=$?
		[ "$DEBUG" ] && echo "line=[$line] ret=$ret" >&2 

		# If read timed out
		if [ $ret -eq 142 ]
		then
			# If there is a backlog event that could be processed
			[ "$DEBUG" ] && echo -n \| >&2
			if [ "$backlog" ]
			then
				# Process the backlog
				[ "$DEBUG" ] && echo -n R >&2
				line=$backlog
			else
				# Do nothing this time
				[ "$DEBUG" ] && echo -n S >&2
				continue
			fi
		elif [ $ret -gt 1 ]
		then
			echo READ ERROR $? exiting ... >&2  # Should never get here
			my_exit 1
		fi

		# Remember the time now in ms
		now=`date +%s%3N`

		# If still within 3s from the last processing? ...
		if [ $before -gt `expr $now - 3000` ]
		then
			# Remember the event and skip
			backlog=$line
			[ "$DEBUG" ] && echo -n . >&2
			continue
		fi

		before=$now
		backlog=
		[ "$DEBUG" ] && echo >&2

		line=`echo $line | tr -s " "`
		obj=`echo $line | awk '{print $1}'`

		log=
		log=$log"event=[$line] "

		# Now, reconcile the state

		# Get the required state from the CR's spec
		# Do this better - check for myapp cr deleted event FIXME
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
			return   # return from here and the controller will be stopped 
			#sleep 99999  # wait to be terminated 
		fi	
		
		spec_replica=`echo "$spec" | jq '.spec.replica' | tr -d \"`
		spec_image=`echo "$spec" | jq '.spec.image' | tr -d \"`
		spec_cmd=`echo "$spec" | jq '.spec.command' | tr -d \"`

		log=$log"spec=[$spec_replica, $spec_image, $spec_cmd] "

		# If this is missing, really there's a problem!
		if [ ! "$spec_replica" ] 
		then
			echo "EXIT spec_replica missing!!"
			my_exit 1
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
				kubectl run $cr-`make_random_str` --wait=false --image=$spec_image -l operator=$cr -- $spec_cmd >/dev/null
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

	done < $PIPE
}

# Start the event watches ... pipe events into the reconcile function
function start_controller {
	cr=$1

	# Start the controller 
	(
		# All events for this controller are passed through this named pipe
		PIPE=$tempfile.$cr.pipe
		mkfifo $PIPE
		watch_opts="--watch --no-headers --ignore-not-found"

		# Create a fn to keep this command running if it fails FIXME
		kubectl get myapp $cr $watch_opts > $PIPE &
		save_pid $cr $!

		sleep 0.5

		# Create a fn to keep this command running if it fails FIXME
		kubectl get pod --selector=operator=$cr $watch_opts > $PIPE &
		save_pid $cr $!

		sleep 0.5

		echo Starting reconcile function for Custom Resource: $cr_name/$cr
		reconcile $cr   # wait here

		stop_controller $cr
		cleanup $cr
	) &
}

function stop_controller {
	# Somehow ask controller to kill all pods # FIXME

set -x
	get_pids $1
	cat $tempfile.$1.pids
	echo Stopping pids = `get_pids $1`
	kill `get_pids $1`
	sleep 2
	kill `get_pids $1`
	sleep 2
	kill -9 `get_pids $1`

	cleanup $cr
set +x
}


function main_manager {
	# This function does the following
	# - Looks for new CRs and for each new CR it starts a new controller
	# - Looks for deleted CRs and for each deleted CR it stops the controller (which will also stop all managed objects) 

	declare -A cr_map

	while true
	do
		cr_list=`kubectl get $cr_name --no-headers | awk '{print $1}'`

		# Check for new CRs
		for cr in `echo "$cr_list"`
		do
			if [ "${cr_map[$cr]}" ]
			then
				[ "$DEBUG" ] && echo CR $cr controller already started >&2
			else
				echo Starting controller for CR $cr >&2
				start_controller $cr
				cr_map[$cr]=1
				[ "$DEBUG" ] && echo ${cr_map[$cr]} >&2
				
			fi
		done

		# Check for deleted CRs
		for cr in "${!cr_map[@]}"
		do
			[ "$DEBUG" ] && echo cr=$cr >&2
			if ! kubectl get $cr_name $cr --no-headers >/dev/null
			then
				echo Stopping controller for CR $cr >&2
				sleep 5 # Give time to delete all pods
				[ "$DEBUG" ] && echo cr=$cr >&2
				#### stop_controller $cr &
				sleep 2
				unset cr_map[$cr]
			fi
		done

		sleep 5
	done
}

# Start
main_manager

echo Execution should never reach here ... quitting
exit 1


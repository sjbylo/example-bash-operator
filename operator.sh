#!/bin/bash 
# MyApp Operator

[ "$LOGLEVEL" = "2" ] && set -x

# Set the name of the CRD
CRD_NAME=myapp 

base=`basename $0`
tempfile=/tmp/.op.$CRD_NAME.$$

# Clean up temp files for each custom resource  or for all
function cleanup {
	# $1 is cr
	if [ "$1" ]
	then
		# Custom resource deleted - clean up only the custom resource  related files
		rm -f $tempfile.$1.pipe
		rm -f $tempfile.$1.pids
	else
		# Clean up everything
		rm -f $tempfile.*
	fi
}

function make_random_str {
	len=${1-6}
	cat /dev/urandom | tr -dc 'a-z0-9' | fold -w $len | head -n 1
}

function save_pid {
	# $1 is cr name
	# $2 is PID
	echo $2 >> $tempfile.$1.pids
}

function get_pids {
	# $1 is cr name
	cat $tempfile.$1.pids
}

# trap ctrl-c or terminate and call exit_all()
trap exit_all INT
trap exit_all TERM

function exit_all() {
	echo "Trap starting ..."

	echo Terminating all watch subprocesses ...
	kill `cat $tempfile.*.pids` 
	sleep 1
	kill `cat $tempfile.*.pids`  2>/dev/null
	sleep 1
	kill -9 `cat $tempfile.*.pids`  2>/dev/null

	cleanup

	echo Operator $base exiting now ...
	exit 0
}

function reconcile {
	local cr=$1
	local before=`date +%s%3N`
	local backlog=
	local PIPE=$tempfile.$cr.pipe

	# Loop through all the events from the watched objects.  Suppress events if they come too fast (within 3 seconds)
	while true
		do
		#[ "$backlog" ] && read -t1 line || read line 
		read -t1 line   # We check every second if there's a "skipped event" to process
		ret=$?
		[ "$LOGLEVEL" ] && echo "line=[$line] ret=$ret" >&2 

		# If read timed out
		if [ $ret -eq 142 ]
		then
			# If there is a backlog event that could be processed
			[ "$LOGLEVEL" ] && echo -n \| >&2
			if [ "$backlog" ]
			then
				# Process the backlog
				[ "$LOGLEVEL" ] && echo -n R >&2
				line=$backlog
			else
				# Do nothing this time
				[ "$LOGLEVEL" ] && echo -n S >&2
				continue
			fi
		elif [ $ret -gt 1 ]
		then
			echo Warning: read error $? >&2  # Should never get here
		fi

		# Remember the time now in ms
		now=`date +%s%3N`

		# If still within 3s from the last processing? ...
		if [ $before -gt `expr $now - 3000` ]
		then
			# Remember the event and skip
			backlog=$line
			[ "$LOGLEVEL" ] && echo -n . >&2
			continue
		fi

		before=$now
		backlog=
		[ "$LOGLEVEL" ] && echo >&2

		line=`echo $line | tr -s " "`
		obj=`echo $line | awk '{print $1}'`

		log=
		log=$log"event=[$line] "

		####################################
		# Now, reconcile the state

		# Get the required state from the custom resource's spec
		# Do this better - check for myapp cr deleted event FIXME
		spec=`kubectl get myapp $cr -o json`
		if [ $? -eq 1 ]
		then
			# If the main custom resource is deleted kill all objects and quit this controller
			kubectl delete pod --selector=operator=$cr --wait=false 

			echo Exiting controller for $CRD_NAME/$cr ...
			return   # return from this fn() and the controller will stop 
		fi	
		
		spec_replica=`echo "$spec" | jq -r '.spec.replica'`
		spec_image=`echo "$spec"   | jq -r '.spec.image'`
		spec_cmd=`echo "$spec"     | jq -r '.spec.command'`

		log=$log"spec=[$spec_replica, $spec_image, $spec_cmd] "

		# If this is missing, really there's a problem!
		if [ ! "$spec_replica" ] 
		then
			echo "EXIT spec_replica missing!!"
			exit_all
		fi

		# Get actual state (i.e. number of pods)
		pods_running=`kubectl get pod --selector=operator=$cr --ignore-not-found | \
			grep -e "\bRunning\b" -e "\bPending\b" -e "\bContainerCreating\b"| \
			awk '{print $1}' | sort -n`
		if [ "$pods_running" ]
		then
			stat_replica=`echo "$pods_running" | wc -l`
		else
			stat_replica=0
		fi

		delta=`expr $spec_replica - $stat_replica`

		if [ $delta -lt 0 ]
		then
			# Delete pods
			log=$log"Adjusting pod count by [$delta]"
			todel=`echo "$pods_running" | tail $delta`
			kubectl delete --wait=false pod $todel >/dev/null
		elif [ $delta -gt 0 ]
		then
			# Start pods
			log=$log"Adjusting pod count by [$delta]"
			while [ $delta -gt 0 ]
			do
				kubectl run $cr-`make_random_str` --generator=run-pod/v1 --wait=false --image=$spec_image -l operator=$cr -- $spec_cmd >/dev/null
				let delta=$delta-1
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
		#################################

	done < $PIPE
}

function run_cmd {
	while true
	do
		$@
		echo "Command '"$@"' failed with $? ..."
	done
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

		export OBJ_TYPE=myapp
		run_cmd kubectl get myapp $cr $watch_opts > $PIPE &
		save_pid $cr $!

		sleep 0.5

		export OBJ_TYPE=pod
		run_cmd kubectl get pod --selector=operator=$cr $watch_opts > $PIPE &
		save_pid $cr $!

		echo Starting reconcile function for custom resource: $CRD_NAME/$cr
		reconcile $cr   # wait here

		stop_controller $cr
		cleanup $cr
	) &
}

function stop_controller {
	# $1 = custom resource
	local cr=$1
	echo Stopping processes: `get_pids $cr`

	kill `get_pids $cr`
	sleep 1
	kill `get_pids $cr` 2>/dev/null
	sleep 2
	kill -9 `get_pids $cr` 2>/dev/null

	cleanup $cr
}


function main_manager {
	# This function does the following
	# - Looks for new custom resource and for each new custom resource it starts a new controller
	# - Looks for deleted custom resources and for each deleted custom resource it stops the controller (which will also stop all managed objects) 

	declare -A cr_map

	local wait_time=5

	while true
	do
		cr_list=`kubectl get $CRD_NAME --no-headers | awk '{print $1}'`

		# Check for new custom resources
		for cr in $cr_list
		do
			if [ "${cr_map[$cr]}" ]
			then
				[ "$LOGLEVEL" ] && echo Controller for $CRD_NAME/$cr already started >&2
			else
				echo Starting controller for $CRD_NAME/$cr >&2
				start_controller $cr
				cr_map[$cr]=1
				
			fi
		done

		# Check for deleted CRs
		for cr in "${!cr_map[@]}"
		do
			if ! kubectl get $CRD_NAME $cr --no-headers >/dev/null
			then
				echo Stopping controller for $CRD_NAME/$cr >&2
				sleep 5 # Give time to controlleer to delete it's resources
				unset cr_map[$cr]
			fi
		done

		sleep $wait_time
	done
}

# Start
cleanup
main_manager

echo Execution should never reach here ... quitting
exit 1


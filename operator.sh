#!/usr/bin/env bash 
# MyApp Operator acts like a replica-set controller
# Bash version 4 or higher is needed
# Reasonably up to date tr and date commands are needed

# Set the name of the CRD.  This is a fictitious application called MyApp. 
CRD_NAME=myapp 

base=`basename $0`
tempfile=/tmp/.op.$CRD_NAME.$$

# To run this script directly on MacOS, install gdate and gtr with brew.
type gdate 2>/dev/null >&2 && DATE_CMD=gdate || DATE_CMD=date
type gtr   2>/dev/null >&2 && TR_CMD=gtr     || TR_CMD=tr

[ "$LOGLEVEL" = "2" ] && set -x
[ "$LOGLEVEL" ] || LOGLEVEL=0
[ $LOGLEVEL -ge 1 ] && echo LOGLEVEL=$LOGLEVEL

echo MyApp Operator process ID: $$

INTERVAL_MS=${INTERVAL_MS-3000}     # time to wait in ms before making changes to controlled pods in the reconcile function.
[ $LOGLEVEL -ge 1 ] && echo INTERVAL_MS=$INTERVAL_MS


# Clean up temp files for each custom resource or for all
function cleanupTempFiles {
	# $1 is the cr name
	if [ "$1" ]
	then
		# Custom resource deleted - clean up only the custom resource related files
		[ $LOGLEVEL -ge 1 ] && echo Deleting files: $tempfile.$1.pipe $tempfile.$1.pids >&2
		rm -f $tempfile.$1.pipe $tempfile.$1.pids  #FIXME pids needed? 
	else
		# Clean up everything
		[ $LOGLEVEL -ge 1 ] && echo Deleting files: $tempfile.* >&2
		rm -f $tempfile.*
	fi
}

function make_random_str {
	len=${1-6}
	cat /dev/urandom | $TR_CMD -dc 'a-z0-9' | fold -w $len | head -n 1
}

# trap ctrl-c or terminate and call exit_all()
trap exit_all INT
trap exit_all TERM

# Clean up everything and exit
function exit_all() {
	echo
	echo "Trap starting ..."

	[ $LOGLEVEL -ge 1 ] && echo Jobs: >&2 && jobs >&2

	echo Terminating processes:
	kill `jobs -p`
	sleep 1
	kill `jobs -p` 2>/dev/null

	cleanupTempFiles

	echo Operator $base exiting now ...
	exit 0
}

#### All following functions are related to the reconcile function

function getCRSpec {
	cr=$1

	json=`kubectl get myapp $cr -o json`
	if [ $? -ne 0 ]; then
		sleep 1
		json=`kubectl get myapp $cr -o json`  # Try a 2nd time!
		[ $? -ne 0 ] && return 1	
	fi

	spec_replica=`echo "$json" | jq -r '.spec.replica'`
	spec_image=`echo "$json"   | jq -r '.spec.image'`
	spec_cmd=`echo "$json"     | jq -r '.spec.command'`
	metadata_deletionTimestamp=`echo "$json"     | jq -r '.metadata.deletionTimestamp'`

	[ ! "$spec_image" -o ! "$spec_replica" -o ! "$spec_cmd" ] && echo "Warning ($cr): spec missing [$spec_image $spec_replica $spec_cmd]" >&2 

	return 0
}

# Simple timer 
function timeUp {
	# If still within $1 ms from the last time $before
	local interval=$1   # interval in ms
	#local before=$2  

	if [ $(( $before + $interval )) -gt `$DATE_CMD +%s%3N` ]
	then
		[ $LOGLEVEL -ge 2 ] && echo Timer running >&2
		return 0  # time not up
	fi
	[ $LOGLEVEL -ge 2 ] && echo Time up >&2

	before=`$DATE_CMD +%s%3N` 

	return 1  # time up
}

# Refresh the current state of the controlled pods
function getRunningPods {
	local cr=$1

	running_pods="`kubectl get pod --selector=operator=$cr --ignore-not-found --no-headers | \
		grep -e "\bRunning\b" -e "\bPending\b" -e "\bContainerCreating\b"| \
		awk '{print $1}'`"
	[ "$running_pods" ] && running_pod_count=`echo "$running_pods" | wc -l | $TR_CMD -d " "` || running_pod_count=0
}

function reconcile {
	local cr=$1
	local PIPE=$2

	before=0

	getCRSpec $cr  # Fetch the initial spec from the CR object

	# Set up the status in the CR
	kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status", "value": {}}]' >/dev/null

	getRunningPods $cr

	# FIXME: Shortcut is to simply assume any existing pods are using these values by default.  
	# Should really check or just delete all existing pods.
	state_image=busybox
	state_cmd="sleep 99999"

	# Loop through all the events from the watched objects (in this case just myapp objects).
	while true
	do
		read -t1 event   # -t timeout used so we have a chance to make changes. 
		ret=$?
		[ $LOGLEVEL -ge 1 -a "$event" ] && echo "ret=[$ret] event=[$event]" >&2

		# If there is a read timeout and also data?
		[ $ret -eq 142 -a "$event" ] && echo "Warning ($cr): timeout and event=[$event]" # This should never happen 

		# If event available, process $event
		if [ "$event" ]
		then
			# Each event is <event type>:<event details>   e.g.  myapp:myapp1 or pod:mypod-xyz
			obj=`echo $event | cut -d: -f1`

			if [ "$obj" = "myapp" ]; then
				getCRSpec $cr  # refresh the spec

				# Check if the object is being deleted ...
				if [ "$metadata_deletionTimestamp" != "null" ]; then 
					[ $LOGLEVEL -ge 1 ] && echo "Deleting all controlled pods for $cr" >&2
					kubectl delete pod --selector=operator=$cr --now --wait=false >/dev/null

					# Remove the finalizers ... allow the CR object to be garbage collected 
					kubectl patch myapp $cr --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]' >/dev/null

					return 0  # This will stop and clean up the controller 
				fi
			#elif [ "$obj" = "cleanup" ]; then  # FIXME only needed if completed pods need to be deleted
				#kubectl delete pod --selector=operator=$cr --now --wait=false --field-selector status.phase=Succeeded >/dev/null 
			else
				[ $LOGLEVEL -ge 1 ] && echo "Warning ($cr): Unknown object type [$obj]" >&2
				# return # This should never happen (but it does!) 
				# Sometimes "read" returns "yapp" instead of "myapp"!
				# "Warning (myapp1): Unknown object type [yapp]"
			fi
		else
			[ $LOGLEVEL -ge 2 ] && echo "Warning ($cr): Read returned [$ret].  Event missing" >&2
		fi
		
		timeUp $INTERVAL_MS $before && continue       # If timer still running, continue (process next event)

		# Refresh current state of controlled pods
		getRunningPods $cr 

		# Start the log message 
		log="$cr $running_pod_count/$spec_replica running. " 

		# If the cr spec has changed (image or command params) restart all pods with the new values ...
		if [ "$state_image" != "$spec_image" -o "$state_cmd" != "$spec_cmd" ]; then
			log=$log"Image or command change, replacing all pods ..."
			echo "$log"

			[ $LOGLEVEL -ge 1 ] && echo "[$state_image] [$spec_image] [$state_cmd] [$spec_cmd]" >&2

			# Remove all the controlled pods ...
			kubectl delete pods --selector=operator=$cr --now --wait=false >/dev/null

			# Remember what the expected state will be
			state_image=$spec_image
			state_cmd=$spec_cmd

			continue  # process next event 
		fi

		state_replica=$running_pod_count

		#delta=`expr $spec_replica - $state_replica`
		delta=$(( $spec_replica - $state_replica ))

		if [ $delta -lt 0 ]
		then
			# Delete pods
			log=$log"Replica mismatch, adjusting pod count by $delta"

			todel=`echo "$running_pods" | tail $delta`
			if [ "$todel" ]
			then
				kubectl delete pods $todel --now --wait=false >/dev/null
			fi

			# write the status into the cr
			kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/replica", "value":  '$spec_replica'}]' >/dev/null
		elif [ $delta -gt 0 ]
		then
			# Start pods
			[ $delta -gt 8 ] && let delta=$(( $delta / 2 )) # This will slow down the pod creation
			log=$log"Replica mismatch, adjusting pod count by $delta"
			while [ $delta -gt 0 ]
			do
				kubectl run $cr-`make_random_str` --wait=false --restart=Never --image=$spec_image -l operator=$cr -- $spec_cmd >/dev/null
				# FIXME: Add in "metadata.ownerReferences" 
				let delta=$delta-1
			done

			# Set the state of the new pod(s)
			state_image=$spec_image
			state_cmd=$spec_cmd

			# write the status into the cr
			kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/image",   "value": "'$state_image'"}]' >/dev/null
			kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/command", "value": "'"$state_cmd"'"}]' >/dev/null

			# write the status into the cr
			kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/replica", "value":  '$spec_replica'}]' >/dev/null
		else
			log=$log"Nothing to do"
		fi

		echo "$log"
	done < $PIPE
}

# Ensure a command is always running
function run_cmd {
	while true
	do
		$@
		cmd_ret=$?
		echo "Warning ($cr): command '"$@"' exited with $cmd_ret ..." >&2
		[ $cmd_ret -gt 128 ] && echo "Warning ($cr) signal $(( $ret - 128 )) sent to run_cmd(), breaking out" >&2 && break 
	done
}

# Prepend a string (event type) before each line
function prepend {
	while read line
	do
		echo "${1}:${line}"
	done
}

# Start the controller and the event watches ... pipe events into the reconcile function
function start_controller {
	cr=$1

	# Start the controller 
	(
		# All events for this controller are passed through this named pipe
		PIPE=$tempfile.$cr.pipe
		mkfifo $PIPE
		watch_opts="--watch --no-headers --ignore-not-found"

		echo Starting watch for custom resource: $CRD_NAME/$cr
		run_cmd kubectl get myapp $cr $watch_opts | prepend myapp >> $PIPE &

		kubectl patch myapp $cr --type=json -p '[{"op": "add", "path": "/metadata/finalizers", "value": ["finalizer.stable.example.com"]}]' >/dev/null

		#run_cmd kubectl get pod --selector=operator=$cr $watch_opts | prepend pod >> $PIPE &

		echo Starting reconcile function for custom resource: $CRD_NAME/$cr
		reconcile $cr $PIPE  # the reconcile function runs until the controller ends.

		echo Terminating processes:
		[ $LOGLEVEL -ge 1 ] && jobs >&2 && jobs -p >&2

		kill `jobs -p`
		sleep 1
		kill `jobs -p` 2>/dev/null

		cleanupTempFiles $cr

		echo Exiting controller for $CRD_NAME/$cr ...
	) &
}


function main_manager {
	# This function does the following
	# - Looks for new custom resource and for each new custom resource it starts a new controller
	# - Looks for deleted custom resources and for each deleted custom resource it stops the controller (which will also stop all controlled objects) 

	local wait_time=5

	while true
	do
		cr_list=`kubectl get $CRD_NAME --no-headers --ignore-not-found | awk '{print $1}'`
		[ $LOGLEVEL -ge 1 ] && echo cr_list=$cr_list >&2

		# Check for new custom resources
		for cr in $cr_list
		do
			if [ "${cr_map[$cr]}" ]
			then
				[ $LOGLEVEL -ge 1 ] && echo Controller for $CRD_NAME/$cr already started >&2
			else
				echo Starting controller for $CRD_NAME/$cr >&2
				start_controller $cr
				cr_map[$cr]=1
				
			fi
		done

		# Check for deleted CRs
		for cr in "${!cr_map[@]}"
		do
			kubectl get $CRD_NAME $cr >/dev/null || unset cr_map[$cr]
		done

		# If no CRs exist, look more often
		[ ${#cr_map[@]} -eq 0 ] && sleep 1 || sleep $wait_time 
	done
}

declare -A cr_map

# Start
cleanupTempFiles
main_manager

echo Execution should never reach here ... quitting
exit 1


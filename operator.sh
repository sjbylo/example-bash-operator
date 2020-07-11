#!/usr/bin/env bash 
# MyApp Operator acts like a replica-set controller
# Bash version 4 or higher is needed

# Set the name of the CRD
CRD_NAME=myapp 

base=`basename $0`
tempfile=/tmp/.op.$CRD_NAME.$$

# Install gdate and gtr with brew to allow this script to work on MacOS
type gdate 2>/dev/null >&2 && DATE_CMD=gdate || DATE_CMD=date
type gtr 2>/dev/null >&2 && TR_CMD=gtr || TR_CMD=tr

[ "$LOGLEVEL" = "2" ] && set -x
[ "$LOGLEVEL" ] || LOGLEVEL=0
[ $LOGLEVEL -ge 1 ] && echo LOGLEVEL=$LOGLEVEL

INTERVAL_MS=${INTERVAL_MS-3000}     # time to wait in ms before making changes to pods in reconcile()
[ $LOGLEVEL -ge 1 ] && echo INTERVAL_MS=$INTERVAL_MS

# Clean up temp files for each custom resource  or for all
function cleanup {
	# $1 is the cr name
	if [ "$1" ]
	then
		# Custom resource deleted - clean up only the custom resource related files
		[ $LOGLEVEL -ge 1 ] && echo Deleting files: $tempfile.$1.pipe $tempfile.$1.pids >&2
		rm -f $tempfile.$1.pipe $tempfile.$1.pids
	else
		# Clean up everything
		[ $LOGLEVEL -ge 1 ] && echo Deleting files: $tempfile.* >&2
		rm -f $tempfile.*
	fi
}

function make_random_str {
	len=${1-6}
	#cat /dev/urandom | $TR_CMD -dc 'a-z0-9' | fold -w $len | head -n 1  FIXME try again with digits
	cat /dev/urandom | $TR_CMD -dc 'a-z' | fold -w $len | head -n 1
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

# Clean up everything and exit
function exit_all() {
	echo
	echo "Trap starting ..."

	echo Terminating all watch subprocesses ...
	[ $LOGLEVEL -ge 1 ] && cat $tempfile.*.pids
	kill `cat $tempfile.*.pids`  
	sleep 1
	echo Terminating all watch subprocesses ...
	kill `cat $tempfile.*.pids`  2>/dev/null >&2

	cleanup

	echo Operator $base exiting now ...
	exit 0
}

function getSpec {
	cr=$1

	spec=`kubectl get myapp $cr -o json 2>/dev/null`
	[ $? -eq 1 ] && return 1	
		
	spec_replica=`echo "$spec" | jq -r '.spec.replica'`
	spec_image=`echo "$spec"   | jq -r '.spec.image'`
	spec_cmd=`echo "$spec"     | jq -r '.spec.command'`

	return 0
}

function timeUp {
	# If still within $1 ms from the last time $before
	local interval=$1   # interval in ms
	local before=$2  

	if [ `expr $before + $interval` -gt `$DATE_CMD +%s%3N` ]
	then
		[ $LOGLEVEL -ge 1 ] && echo Timer running >&2
		return 0  # time not up
	fi
	[ $LOGLEVEL -ge 1 ] && echo Time up >&2
	return 1  # time up
}

#function getPodCount {
	#local cr=$1
#
	#running_pod_count=`kubectl get pod --selector=operator=$cr --ignore-not-found | \
		#grep -e "\bRunning\b" -e "\bPending\b" -e "\bContainerCreating\b"| \
		#wc -l | $TR_CMD -d " "`
#}

function getRunningPods {
	local cr=$1

	running_pods=`kubectl get pod --selector=operator=$cr --ignore-not-found --no-headers | \
		grep -e "\bRunning\b" -e "\bPending\b" -e "\bContainerCreating\b"| \
		awk '{print $1}'`
	running_pod_count=`echo "$running_pods" | wc -l | $TR_CMD -d " "`
}

function reconcile {
	local cr=$1
	#local PIPE=$2

	local before=`$DATE_CMD +%s%3N`
	local PIPE=$tempfile.$cr.pipe  #FIXME

	getSpec $cr  # Fetch the initial spec from the CR object

	[ ! "$spec_image" -o ! "$spec_replica" -o ! "$spec_cmd" ] && echo "WARNING: spec missing [$spec_image $spec_replica $spec_cmd]" >&2 

	# Set up the status in the CR
	kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status", "value": {}}]' >/dev/null

	#getPodCount $cr FIXME
	getRunningPods $cr

	# Simply assume any existing pods are using these as a default.  Should really check.
	state_image=busybox
	state_cmd="sleep 99999"

	# Loop through all the events from the watched objects.  
	while true
	do
		read -t1 event   # Timeout so we have a chance to make changes. 
		ret=$?
		[ $LOGLEVEL -ge 1 -a "$event" ] && echo "ret=[$ret] event=[$event]" >&2

		# If there is a read timeout and also data?
		[ $ret -eq 142 -a "$event" ] && echo FAILURE timeout and event=$event && return  # This should never happen 

		# If read not a timeout, process $event
		#if [ $ret -ne 142 ]
		if [ "$event" ]
		then
			# Each event is <event type>:<event details>   e.g.  myapp:myapp1 
			obj=`echo $event | cut -d: -f1`
			#event=`echo $line | cut -d: -f2 | $TR_CMD -s " "`

			if [ "$obj" = "myapp" ]; then
				# Retrieve the CR spec.  If CR object deleted, delete all managed objects
				if ! getSpec $cr; then
					[ $LOGLEVEL -ge 1 ] && echo "Fetching spec of $cr failed" >&2
					kubectl delete pod --selector=operator=$cr --now --wait=false >/dev/null
					return 0  # This will stop the controller 
				fi
			elif [ "$obj" = "cleanup" ]; then
				kubectl delete pod --selector=operator=$cr --now --wait=false --field-selector status.phase=Succeeded >/dev/null 
			else
				[ $LOGLEVEL -ge 1 ] && echo "WARNING: Unknown object type [$obj]" >&2
				return # This should never happen
			fi
		else
			[ $LOGLEVEL -ge 1 ] && echo "Read returned [$ret].  Event missing" >&2
		fi
		
		timeUp $INTERVAL_MS $before && continue  # If timer still running, continue and process next event
		before=`$DATE_CMD +%s%3N` 

		[ ! "$spec_image" -o ! "$spec_replica" -o ! "$spec_cmd" ] && echo "WARNING: spec missing [$spec_image $spec_replica $spec_cmd]" >&2

		# Start the log message 
		log="$cr $running_pod_count/$spec_replica running. " 

		####################################
		# Now, reconcile the state.

		# If the cr spec has changed (image or command params) restart all pods ...
		if [ "$state_image" != "$spec_image" -o "$state_cmd" != "$spec_cmd" ]; then
			log=$log"Image or command change, replacing all pods ..."
			echo "$log"

			[ $LOGLEVEL -ge 1 ] && echo "[$state_image] [$spec_image] [$state_cmd] [$spec_cmd]" >&2

			# Remove all the related pods ...
			kubectl delete pods --selector=operator=$cr --now --wait=false >/dev/null

			state_image=$spec_image
			state_cmd=$spec_cmd

			continue  # process next event 
		fi

		#getPodCount $cr FIXME 
		getRunningPods $cr 

		state_replica=$running_pod_count

		#log="$cr $running_pod_count/$spec_replica running. " 

		delta=`expr $spec_replica - $state_replica`

		if [ $delta -lt 0 ]
		then
			# Delete pods
			log=$log"Replica mismatch, adjusting pod count by $delta"

			#getRunningPods $cr 

			todel=`echo "$running_pods" | tail $delta`
			if [ "$todel" ]
			then
				kubectl delete pods $todel --now --wait=false >/dev/null
			fi
		elif [ $delta -gt 0 ]
		then
			# Start pods
			[ $delta -gt 5 ] && let delta=$(( $delta / 2)) # This will slow down the pod creation
			log=$log"Replica mismatch, adjusting pod count by $delta"
			while [ $delta -gt 0 ]
			do
				kubectl run $cr-`make_random_str` --wait=false --restart=Never --image=$spec_image -l operator=$cr -- $spec_cmd >/dev/null
				let delta=$delta-1
			done

			# Set the actual state
			state_image=$spec_image
			state_cmd=$spec_cmd
		else
			log=$log"Nothing to do"
		fi

		# write the status into the cr
		#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/image", "value": "$state_image"}]'
		#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/command", "value": "$state_cmd"}]'
		kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/replica", "value": '$state_replica'}]' >/dev/null

		echo "$log"
	done < $PIPE
}

# Ensure a command is always running
function run_cmd {
	while true
	do
		$@
		echo "Warning: command '"$@"' failed with $? ..." >&2
	done
}

# Prepend a string (event type) before each line
function prepend { while read line; do echo "${1}:${line}"; done }

# Start the event watches ... pipe events into the reconcile function
function start_controller {
	cr=$1

	# Start the controller 
	(
		# All events for this controller are passed through this named pipe
		PIPE=$tempfile.$cr.pipe
		mkfifo $PIPE
		watch_opts="--watch --no-headers --ignore-not-found"

		echo Starting watch for custom resource: $CRD_NAME/$cr
		run_cmd kubectl get myapp $cr $watch_opts | prepend myapp > $PIPE &
		save_pid $cr $!

		#sleep 0.5
		#
		#run_cmd kubectl get pod --selector=operator=$cr $watch_opts | prepend pod > $PIPE &
		#save_pid $cr $!

		echo Starting reconcile function for custom resource: $CRD_NAME/$cr
		reconcile $cr $PIPE  # wait here #FIXME

		stop_controller $cr 
		cleanup $cr
	) &
	save_pid $cr $!
}

function stop_controller {
	# $1 = custom resource
	local cr=$1

	unset cr_map[$cr]

	echo Terminating processes `get_pids $cr`
	kill `get_pids $cr`
	sleep 1

	echo Terminating processes `get_pids $cr`
	kill `get_pids $cr` 2>/dev/null
	sleep 2

	echo Killing processes `get_pids $cr`
	kill -9 `get_pids $cr` 2>/dev/null

	cleanup $cr
}

function main_manager {
	# This function does the following
	# - Looks for new custom resource and for each new custom resource it starts a new controller
	# - Looks for deleted custom resources and for each deleted custom resource it stops the controller (which will also stop all managed objects) 

	local wait_time=5

	while true
	do
		cr_list=`kubectl get $CRD_NAME --no-headers --ignore-not-found | awk '{print $1}'`

		# Check for new custom resources
		for cr in $cr_list
		do
			if [ "${cr_map[$cr]}" ]
			then
				[ $LOGLEVEL -ge 2 ] && echo Controller for $CRD_NAME/$cr already started >&2
			else
				echo Starting controller for $CRD_NAME/$cr >&2
				start_controller $cr
				cr_map[$cr]=1
				
			fi
		done

		## Check for deleted CRs
		#for cr in "${!cr_map[@]}"
		#do
			#if ! kubectl get $CRD_NAME $cr --no-headers --ignore-not-found >/dev/null   # FIXME - needed?
			#then
				#echo Stopping controller for $CRD_NAME/$cr >&2
				#sleep 5 # Give time to controller to delete it's resources
				#unset cr_map[$cr]
			#fi
		#done

		# If no CRs exist, look more often
		[ ${#cr_map[@]} -eq 0 ] && sleep 1 || sleep $wait_time 
	done
}

declare -A cr_map

# Start
cleanup
main_manager

echo Execution should never reach here ... quitting
exit 1


#!/usr/bin/env bash 
#!/usr/local/bin/bash 
# MyApp Operator

type gdate 2>/dev/null >&2 && DATE_CMD=gdate || DATE_CMD=date
type gtr 2>/dev/null >&2 && TR_CMD=gtr || TR_CMD=tr

[ "$LOGLEVEL" = "2" ] && set -x
[ "$LOGLEVEL" ] || LOGLEVEL=0

INTERVAL_MS=${INTERVAL_MS-5000}        # time to wait in ms before making changes to pods

echo LOGLEVEL=$LOGLEVEL
echo INTERVAL_MS=$INTERVAL_MS

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
		[ $LOGLEVEL -ge 1 ] && echo Deleting files: $tempfile.$1.pipe $tempfile.$1.pids >&2
		rm -f $tempfile.$1.pipe
		rm -f $tempfile.$1.pids
	else
		# Clean up everything
		[ $LOGLEVEL -ge 1 ] && echo Deleting files: $tempfile.* >&2
		rm -f $tempfile.*
	fi
}

function make_random_str {
	len=${1-6}
	#cat /dev/urandom | $TR_CMD -dc 'a-z0-9' | fold -w $len | head -n 1
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

function exit_all() {
	echo
	echo "Trap starting ..."

	echo Terminating all watch subprocesses ...
	kill `cat $tempfile.*.pids`  2>/dev/null
	sleep 1
	kill `cat $tempfile.*.pids`  2>/dev/null >&2
	sleep 1
	kill -9 `cat $tempfile.*.pids`  2>/dev/null >&2

	cleanup

	echo Operator $base exiting now ...
	exit 0
}

function getSpec {
	cr=$1

	spec=`kubectl get myapp $cr -o json`
	if [ $? -eq 1 ]
	then
		return 1
	fi	
		
	spec_replica=`echo "$spec" | jq -r '.spec.replica'`
	spec_image=`echo "$spec"   | jq -r '.spec.image'`
	spec_cmd=`echo "$spec"     | jq -r '.spec.command'`

	return 0
}

function timeUp {
	# If still within $1 ms from the last time?
	local interval=$1   # interval in ms
	local before=$2  

	#if [ $before -gt `expr $now - $interval` ]
	if [ `expr $before + $interval` -gt `$DATE_CMD +%s%3N` ]
	then
		[ $LOGLEVEL -ge 1 ] && echo Timer running >&2
		return 0  # time not up
	fi
	[ $LOGLEVEL -ge 1 ] && echo Time up >&2
	return 1  # time up
}

# Set the global running pod state map
declare -A state_pods

function getRunningPods {
	local cr=$1

	running_pods=`kubectl get pod --selector=operator=$cr --ignore-not-found | \
		grep -e "\bRunning\b" -e "\bPending\b" -e "\bContainerCreating\b"| \
		awk '{print $1}'`
	###running_pods_cnt=`echo "$running_pods" | wc -l` # needed?

	# refresh the running pod state map
	for i in ${!state_pods[@]}; do   # empty the map
		unset state_pods[$i]
	done
	for i in $running_pods; do	# fill the map with actual state
		state_pods[$i]=1
	done
}

function reconcile {
	local cr=$1

	local before=`$DATE_CMD +%s%3N`
	local PIPE=$tempfile.$cr.pipe

	getRunningPods $cr
	[ $LOGLEVEL -ge 1 ] && echo "Debug: state_pods=[${!state_pods[@]}]" >&2

	getSpec $cr  # Fetch the initial spec from the CR object

	[ ! "$spec_image" -o ! "$spec_replica" -o ! "$spec_cmd" ] && echo "WARNING: spec missing [$spec_image $spec_replica $spec_cmd]" >&2 

	kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status", "value": {}}]' >/dev/null

	local counter=0

	state_image=busybox
	state_cmd="sleep 99999999"

	# Loop through all the events from the watched objects.  Suppress events if they come too fast (within 3 seconds)
	while true
	do
		read -t1 line   # Cheeck at least every 1s if timer is up
		ret=$?

		[ $LOGLEVEL -ge 1 ] && echo "ret=[$ret]" >&2

		obj=`echo $line | cut -d: -f1`
		event=`echo $line | cut -d: -f2 | $TR_CMD -s " "`

		[ $LOGLEVEL -ge 1 ] && echo "line=[$line] event=[$event]" >&2

		[ $ret -eq 142 -a "$line" ] && echo FAILURE timeout and line=$line && return

		# If read not a timeout 
		if [ $ret -ne 142 ]
		then
			if [ "$obj" = "pod" ]; then
				# Remember the state of the pod
				pod_name=`echo $event | awk '{print $1}'`
				pod_state=`echo $event | awk '{print $3}'`
				[ $LOGLEVEL -ge 1 ] && echo "Debug: pod_state=[$pod_state]" >&2
				[ $LOGLEVEL -ge 1 ] && echo "Debug: pod_name=[$pod_name]" >&2
				[ $LOGLEVEL -ge 1 ] && echo "Debug: state_pods=[${!state_pods[@]}]" >&2
				if echo $pod_state | grep -x -q -e "Running" -e "Pending" -e "ContainerCreating"; then
					state_pods["$pod_name"]=1
				else
					if [ "$pod_state" = "Terminating" -o "$pod_state" = "Completed" ]
					then
						unset state_pods["$pod_name"]
						#( sleep 5; echo "cleanup:no event" >> $PIPE ) &   # FIXME
					fi
				fi
				[ $LOGLEVEL -ge 1 ] && echo "Debug: state_pods=[${!state_pods[@]}]" >&2
			elif [ "$obj" = "myapp" ]; then
				# Retrieve the CR spec.  If CR object deleted, delete all managed objects
				if ! getSpec $cr; then
					kubectl delete pod --selector=operator=$cr --now --wait=false >/dev/null
					return 0
				fi
			elif [ "$obj" = "cleanup" ]; then
				kubectl delete pod --selector=operator=$cr --now --wait=false --field-selector status.phase=Succeeded >/dev/null 
			else
				[ $LOGLEVEL -ge 1 ] && echo "WARNING: Unknown object type [$obj]" >&2
				return 
			fi
			let event_cnt=$event_cnt+1
		else
			[ $LOGLEVEL -ge 1 ] && echo "Read returned [$ret]" >&2
		fi
		
		timeUp $INTERVAL_MS $before && continue  # If timer still running, continue and process next event
		before=`$DATE_CMD +%s%3N` 

		[ ! "$spec_image" -o ! "$spec_replica" -o ! "$spec_cmd" ] && echo "WARNING: spec missing [$spec_image $spec_replica $spec_cmd]" >&2

		log="$cr `printf "%2s\n" $event_cnt` events. ${#state_pods[@]}/$spec_replica running. " 
		event_cnt=0

		#log=$log"[$obj] [$event] "

		####################################
		# Now, reconcile the state.

		# If the spec has changed (image or command) restart all pods ...
		if [ "$state_image" != "$spec_image" -o "$state_cmd" != "$spec_cmd" ]; then
			log=$log"Image or command change, replacing all pods ..."
			echo "$log"

			[ $LOGLEVEL -ge 1 ] && echo "Replacing all pods ..." >&2
			[ $LOGLEVEL -ge 1 ] && echo "state_image=[$state_image] spec_image=[$spec_image]" >&2
			[ $LOGLEVEL -ge 1 ] && echo "state_cmd=[$state_cmd] spec_cmd=[$spec_cmd]" >&2
			[ $LOGLEVEL -ge 1 ] && echo "state_pods=[${!state_pods[@]}]" >&2

			# Remove all the related pods ...
			kubectl delete pods --selector=operator=$cr --now --wait=false >/dev/null

			# Clear the running pod map
			if [ ${#state_pods[@]} -gt 0 ]; then
				for i in ${!state_pods[@]}
				do
					unset state_pods[$i]
				done
			fi

			state_image=$spec_image
			state_cmd=$spec_cmd

			continue  # process next event 
		fi

		# Every x-th time, refresh running pods state and reset the map?
		# FIXME [ $counter -gt 4 ] && getRunningPods $cr && counter=0

		state_replica=${#state_pods[@]}

		delta=`expr $spec_replica - $state_replica`

		if [ $delta -lt 0 ]
		then
			# Delete pods
			log=$log"Replica mismatch, adjusting pod count by $delta"

			getRunningPods $cr && counter=0

			todel=`echo "$running_pods" | tail $delta`
			if [ "$todel" ]
			then
				kubectl delete pods $todel --now --wait=false >/dev/null
			fi
		elif [ $delta -gt 0 ]
		then
			# Start pods
			log=$log"Replica mismatch, adjusting pod count by $delta"
			while [ $delta -gt 0 ]
			do
				kubectl run $cr-`make_random_str` --wait=false --restart=Never --image=$spec_image -l operator=$cr -- $spec_cmd >/dev/null
				let delta=$delta-1
			done

			# Set the state
			state_image=$spec_image
			state_cmd=$spec_cmd
		else
			log=$log"Nothing to do"
		fi

		# write the status into the cr
		#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/image", "value": "$state_image"}]'
		#kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/command", "value": "$state_cmd"}]'
		kubectl patch myapp $cr --type=json -p '[{"op": "replace", "path": "/status/replica", "value": '$state_replica'}]' >/dev/null

		let counter=$counter+1

		echo "$log"
	done < $PIPE
}

function run_cmd {
	while true
	do
		$@
		echo "Command '"$@"' failed with $? ..."
	done
}

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

		run_cmd kubectl get myapp $cr $watch_opts | prepend myapp > $PIPE &
		save_pid $cr $!

		sleep 0.5

		run_cmd kubectl get pod --selector=operator=$cr $watch_opts | prepend pod > $PIPE &
		save_pid $cr $!

		echo Starting reconcile function for custom resource: $CRD_NAME/$cr
		reconcile $cr   # wait here

		stop_controller $cr 
		cleanup $cr
	) &
	save_pid $cr $!
}

function stop_controller {
	# $1 = custom resource
	local cr=$1
	#echo Stopping processes: `get_pids $cr`

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
				[ $LOGLEVEL -ge 2 ] && echo Controller for $CRD_NAME/$cr already started >&2
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
				sleep 5 # Give time to controller to delete it's resources
				unset cr_map[$cr]
			fi
		done

		[ ${#cr_map[@]} -ne 0 ] && sleep $wait_time || sleep 1
	done
}

# Start
cleanup
main_manager

echo Execution should never reach here ... quitting
exit 1




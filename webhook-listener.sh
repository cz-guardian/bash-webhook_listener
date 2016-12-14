#!/bin/bash
#
# Author: Jaroslav Stepanek
# Email: jaroslav.stepanek@theguardian.cz
# Date: Wed 14 Dec 2016
# Purpose: Custom daemon script for listening to webhook calls

#
# Static vars
#
TCPPORT="12345"
PIDFILE="/var/tmp/webhook-listener.pid"
# If no locking is necessary then comment out
LOCKFILE="/var/tmp/webhook-listener.lock"
LOGFILE="/var/tmp/webhook-listener.log"

#
# Global vars
# 
LISTENER_COMMAND="nc -l ${TCPPORT}"
# String on which the executeCommands() will be run
LISTENER_REGEX='^POST'

####
# Functions
####
#
# Wrapper for logging messages
#
function log()
{
	echo "$(date) "$* >> "${LOGFILE}"
}

#
# Create the execution lock
#
function lock()
{
	if [ "${LOCKFILE}" ]; then
		touch "${LOCKFILE}"
	fi 
}

#
# Remove the execution lock
#
function unlock()
{
	if [ "${LOCKFILE}" ]; then
		rm -f "${LOCKFILE}"
	fi
}

#
# After receiving the hook, execute the following commands
#
function executeCommands()
{
	if [ "${LOCKFILE}" ] && [ -f "${LOCKFILE}" ]; then
		log "Locked, no execution allowed"
	else
		lock
		### Place your commands here ###
		log "ZZZ"
		################################
		unlock
	fi
}

#
# Maintain the NetCat reading and if the data matches the pattern call execute
#
function startListener()
{
	trap onExit SIGHUP SIGINT SIGTERM

	eval "${LISTENER_COMMAND}" | while read line 
	do
		if [ "$(echo $line | grep "${LISTENER_REGEX}")" ]; then
			executeCommands "${line}"
		fi
	done
}

#
# Main wrapper that takes care of running the NetCat listener
#
function listen()
{
	local mPid=0

	# Setup trap for kill
	trap onExit SIGHUP SIGINT SIGTERM

	while [ 1 ]; do
		# Start NetCat in background
		startListener >/dev/null &
		mPid=$!

		# Wait for NetCat process to finish
		wait ${mPid}
		sleep 1
	done
}

#
# onExit hook that makes sure everything is closed properly
#
function onExit()
{
	local ncPid=$(ps -eo pid,cmd | awk "\$0~/${LISTENER_COMMAND}/&&\$0!~/awk/{print \$1}")
	kill ${ncPid} &>/dev/null
	exit 0
}

#
# Start hook
#
function start()
{
	local mPid=0

	status &>/dev/null
		if [ $? -gt 1 ]; then
		echo "Process already running"
		exit 0
	fi

	# Unlock the execution lock
	unlock

	# Start the listening process
	listen &>/dev/null &
	mPid=$!
	disown ${mPid}

	# Write down the PID
	echo ${mPid} > ${PIDFILE}
}

#
# Stop hook
#
function stop()
{
	local mPid=$(cat ${PIDFILE})

	if [ "${mPid}" ]; then 
		kill ${mPid} \
			&& rm -f ${PIDFILE} 
	fi

	# Unlock the execution lock
	unlock
}

#
# Status hook
#
function status()
{
	local mPid=$(cat ${PIDFILE} 2>/dev/null)

	if [ "${mPid}" ]; then 
		ps -p ${mPid} &>/dev/null

		if [ $? -eq 0 ]; then
			echo "Process is running with pid ${mPid}"
			return 1
		else
			echo "Process is not running but the PID file still exists!"
			return 0
		fi
	else
		echo "Process is stopped"
		return 0
	fi
}

#
# Main
#
function main() 
{
	local arg="${1}"
	
	case "${arg}" in
		start)
			start
			exit 0
		;;
		stop)
			stop
			exit 0
		;;
		status)
			status
			exit 0
		;;
		restart)
			stop
			sleep 1
			start
			exit 0
		;;
		*)
			echo "Usage"
			exit 0
		;;
	esac
}

# Call main and pass the arguments
main $*

# Clean exit if this point is reached
exit 0
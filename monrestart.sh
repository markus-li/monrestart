#!/bin/bash

# monrestart v0.1
# http://kloudberry.co.uk/
#
# Copyright (c) 2013 Markus Liljergren
# Licensed under the MIT license.
# https://raw.github.com/markus-li/monrestart/master/LICENSE

# Requirements:
# * bash
# * bc
# * egrep
# * awk

# Usage:
#
# Set the configuration in the config file and run this script manually or from cron.
# 

# KNOWN 'BUGS':
# If a pid file exists and contains the WRONG PID, this will NOT be detected.
# 
CONFIGFILE='monrestart.conf'
# If the file contains something 
if egrep -q -v '^#|^[^ ]*=[^[[:space:]]]?[^;]*|^[[:space:]]*$' "$CONFIGFILE"; then
  echo "Config file is unclean, you should probably clean it! These lines are unclean:" >&2
  egrep -n -v '^#|^[^ ]*=[^[[:space:]]]?[^;]*|^[[:space:]]*$' "$CONFIGFILE"
  echo
  echo "Running anyway..."
fi
echo "Reading config..."
source "$CONFIGFILE"

echo "Checking processes/services..."
while read -r line
do
  cur_service=`expr "$line" : '^\([^#]*\)_active.*'`
  if [[ -n "${cur_service}" ]]; then
    echo "------------------------"
    echo "Checking '$cur_service'..."
    active="${cur_service}_active"
    procname="${cur_service}_procname"
    pidfile="${cur_service}_pidfile"
    start="${cur_service}_start"
    stop="${cur_service}_stop"
    kill_wait="${cur_service}_kill_wait"
    maxcpu="${cur_service}_maxcpu"
    maxcpu_wait="${cur_service}_maxcpu_wait"
    if [[ -n "${!active}" ]] && ${!active}; then
      echo "${cur_service} IS monitored!"
      # If we have a pid-file, use that:
      if [[ -n "${!pidfile}" ]] && [ -f "${!pidfile}" ]; then
        echo "Using PID-file: ${!pidfile}"
        pid=`cat "${!pidfile}" 2>/dev/null`
      else
        echo "No PID-file specified and/or found! Using procname '${!procname}'..."
        pid=`ps fax | grep -v "grep " | grep -m 1 "${!procname}" | grep -o '^[ ]*[0-9]*'`
      fi
      if [[ -n "${pid}" ]]; then
        echo "Monitoring PID: ${pid}"
      else
        echo "No PID found!"
      fi
      # 'kill -0' DOES NOT kill a process! It just checks if it is there and 
      # can accept signals.
      if kill -0 $pid > /dev/null 2>&1; then
        echo "${cur_service} is running."
        # We could do further checks here, or just not do anything more...
        
        # This will block for the number of seconds set in maxcpu_wait, it would
        # probably be better to fork before doing this...
        cpu_usage=`ps -p $pid -o pid,%cpu | grep $pid | awk {'print $2*100'}`
        if [ ${cpu_usage} -gt 0 ]; then 
          cpu_usage_percent=`"scale=2; ${cpu_usage} / 100" | bc`
        else
          cpu_usage_percent='0'
        fi
        if [[ -n "${!maxcpu}" ]] && [ ${cpu_usage} -ge $((${!maxcpu} * 100)) ]; then
          echo "CPU usage is currently above ${!maxcpu}%!"
          if [[ -n "${!maxcpu_wait}" ]]; then
            echo "Sleeping for: ${!maxcpu_wait}"
            sleep "${!maxcpu_wait}"
          fi
          if [[ -n "${!maxcpu}" ]] && [ ${cpu_usage} -ge $((${!maxcpu} * 100)) ]; then
            echo "After having waited ${!maxcpu_wait}, the CPU is still high, restarting ${cur_service}."
            if [[ -n "${!stop}" ]]; then
              echo "Using this stop-command: '${!stop}'"
              ${!stop}
            else
              echo "No stop-command specified, running this:"
              echo "kill ${pid}"
              kill ${pid}
            fi
            numsec=0
            if kill -0 $pid > /dev/null 2>&1; then
              echo "Waiting for up to ${!kill_wait} seconds for ${cur_service} to terminate properly."
              while [ "$numsec" -lt "${!kill_wait}" ]; do
                sleep 1
                let numsec=numsec+1
                if kill -0 $pid > /dev/null 2>&1; then
                  if [ ${numsec} -eq ${!kill_wait} ]; then
                    echo "${cur_service} did not terminate properly, sending SIGKILL!" >&2
                    kill -9 $pid
                    sleep 1
                    break
                  fi
                else
                  # The process has quit, we're done here...
                  echo "${cur_service} has terminated properly."
                  break
                fi
              done
            fi
            
            if kill -0 $pid > /dev/null 2>&1; then
              echo "Couldn\'t restart ${cur_service}!" >&2
            else
              rm -f ${!pidfile}
              echo "Starting ${cur_service} again..."
            fi
            ${!start}
          fi
        else
          
          echo "CPU usage is ${cpu_usage_percent}%, which currently either not monitored or below specified threshold."
        fi
      else
        echo "${cur_service} is NOT running!"
        # We should now start the process/service
        echo "Starting ${cur_service}..."
        rm -f ${!pidfile}
        ${!start}
      fi
      
    else
      echo "${cur_service} is NOT monitored!"
    fi
    
  fi
done < "$CONFIGFILE"
echo "------------------------"
echo "Done checking processes/services!"
#!/bin/bash

# This script monitors incoming and outgoing traffic on your server

# Set the default values for the arguments
interface=eth0
interval=1

# Parse the command-line arguments
while [[ $# -gt 0 ]]
do
  case $1 in
    -i|--interface)
      interface=$2
      shift
      shift
      ;;
    -t|--interval)
      interval=$2
      shift
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Set the log file location
log_file=/var/log/traffic_monitor.log

# Display the banner with your name and version
echo "OVHGERMANY Traffic Monitor - Version 0.8b"

while true
do
  # Get the current date and time
  date_time=$(date "+%Y-%m-%d %H:%M:%S")

  # Get the incoming and outgoing traffic in bytes
  incoming=$(cat /sys/class/net/$interface/statistics/rx_bytes)
  outgoing=$(cat /sys/class/net/$interface/statistics/tx_bytes)

  # Convert the incoming and outgoing traffic to megabytes or gigabytes
  if [[ $incoming -ge 1000000000 ]]; then
    incoming=$(awk "BEGIN {print $incoming/1000000000}")
    incoming_unit="GB"
  elif [[ $incoming -ge 1000000 ]]; then
    incoming=$(awk "BEGIN {print $incoming/1000000}")
    incoming_unit="MB"
  fi
  if [[ $outgoing -ge 1000000000 ]]; then
    outgoing=$(awk "BEGIN {print $outgoing/1000000000}")
    outgoing_unit="GB"
  elif [[ $outgoing -ge 1000000 ]]; then
    outgoing=$(awk "BEGIN {print $outgoing/1000000}")
    outgoing_unit="MB"
  fi

  # Clear the output and display the incoming and outgoing traffic
  clear
  echo "OVHGERMANY Traffic Monitor - Version 0.8b"
  if [[ "$incoming_unit" == "GB" ]] || [[ "$outgoing_unit" == "GB" ]]; then
    echo -e "\033[31mUnderattack Or Downloading Something\033[0m"
  fi
  echo "Incoming: $incoming $incoming_unit"
  echo "Outgoing: $outgoing $outgoing_unit"
  
  # Write the date, time, incoming traffic, and outgoing traffic to the log file
  echo "$date_time $incoming $incoming_unit $outgoing $outgoing_unit" >> $log_file

  # Sleep for the specified interval
  sleep $interval
done

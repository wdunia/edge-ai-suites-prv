#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <DLSPS_NODE_IP>:<DLSPS_PORT>"
  exit 1
fi

# Assign the argument to a variable
URL=$1

# Execute curl requests using the URL variable
function get_status() {

  interval=10
  start_time=$(date +%s)

  status=$(curl -s --location -X GET "http://$URL/pipelines/status" | grep state | awk ' { print $2 } ' | tr -d \")
  if [[ "$status" != *"RUNNING"* ]]; then
      running=false
      echo -e "\nNo running pipelines"
      exit 0
  else
    running=true
    echo -e "\n>>>>>Pipeline status reported every $interval seconds."
    echo -e "\n>>>>>Press Ctrl+C to exit..."

    while [ "$running" == true ]; do
      status=$(curl -s --location -X GET "http://$URL/pipelines/status" | grep state | awk ' { print $2 } ' | tr -d \")
      if [[ "$status" != *"RUNNING"* ]]; then
        running=false
      else
      results_pipeline=()
      elapsed_time=$(($(date +%s) - $start_time))
      echo -e "\n>>>>>>>>>>>>>>> $elapsed_time seconds."
      results=$(curl -s --location -X GET "http://$URL/pipelines/status" | grep -A 2 -B 5 RUNNING | grep fps | awk -F': ' '{print $2}' | awk -F',' '{printf" %.2f ", $1}')
      results_pipeline+=("$results")
      echo -e "pipelines fps: (${results_pipeline[@]})"
      sleep $interval

      fi
    done
  fi

}
# Function to handle exit
cleanup() {
    echo -e "\n>>>>>Ctrl+C pressed, terminating the script..."
    exit 0
}

# Set trap to catch SIGINT (Ctrl+C) and call cleanup
trap cleanup SIGINT

get_status

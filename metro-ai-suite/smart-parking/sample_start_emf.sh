#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <DLSPS_NODE_IP>:<DLSPS_PORT> [cpu|gpu]"
  exit 1
fi

# Assign the argument to a variable
URL=$1

# Default device
device="CPU"

# Check for optional device parameter
if [ -n "$2" ]; then
  if [ "$2" == "gpu" ]; then
    device="GPU"
  elif [ "$2" == "cpu" ]; then
    device="CPU"
  else
    echo "Invalid device option. Use 'cpu' or 'gpu'."
    exit 1
  fi
fi

# Execute curl requests using the URL variable
function run_sample() {
  pipelines=$1
  device=$2
  interval=10
  if [ $device == "GPU" ]; then
    pipeline_name="yolov10_1_gpu"
  else
    pipeline_name="yolov10_1_cpu"
  fi
  pipeline_list=()
  echo
  echo -n ">>>>>Initialization..."
  for x in $(seq 1 $pipelines); do
    payload=$(cat <<EOF
   {
    "source": {
        "uri": "file:///home/pipeline-server/videos/new_video_$x.mp4",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "host": "mqtt-broker:1883",
            "topic": "object_detection_$x",
            "timeout": 1000
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "object_detection_$x"
        }
    },
    "parameters": {
        "detection-device": "$device",
        "classification-device": "$device"
    }
  }
EOF
)
    response=$(curl  -s "http://$URL/pipelines/user_defined_pipelines/${pipeline_name}" -X POST -H "Content-Type: application/json" -d "$payload")
    if [ $? -ne 0 ]; then
      echo -e "\nError: curl command failed. Check the deployment status."
      return 1
    fi
    pipeline_list+=("$response")
  done
  running=false
  while [ "$running" != true ]; do
    status=$(curl -s --location -X GET "http://$URL/pipelines/status" | grep state | awk ' { print $2 } ' | tr -d \")
    if [[ "$status" == *"QUEUED"* ]]; then
      running=false
      echo -n "."
      sleep 1
    else
      running=true
      echo -n "Pipelines initialized."
      echo
    fi
  done
}

function stop_all_pipelines() {
  echo
  echo -n ">>>>>Stopping all running pipelines."
  status=$(curl -s -X GET "http://$URL/pipelines/status" -H "accept: application/json")
  if [ $? -ne 0 ]; then
    echo -e "\nError: curl command failed. Check the deployment status."
    return 1
  fi
  pipelines=$(echo $status  | grep -o '"id": "[^"]*"' | awk ' { print $2 } ' | tr -d \"  | paste -sd ',' - )
  IFS=','
  for pipeline in $pipelines; do
    response=$(curl -s --location -X DELETE "http://$URL/pipelines/${pipeline}")
  done
  unset IFS
  running=true
  while [ "$running" == true ]; do
    echo -n "."
    status=$(curl -s --location -X GET "http://$URL/pipelines/status" | grep state | awk ' { print $2 } ' | tr -d \")
    if [[ "$status" == *"RUNNING"* ]]; then
      running=true
      sleep 2
     else
      running=false
     fi
  done
  echo -n " done."
  echo
  return 0
}

stop_all_pipelines

if [ $? -ne 0 ]; then
   exit 1
fi

echo -e "\n>>>>>$device device selected."
run_sample 4 $device
if [ $? -ne 0 ]; then
  exit 1
fi

#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <DLSPS_NODE_IP>:<DLSPS_PORT>"
  exit 1
fi

# Assign the argument to a variable
URL=$1

# Execute curl requests using the URL variable
curl "http://$URL/pipelines/user_defined_pipelines/object_tracking_1" -X POST -H 'Content-Type: application/json' -d '
{
    "source": {
        "uri": "file:///home/pipeline-server/videos/VIRAT_S_000101.mp4",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "host": "mqtt-broker:1883",
            "topic": "object_tracking_1",
            "timeout": 1000
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "object_tracking_1"
        }
    },
    "parameters": {
        "detection-device": "CPU"
    }
}'

curl "http://$URL/pipelines/user_defined_pipelines/object_tracking_2" -X POST -H 'Content-Type: application/json' -d '
{
    "source": {
        "uri": "file:///home/pipeline-server/videos/VIRAT_S_000102.mp4",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "host": "mqtt-broker:1883",
            "topic": "object_tracking_2",
            "timeout": 1000
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "object_tracking_2"
        }
    },
    "parameters": {
        "detection-device": "CPU"
    }
}'

curl "http://$URL/pipelines/user_defined_pipelines/object_tracking_3" -X POST -H 'Content-Type: application/json' -d '
{
    "source": {
        "uri": "file:///home/pipeline-server/videos/VIRAT_S_000103.mp4",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "host": "mqtt-broker:1883",
            "topic": "object_tracking_3",
            "timeout": 1000
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "object_tracking_3"
        }
    },
    "parameters": {
        "detection-device": "CPU"
    }
}'

curl "http://$URL/pipelines/user_defined_pipelines/object_tracking_4" -X POST -H 'Content-Type: application/json' -d '
{
    "source": {
        "uri": "file:///home/pipeline-server/videos/VIRAT_S_000104.mp4",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "mqtt",
            "host": "mqtt-broker:1883",
            "topic": "object_tracking_4",
            "timeout": 1000
        },
        "frame": {
            "type": "webrtc",
            "peer-id": "object_tracking_4"
        }
    },
    "parameters": {
        "detection-device": "CPU"
    }
}'

#!/bin/bash

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f1",
    "prompt": "You are a traffic monitor viewing an intersection from above. Is any car driving south-east? If yes, answer: South-east detected. If no, answer: No south-east movement.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Intersection-aerial",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f2",
    "prompt": "You are a security guard. Infer if an incident is occurring. Describe and give brief reason with less than 20 words.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Destroyed-city",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f3",
    "prompt": "You are a traffic monitor viewing an intersection. Is there a bicycle or cyclist visible? If yes, answer: Bicycle detected. If no, answer: No bicycle visible.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Intersection-cyclist",
    "frameRate": 1,
    "chunkSize": 2
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f4",
    "prompt": "You are viewing a dashcam feed from a moving car. Is there a traffic accident visible? If yes, answer: Accident detected. If no, answer: No accident visible.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Dashcam-accident",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

python3 camera-rtsp.py ./videos1

exit

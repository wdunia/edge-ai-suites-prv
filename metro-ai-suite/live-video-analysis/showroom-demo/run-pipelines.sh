#!/bin/bash

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f3",
    "prompt": "Is there a car accident visible? Describe in less than 15 words.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Dashcam-accident1",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 15

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f4",
    "prompt": "Is there a car accident visible? Describe in less than 15 words.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Dashcam-accident2",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 15

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f2",
    "prompt": "Is there a cyclist and where is it? Describe in less than 15 words.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Intersection-cyclist",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 15

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f1",
    "prompt": "Create a headline for a TV news story that describes what happened and draws on random elements of the scene to convey a sense of hope.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 30,
    "pipelineName": "GenAI_Pipeline_on_CPU",
    "runName": "News-headline",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

python3 camera-rtsp.py ./videos

exit

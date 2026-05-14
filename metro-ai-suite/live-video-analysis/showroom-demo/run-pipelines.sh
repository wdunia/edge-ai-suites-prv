#!/bin/bash

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f1",
    "prompt": "Is there a bicycle or motorcycle moving? If yes, answer: Two-wheeler in motion. If no, answer: No two-wheeler moving.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 15,
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
    "rtspUrl": "rtsp://host.docker.internal:8555/f2",
    "prompt": "Is there a traffic accident visible? If yes, answer: Accident detected. If no, answer: No accident visible.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Dashcam-accident",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f3",
    "prompt": "Is there any dangerous situation in a pedestrian tunnel? If yes, answer: Yes. Danger detected. If no, answer: No danger detected.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Monitored-tunnel",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f4",
    "prompt": "Infer if a crime is in action. Describe and give reason in less than 15 words.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Monitored-public-space",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

python3 camera-rtsp.py ./videos

exit

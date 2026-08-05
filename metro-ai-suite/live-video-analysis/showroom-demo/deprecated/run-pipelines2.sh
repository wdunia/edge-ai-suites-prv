#!/bin/bash

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f1",
    "prompt": "You are a safety monitor watching a train station platform. Is anything dangerous happening? If yes, answer: Danger detected. If no, answer: No danger detected.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 15,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Station-platform",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f2",
    "prompt": "You are a security monitor watching a pedestrian tunnel. Is there any dangerous situation? If yes, answer: Danger detected. If no, answer: No danger detected.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 15,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Pedestrian-tunnel",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f3",
    "prompt": "You are a fire safety monitor watching a computer room. Is there any fire hazard visible? If yes, answer: Fire hazard detected. If no, answer: No fire hazard.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 15,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Computer-room-fire",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 5

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f4",
    "prompt": "You are a safety monitor watching a car repair workshop. Is there any danger visible? If yes, answer: Danger detected. If no, answer: No danger detected.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 15,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Workshop-safety",
    "frameRate": 1,
    "chunkSize": 1
  }' \
  http://localhost:4173/api/generate_captions_alerts

python3 camera-rtsp.py ./videos2

exit

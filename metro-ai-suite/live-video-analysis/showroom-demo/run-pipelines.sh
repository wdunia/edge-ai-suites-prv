#!/bin/bash

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f1",
    "prompt": "You are a traffic monitor viewing an intersection. Is there a bicycle or motorcycle moving? If yes, answer: Two-wheeler in motion. If no, answer: No two-wheeler moving.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 10,
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
    "prompt": "You are viewing a dashcam feed from a moving car. Is there a traffic accident visible? If yes, answer: Accident detected. If no, answer: No accident visible.",
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
    "prompt": "You are a security guard watching a pedestrian tunnel. Is there any dangerous situation? If yes, answer: Yes. Danger detected. If no, answer: No danger detected. Describe and give reason in less than 10 words.",
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
    "prompt": "You are given 2 images, Infer if a crime is in action. Describe and give reason in less than 15 words.",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Monitored-public-space",
    "frameRate": 1,
    "chunkSize": 2
  }' \
  http://localhost:4173/api/generate_captions_alerts

python3 camera-rtsp.py ./videos

exit

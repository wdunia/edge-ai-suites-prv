#!/bin/bash

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f1",
    "prompt": "You are a security guard with 2 images. Infer if an incident is occuring. Describe and give brief reason with less than 20 words",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Video1",
    "frameRate": 1,
    "chunkSize": 2
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 10

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f2",
    "prompt": "You are a security guard with 2 images. Infer if an incident is occuring. Describe and give brief reason with less than 20 words",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Video2",
    "frameRate": 1,
    "chunkSize": 2
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 10

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f3",
    "prompt": "You are a security guard with 2 images. Infer if an incident is occuring. Describe with less than 20 words",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Video3",
    "frameRate": 1,
    "chunkSize": 2
  }' \
  http://localhost:4173/api/generate_captions_alerts

sleep 10

curl --noproxy localhost -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rtspUrl": "rtsp://host.docker.internal:8555/f4",
    "prompt": "You  are given 2 images, Infer if a crime is in action. Describe and give reason in  less than 10 words",
    "modelName": "InternVL2-1B",
    "maxNewTokens": 20,
    "pipelineName": "GenAI_Pipeline_on_GPU",
    "runName": "Video4",
    "frameRate": 1,
    "chunkSize": 2
  }' \
  http://localhost:4173/api/generate_captions_alerts

exit

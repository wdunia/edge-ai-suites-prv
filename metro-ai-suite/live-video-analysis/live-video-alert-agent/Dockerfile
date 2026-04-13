# Copyright (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

FROM python:3.12-slim AS builder
WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# Build stage: compile Tailwind CSS and fetch Chart.js via npm
FROM node:22-slim AS frontend
WORKDIR /ui
COPY src/ui/tailwind.config.js src/ui/tailwind.css src/ui/index.html ./
COPY src/ui/static/js/app.js ./static/js/app.js
RUN npm install --save-dev tailwindcss@3 chart.js@4.4.9 && \
    npx tailwindcss -i tailwind.css -o static/css/tailwind.css --minify && \
    cp node_modules/chart.js/dist/chart.umd.min.js static/js/chart.umd.min.js

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m appuser

WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --chown=appuser:appuser src/ ./src/
# Overwrite vendor assets with freshly built/fetched versions
COPY --from=frontend --chown=appuser:appuser /ui/static/ ./src/ui/static/

USER appuser
EXPOSE 9000
CMD ["python", "src/main.py"]

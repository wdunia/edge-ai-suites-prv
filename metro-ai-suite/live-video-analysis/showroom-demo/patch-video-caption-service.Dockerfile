# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Verification-only image for the KV-cache eviction defect.
#
# The released video-caption-service configures the OpenVINO GenAI continuous-batching
# scheduler with use_cache_eviction=true next to enable_prefix_caching=true. Once the KV
# cache fills up, eviction double-frees blocks and runs die after 30-60 minutes with
# "BlockAllocator leaked blocks" followed by "check 'm_ref_count > 0' failed".
#
# This applies the proposed one-token change on top of the released image, so the fix can
# be validated without rebuilding the service from source: no apt, no uv, no CDN download,
# and therefore no proxy dependency on the showroom host.
#
# Build (from this directory):
#   docker build -t video-caption-service:kv-eviction-fix -f patch-video-caption-service.Dockerfile .
#
# Use, in captioning-demo.env:
#   REGISTRY=
#   TAG=kv-eviction-fix
#
# Revert by restoring REGISTRY=intel/ and TAG=latest; that image is also the negative
# control, because it still carries use_cache_eviction=true.

ARG BASE_IMAGE=intel/video-caption-service:latest
FROM ${BASE_IMAGE}

# grep first so the build fails loudly if the released image no longer contains the
# expected string, instead of producing a silently unpatched image.
USER root
RUN grep -c 'use_cache_eviction=true' /app/backend/services/pipeline_server.py \
    && sed -i 's/use_cache_eviction=true/use_cache_eviction=false/' /app/backend/services/pipeline_server.py \
    && grep -n 'SCHEDULER_CONFIG' /app/backend/services/pipeline_server.py
USER appuser

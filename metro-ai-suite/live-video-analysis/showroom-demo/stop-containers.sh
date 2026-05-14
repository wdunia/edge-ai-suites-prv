#!/bin/bash
# Stops and removes all Docker containers. Use with caution.

docker rm -f $(docker ps -aq)
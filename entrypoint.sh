#!/bin/bash

echo "Starting API server..."

# Activate the virtual environment
source /workspace/venv/bin/activate

# Start the API server
/workspace/venv/bin/python /workspace/Hunyuan3D-2.1/api_server.py

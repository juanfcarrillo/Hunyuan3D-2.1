# Custom Hunyuan3D-2.1 Docker Image
# Multi-stage build to cache Python dependencies
# Stage 1: Base image with system dependencies
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS base

LABEL name="hunyuan3d21-custom" maintainer="hunyuan3d21-custom"

# Create workspace folder and set it as working directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Update package lists and install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    vim \
    libegl1-mesa-dev \
    libglib2.0-0 \
    unzip \
    git-lfs \
    pkg-config \
    libglvnd0 \
    libgl1 \
    libglx0 \
    libegl1 \
    libgles2 \
    libglvnd-dev \
    libgl1-mesa-dev \
    libegl1-mesa-dev \
    libgles2-mesa-dev \
    cmake \
    curl \
    mesa-utils-extra \
    libxrender1 \
    libeigen3-dev \
    python3-dev \
    python3-setuptools \
    libcgal-dev \
    libxi6 \
    libgconf-2-4 \
    libxkbcommon-x11-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH
ENV PYOPENGL_PLATFORM=egl

# Set CUDA environment variables
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0"

# Install Python 3.11 and pip
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    python3-pip \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.11 as default python3
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Create virtual environment
RUN python3 -m venv /workspace/venv
ENV PATH="/workspace/venv/bin:${PATH}"

# Upgrade pip and install basic tools
RUN pip install --upgrade pip setuptools wheel ninja

# Stage 2: Dependencies stage - cache Python packages
FROM base AS dependencies

# Copy requirements file first for better caching
COPY requirements.txt /tmp/requirements.txt

# Install PyTorch and related packages
RUN pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu124

# Install Python dependencies from requirements.txt
RUN pip install -r /tmp/requirements.txt || pip install -r /tmp/requirements.txt --ignore-errors

# Install bpy separately if it fails
RUN pip install bpy || echo "Warning: bpy installation failed, continuing without it"

# Stage 3: Build stage - compile custom components
FROM dependencies AS build

# Set working directory
WORKDIR /workspace/Hunyuan3D-2.1

# Copy source code for building custom components
COPY hy3dpaint/custom_rasterizer ./hy3dpaint/custom_rasterizer
COPY hy3dpaint/DifferentiableRenderer ./hy3dpaint/DifferentiableRenderer

# Install custom_rasterizer with proper environment variables and flags
RUN cd ./hy3dpaint/custom_rasterizer && \
    python setup.py install

# Install DifferentiableRenderer
RUN cd ./hy3dpaint/DifferentiableRenderer && \
    bash compile_mesh_painter.sh

# Stage 4: Final runtime image
FROM dependencies AS runtime

# Copy compiled components from build stage
COPY --from=build /workspace/venv /workspace/venv

# Copy the entire project to the container
COPY . /workspace/Hunyuan3D-2.1/

# Set working directory to the copied project
WORKDIR /workspace/Hunyuan3D-2.1

# Create ckpt folder in hy3dpaint and download RealESRGAN model
RUN cd /workspace/Hunyuan3D-2.1/hy3dpaint && \
    mkdir -p ckpt && \
    wget https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P ckpt

# Apply configuration fixes for path references
RUN cd /workspace/Hunyuan3D-2.1/hy3dpaint && \
    sed -i 's/self\.multiview_cfg_path = "cfgs\/hunyuan-paint-pbr\.yaml"/self.multiview_cfg_path = "hy3dpaint\/cfgs\/hunyuan-paint-pbr.yaml"/' textureGenPipeline.py

RUN cd /workspace/Hunyuan3D-2.1/hy3dpaint/utils && \
    sed -i 's/custom_pipeline = config\.custom_pipeline/custom_pipeline = os.path.join(os.path.dirname(__file__),"..","hunyuanpaintpbr")/' multiview_utils.py

# Set global library paths to ensure proper linking at runtime
ENV LD_LIBRARY_PATH="/workspace/venv/lib:${LD_LIBRARY_PATH}"

# No need to activate conda environment anymore since we're using venv

# Create gradio cache directory
RUN mkdir -p gradio_cache

# Expose port 7860 for the API server
EXPOSE 7860
EXPOSE 8081

# Cleanup
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set default command to run the API server from within the virtual environment
CMD ["/workspace/venv/bin/python", "api_server.py"]

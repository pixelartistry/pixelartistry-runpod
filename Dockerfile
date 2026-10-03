# syntax=docker/dockerfile:1
# PixelArtistry · Trellis2 & Pixal3D — ComfyUI image for RunPod
#
# Baked into the image (all open licences): Ubuntu 24.04, Python 3.12, PyTorch 2.8 (CUDA 12.8),
# xformers, flash-attn, ComfyUI with the native Trellis2 + Pixal3D nodes, and every Python package
# visualbruno's ComfyUI-Trellis2 needs.
#
# NOT in the image, fetched by each pod at start (see start.sh):
#   - visualbruno/ComfyUI-Trellis2 itself and prebuilt CUDA wheels (cu128 + torch 2.8, cp312, from
#     PozzettiAndrea/cuda-wheels; nvdiffrast/nvdiffrec are NVIDIA non-commercial licence), meshlib (own licence)
#   - all model weights (downloaded once into the /workspace volume)
#   - the paid PA_ workflows (buyers drag them in)

FROM ubuntu:24.04

# Must match requirements.lock — after changing it, run ./lock.sh
ARG COMFYUI_REF=v0.38.2
ARG PYTHON_VERSION=3.12

ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PYTHONUNBUFFERED=1 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_LINK_MODE=copy \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PA_WHEEL_TAG=cu128torch2.8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git curl ca-certificates build-essential openssh-server \
      libgl1 libopengl0 libglib2.0-0 libgomp1 libsm6 libxext6 libxrender1 libegl1 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.12.22 /uv /uvx /usr/local/bin/

RUN uv venv --python "${PYTHON_VERSION}" --seed /opt/venv

RUN git clone --depth 1 --branch "${COMFYUI_REF}" https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI

COPY requirements.lock /opt/pa/requirements.lock
RUN uv pip install --no-cache --compile-bytecode -r /opt/pa/requirements.lock \
 && python -c "import torch, torchvision, xformers; print('torch', torch.__version__, '· CUDA', torch.version.cuda)"

# flash-attn: prebuilt wheel (BSD-3) from PozzettiAndrea/cuda-wheels, built for exactly this torch + CUDA.
# Compiled for sm80/90/100/120, so it runs on A100, RTX 3090/4090, L40S, H100, B200 and RTX 5090.
RUN uv pip install --no-cache --no-deps --extra-index-url https://pozzettiandrea.github.io/cuda-wheels/ \
      --index-strategy unsafe-best-match "flash-attn==2.8.3+${PA_WHEEL_TAG}" \
 && python -c "import flash_attn; print('flash_attn', flash_attn.__version__)"

# Smoke test: ComfyUI imports and registers its nodes (CPU only, exits immediately), then clean up
RUN cd /opt/ComfyUI \
 && python main.py --cpu --quick-test-for-ci \
 && rm -rf /opt/ComfyUI/user /opt/ComfyUI/output /opt/ComfyUI/temp /opt/ComfyUI/input

COPY start.sh /opt/pa/start.sh
RUN chmod +x /opt/pa/start.sh

LABEL org.opencontainers.image.source="https://github.com/pixelartistry/pixelartistry-runpod" \
      org.opencontainers.image.title="PixelArtistry · Trellis2 & Pixal3D (ComfyUI)" \
      org.opencontainers.image.description="ComfyUI with native Trellis2 + Pixal3D and visualbruno's nodes, for RunPod"

EXPOSE 8188 8080 22
WORKDIR /opt/ComfyUI
CMD ["/opt/pa/start.sh"]

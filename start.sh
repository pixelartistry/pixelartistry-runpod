#!/usr/bin/env bash
# PixelArtistry · Trellis2 & Pixal3D on RunPod — runs every time the pod starts.
# ComfyUI, Python and PyTorch are already in the image. This script only:
#   1/5 checks the GPU   2/5 prepares /workspace   3/5 fetches visualbruno's nodes
#   4/5 downloads the models you picked (first start only)   5/5 starts ComfyUI
# Everything you make or download lives in /workspace, so it survives Stop/Start.
# Help: https://discord.com/invite/peVv6nzKrS
set -Eeuo pipefail

# ---------- settings (override any of these with RunPod environment variables) ----------
WS="${WORKSPACE:-/workspace}"
MODELS="${MODELS:-int8 bf16 multiview vb}"                               # int8 | bf16 | multiview | vb
TRELLIS2_REF="${TRELLIS2_REF:-b0e84c0f29857a444e8bcb5b9be2ea218e96efd0}" # visualbruno/ComfyUI-Trellis2 @ 2026-09-25 ("main" = always newest, untested)
MESHLIB_VERSION="${MESHLIB_VERSION:-3.1.4.297}"
WHEELS_SUBDIR="${PA_WHEELS_SUBDIR:-Torch2110}"                           # set in the image; matches its PyTorch
COMFY_PORT="${COMFY_PORT:-8188}"
FILES_PORT="${FILES_PORT:-8080}"
COMFYUI_ARGS="${COMFYUI_ARGS:-}"

COMFY=/opt/ComfyUI
PY=/opt/venv/bin/python
PA="$WS/.pixelartistry"
T2="$PA/ComfyUI-Trellis2"
M="$WS/models"
WF="$WS/user/default/workflows"
export HF_HOME="$WS/.cache/huggingface" HF_XET_HIGH_PERFORMANCE=1
export UV_CACHE_DIR="$WS/.cache/uv" UV_LINK_MODE=copy

log()  { printf '\n\033[1;33m[PixelArtistry]\033[0m %s\n' "$*"; }
has()  { [[ " $MODELS " == *" $1 "* ]]; }
stop() { log "$*"; log "Help: https://discord.com/invite/peVv6nzKrS"; sleep infinity; }
trap 'stop "Setup stopped at start.sh line $LINENO. Scroll up for the error, then restart the pod."' ERR

# ---------- 1/5 GPU ----------
log "1/5 GPU check"
command -v nvidia-smi >/dev/null 2>&1 || stop "No NVIDIA GPU found. Deploy this template on a GPU pod."
GPU="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -1)"
DRV="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
log "GPU: $GPU · driver $DRV"
if (( ${DRV%%.*} < 580 )); then
  stop "Driver $DRV is too old: this image uses CUDA 13 and needs driver 580+. Terminate this pod and redeploy with Filter -> CUDA version 13.0."
fi

# SSH: RunPod passes PUBLIC_KEY when you've added an SSH key in your account settings
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  mkdir -p ~/.ssh /run/sshd && chmod 700 ~/.ssh
  echo "$PUBLIC_KEY" > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  ssh-keygen -A >/dev/null 2>&1 && /usr/sbin/sshd
fi

# ---------- 2/5 folders in the volume ----------
log "2/5 Workspace: $WS"
mkdir -p "$M" "$WS/input" "$WS/output" "$WF/visualbruno" "$WF/PixelArtistry" "$PA" "$HF_HOME" "$UV_CACHE_DIR"

# ---------- 3/5 visualbruno/ComfyUI-Trellis2 (fetched from GitHub, kept in the volume) ----------
log "3/5 ComfyUI-Trellis2 @ ${TRELLIS2_REF:0:12}"
git config --global --add safe.directory "$T2"
[[ -d "$T2/.git" ]] || git clone -q https://github.com/visualbruno/ComfyUI-Trellis2.git "$T2"
if [[ ! "$TRELLIS2_REF" =~ ^[0-9a-f]{40}$ || "$(git -C "$T2" rev-parse HEAD)" != "$TRELLIS2_REF" ]]; then
  git -C "$T2" fetch -q --tags origin
  git -C "$T2" checkout -q -f --detach "origin/$TRELLIS2_REF" 2>/dev/null || git -C "$T2" checkout -q -f --detach "$TRELLIS2_REF"
fi

# flash_attn has no wheel for Torch 2.11 + CUDA 13, so new LoadModel nodes default to sdpa + xformers
"$PY" - "$T2/nodes.py" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'("backend": \(\[[^\]]*\],\{"default":)"flash_attn"', r'\1"sdpa"', s, count=1)
s = re.sub(r'("sparse_backend": \(\[[^\]]*\],\{"default":)"flash_attn"', r'\1"xformers"', s, count=1)
open(p, "w").write(s)
PY
ln -sfn "$T2" "$COMFY/custom_nodes/ComfyUI-Trellis2"

# Prebuilt CUDA wheels from the repo + meshlib. The container disk resets on every Stop,
# so this runs each start; with the cache in /workspace it takes a few seconds.
ls "$T2/wheels/Linux/$WHEELS_SUBDIR/"*.whl >/dev/null 2>&1 \
  || stop "This ComfyUI-Trellis2 version has no wheels/Linux/$WHEELS_SUBDIR folder. Remove the TRELLIS2_REF variable to go back to the tested version."
uv pip install -q --python "$PY" --no-deps "$T2/wheels/Linux/$WHEELS_SUBDIR/"*.whl \
  "meshlib==$MESHLIB_VERSION" "meshlib-core==$MESHLIB_VERSION"
"$PY" -c "import torch, xformers, cumesh, o_voxel, flex_gemm, nvdiffrast.torch, meshlib.mrmeshpy, pymeshlab; print('torch', torch.__version__, '· CUDA', torch.version.cuda, '· GPU ok' if torch.cuda.is_available() else '· GPU NOT VISIBLE')"

# ---------- 4/5 models (first start only; existing files are skipped) ----------
log "4/5 Models: $MODELS"
get() { # repo path-in-repo  -> $M/path-in-repo
  [[ -s "$M/$2" ]] && return 0
  echo "   downloading $2"
  "$PY" - "$1" "$2" "$M" <<'PY'
import sys
from huggingface_hub import hf_hub_download
repo, filename, root = sys.argv[1:]
hf_hub_download(repo_id=repo, filename=filename, local_dir=root)
PY
}
get Comfy-Org/Pixal3D   clip_vision/dino_v3_L_naf_fp32.safetensors
get Comfy-Org/Pixal3D   vae/trellis_2_shape_vae_bf16.safetensors
get Comfy-Org/Pixal3D   vae/trellis_2_texture_vae_bf16.safetensors
get Comfy-Org/MoGe      geometry_estimation/moge_2_vitl_normal_fp16.safetensors
get Comfy-Org/BiRefNet  background_removal/birefnet.safetensors
if has int8; then
  get Comfy-Org/Pixal3D   diffusion_models/pixal3d_int8_convrot.safetensors
  get Comfy-Org/TRELLIS.2 diffusion_models/trellis_2_int8_convrot.safetensors
  if has multiview; then get Comfy-Org/Pixal3D diffusion_models/pixal3d_multiview_int8_convrot.safetensors; fi
fi
if has bf16; then
  get Comfy-Org/Pixal3D   diffusion_models/pixal3d_bf16.safetensors
  get Comfy-Org/TRELLIS.2 diffusion_models/trellis_2_bf16.safetensors
  if has multiview; then get Comfy-Org/Pixal3D diffusion_models/pixal3d_multiview_bf16.safetensors; fi
fi
if has vb && [[ ! -f "$M/microsoft/TRELLIS.2-4B/.pa_complete" ]]; then   # visualbruno's nodes; DINOv3 follows on first run
  echo "   downloading microsoft/TRELLIS.2-4B"
  "$PY" -c "from huggingface_hub import snapshot_download as s; s('microsoft/TRELLIS.2-4B', local_dir='$M/microsoft/TRELLIS.2-4B')"
  touch "$M/microsoft/TRELLIS.2-4B/.pa_complete"
fi
du -sh "$M" 2>/dev/null | sed 's/^/   models on disk: /' || true

# ---------- 5/5 example workflows, download page, ComfyUI ----------
"$PY" - "$T2/example_workflows" "$WF/visualbruno" <<'PY'
import json, os, sys, glob
src, dst = sys.argv[1], sys.argv[2]
def fix(o):  # every Trellis2LoadModel, including ones inside subgraphs
    if isinstance(o, dict):
        if o.get("type") == "Trellis2LoadModel":
            w = o.get("widgets_values")
            if isinstance(w, list) and len(w) > 6:
                if w[1] in ("flash_attn", "flash_attn_3"): w[1] = "sdpa"
                if w[6] == "flash_attn": w[6] = "xformers"
            named = o.get("widgets_values_named")
            if isinstance(named, dict):
                if named.get("backend") in ("flash_attn", "flash_attn_3"): named["backend"] = "sdpa"
                if named.get("sparse_backend") == "flash_attn": named["sparse_backend"] = "xformers"
        for v in o.values(): fix(v)
    elif isinstance(o, list):
        for v in o: fix(v)
for f in glob.glob(os.path.join(src, "*.json")):
    out = os.path.join(dst, os.path.basename(f))
    if os.path.exists(out):
        continue  # never overwrite the user's edits
    d = json.load(open(f))
    fix(d)
    json.dump(d, open(out, "w"), indent=1)
PY

# Download page: every file in /workspace/output (GLBs, textures, renders), one click each
nohup "$PY" -m http.server "$FILES_PORT" --bind 0.0.0.0 --directory "$WS/output" >/dev/null 2>&1 &

log "5/5 Starting ComfyUI"
log "Open it from RunPod: Connect -> HTTP Service [Port $COMFY_PORT]. Your files: HTTP Service [Port $FILES_PORT]."
log "PixelArtistry workflows: drag the PA_*.json files onto the canvas, then Ctrl+S to keep them in the Workflows sidebar."
cd "$COMFY"
# shellcheck disable=SC2086
exec "$PY" main.py --listen 0.0.0.0 --port "$COMFY_PORT" \
  --models-directory "$M" --user-directory "$WS/user" \
  --input-directory "$WS/input" --output-directory "$WS/output" \
  $COMFYUI_ARGS

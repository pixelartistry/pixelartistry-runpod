# PixelArtistry · Trellis2 & Pixal3D on RunPod

ComfyUI with the native **Trellis2** and **Pixal3D** nodes plus [visualbruno's ComfyUI-Trellis2](https://github.com/visualbruno/ComfyUI-Trellis2), ready to run on a RunPod GPU. Made for people without an NVIDIA card, or on a Mac.

**Deploy:** use the PixelArtistry template on RunPod and set **Filter → CUDA version 12.8** (or newer). First start downloads the models into your volume. After that, restarts take about a minute.

- ComfyUI: **Connect → HTTP 8188**
- Your files (GLBs, textures): **Connect → HTTP 8080**

Image: `ghcr.io/pixelartistry/trellis2-pixal3d` · Python 3.12 · PyTorch 2.8 (CUDA 12.8) · NVIDIA driver 570+

Each pod fetches visualbruno's nodes, their prebuilt wheels and meshlib from their original sources at start. Some of those carry non-commercial licences (NVIDIA nvdiffrast/nvdiffrec, MeshLib), so check them before commercial use.

Tutorials and workflows: [youtube.com/@PixelArtistry_](https://www.youtube.com/@PixelArtistry_) · [pixel-artistry.com](https://pixel-artistry.com)

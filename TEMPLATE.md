# RunPod template — PixelArtistry · Trellis2 & Pixal3D

**In the image:** ComfyUI v0.38.2 (native Trellis2 + Pixal3D nodes) · Python 3.12 · PyTorch 2.8 (CUDA 12.8) · xformers · every package visualbruno's nodes need. Built by GitHub Actions, hosted free on GitHub's registry.

**Fetched by each pod at start:** visualbruno/ComfyUI-Trellis2 (pinned to `b0e84c0`, 25 Sep 2026, still the newest commit) with its prebuilt wheels and 23 example workflows, plus meshlib. **Downloaded once into the volume:** the models.

**Not included:** the PA_ workflows. The image is public, so anyone could pull files out of it. Buyers drag their PA_ files in.

---

## 1. Put this folder on GitHub (5 min)

Create a **public** repo `pixelartistry/pixelartistry-runpod` and push this whole folder, including the hidden `.github` folder. In Claude Code: *"push this folder to a new public repo pixelartistry/pixelartistry-runpod"*.

## 2. Build the image (20–30 min, runs by itself)

```
git tag v1.0.0
git push origin v1.0.0
```

The **Actions** tab shows the build. When it's green, the image is at `ghcr.io/pixelartistry/trellis2-pixal3d:v1.0.0`.

**First time only:** github.com/pixelartistry → **Packages** → `trellis2-pixal3d` → **Package settings** → **Change visibility** → **Public**. New packages start private, and RunPod can't pull a private image.

## 3. Create the template (3 min)

console.runpod.io → **Templates** → **New Template**

| Field | Value |
|---|---|
| Name | `PixelArtistry · Trellis2 & Pixal3D (ComfyUI)` |
| Type / Compute | Pod · NVIDIA GPU |
| Container Image | `ghcr.io/pixelartistry/trellis2-pixal3d:v1.0.0` |
| Container Start Command | *(leave empty)* |
| Container Disk | 30 GB |
| Volume Disk | 100 GB |
| Volume Mount Path | `/workspace` |
| Expose HTTP Ports | `8188,8080` (ComfyUI, download page) |
| Expose TCP Ports | `22` |
| Visibility | Public |

Environment variables:

| Key | Value | Why |
|---|---|---|
| `MODELS` | `int8 bf16 multiview vb` | Which models to download. See the table below; drop `bf16` to save ~21 GB if you don't need Full Precision |
| `HF_TOKEN` | *(leave empty)* | Optional, only speeds up Hugging Face downloads |

Leave `TRELLIS2_REF` out. The tested commit is built into `start.sh`.

| `MODELS` keyword | Downloads |
|---|---|
| *(always)* | DINOv3 encoder, shape + texture VAEs, MoGe, BiRefNet |
| `int8` | Pixal3D int8 (5.6 GB) + Trellis2 int8 (5.3 GB) |
| `bf16` | Pixal3D bf16 (11 GB) + Trellis2 bf16 (10.3 GB) |
| `multiview` | Pixal3D multiview in the precisions above (int8 5.6 GB, bf16 11 GB) |
| `vb` | microsoft/TRELLIS.2-4B for visualbruno's nodes (DINOv3 follows on first run) |

Save, then copy the template's share link. That link goes into Chapter 16 of the guide.

## 4. Test pod

- RTX 4090 or RTX 5090, Community Cloud.
- **Filter → CUDA version: 12.8 or newer.** The image needs NVIDIA driver 570+. On an older host the log says so and stops.
- Watch **Logs**: steps 1/5 to 5/5, ending with ComfyUI's "To see the GUI go to". Note the total time of the first start for the guide.

Check these four things:

1. Step 3 prints `torch 2.8.0+cu128 · CUDA 12.8 · GPU ok`.
2. **Connect → HTTP 8188**: drag in one PA_ preset (e.g. the 6 GB Pixal3D one) and run it.
3. Run one example from the *visualbruno* folder in the Workflows sidebar.
4. **Connect → HTTP 8080**: the GLB from step 2 is there and downloads.

Then **Stop** and **Start** the pod once. The restart should take about a minute, with no model downloads.

If anything fails, paste me the log from the first red line down.

---

## Updating later

1. Change `COMFYUI_REF` in `Dockerfile` and/or the `TRELLIS2_REF` default in `start.sh`.
2. Run `bash lock.sh` (needs uv). It rebuilds `requirements.lock` from both repos.
3. Commit, then `git tag v1.0.1 && git push origin v1.0.1`.
4. Test a pod on `:v1.0.1`. If it works, edit the template's Container Image to `:v1.0.1`.

The template always points at a fixed version tag, so buyers only get builds you've tested. Existing pods keep their models; only the software changes.

## Why visualbruno's nodes aren't baked in

Two of the prebuilt wheels in his repo, nvdiffrast and nvdiffrec, are under NVIDIA's non-commercial licence, and meshlib has its own licence. If they're baked in, your public image is redistributing them. Instead, each pod downloads them from visualbruno's GitHub and PyPI at start, the same way the earlier start-script version worked. So the image itself only contains openly licensed software.

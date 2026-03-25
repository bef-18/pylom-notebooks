# pyLOM Docker Image — Build, Push, Pull & Run on Brev

## Overview

The `pylom-notebooks` image is a self-contained JupyterLab environment for the pyLOM NN tutorial notebooks. It bundles:

- NVIDIA CUDA 12.6 + cuDNN runtime
- PyTorch 2.x (cu126 wheel — compatible with driver ≤ 12.7)
- CuPy 13.3.0 (pinned — CuPy 14.x requires driver ≥ 12.8)
- pyLOM 3.2.7 from source, with all bug-fix patches applied
- JupyterLab (no token, no password)
- TensorBoard
- `CYLINDER.h5` dataset (~418 MB) baked in at `/data/CYLINDER.h5`
- All four tutorial notebooks pre-loaded in `/workspace/`

**Docker Hub image:** `bef18/pylom-notebooks:latest`
**GitHub repo:** <https://github.com/bef-18/pylom-notebooks>

---

## Quick start on a new Brev machine (VM mode)

Run this single command after SSH-ing in — it clones the notebooks, pulls the image and starts the container:

```bash
curl -fsSL https://raw.githubusercontent.com/bef-18/pylom-notebooks/main/start.sh | bash
```

Then open `~/Tutorials/pyLOM/` in Cursor. The kernel auto-connects to the container at `http://localhost:8889`.

---

## Repository layout

```
bef-18/pylom-notebooks  (GitHub)
├── Dockerfile                  # full image definition
├── docker-compose.yml          # local build + run
├── docker-compose.deploy.yml   # deploy-only (pulls from Docker Hub)
├── entrypoint.sh               # symlinks /data/CYLINDER.h5 → /workspace/, starts JupyterLab
├── start.sh                    # one-command setup for new machines
├── .vscode/settings.json       # auto-connects Cursor to http://localhost:8889
├── .dockerignore
├── example_POD_cylinder.ipynb
├── example_SHRED.ipynb
├── example_VAE_cylinder.ipynb
└── example_GAVI_R_cylinder.ipynb
```

---

## Key build decisions

### Why `nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04` as base?
The NVIDIA driver on the host reported `CUDA Version: 12.7`. PyTorch's default pip wheel ships with CUDA 13.0, which requires driver ≥ 12.8 and fails silently with `CUDA available: False`. The cu126 PyTorch wheel is the last one ABI-compatible with driver 12.7.

### Why CuPy 13.3.0?
CuPy 14.x was built against CUDA 12.9, which caused `CUDA_ERROR_INVALID_IMAGE` on systems with driver 12.7. Version 13.3.0 targets CUDA 12.x safely.

### Why `USE_MKL=OFF`?
The upstream `options.cfg` has `USE_MKL=ON`, which requires Intel MKL headers (`mkl.h`). MKL is not present in the CUDA Ubuntu base image. The Dockerfile patches `options.cfg` to `USE_MKL=OFF` and installs `libopenblas-dev` + `liblapack-dev` as the BLAS/LAPACK backend instead.

### Why `USE_COMPILED=OFF`?
pyLOM's optional compiled Cython/C modules require a full Fortran/C toolchain. Setting `USE_COMPILED=OFF` uses the pure-Python fallback, sufficient for the NN notebooks and much simpler to build.

### Bug-fix patches applied during build
The Dockerfile applies four `sed` patches to the cloned pyLOM source before installing:

| File | Fix |
|------|-----|
| `pyLOM/utils/plots.py` | VTK version tuple `(9,)` → `(9,2,2)` (pyvista ≥ 0.43 requires 3-tuple) |
| `pyLOM/NN/GAVI/__init__.py` | Add `from . import wrapper, utils` before `del wrapper, utils` (NameError) |
| `pyLOM/NN/__init__.py` | Add `from . import utils` before `del os, torch, utils` (NameError) |
| `pyLOM/NN/utils.py` | Conditional `clone().detach()` vs `torch.tensor()` based on input type (AttributeError) |

### Port 8889 instead of 8888
Brev machines run their own JupyterLab on port 8888. The container maps to **8889** to avoid the conflict.

### Notebooks mounted from host, not from image
The image has notebooks baked into `/workspace/`, but in practice the host directory `~/Tutorials/pyLOM/` is mounted over `/workspace/`. This lets Cursor edit notebooks directly from the host filesystem. The tradeoff is that the host directory must not be empty when the container starts — `start.sh` handles this by cloning the repo first.

---

## Building the image

```bash
cd ~/Tutorials/pyLOM

# Build (≈20–30 min first time; subsequent builds reuse cached layers)
docker compose build

# Force full rebuild (use after patching the Dockerfile):
docker compose build --no-cache
```

---

## Pushing to Docker Hub

Brev machines configure a **pull-through cache proxy** in Docker's systemd service that blocks push (POST) requests. Remove it before pushing, restore it afterwards.

```bash
# 1. Back up and remove the proxy
sudo cp /etc/systemd/system/docker.service.d/http-proxy.conf \
        /etc/systemd/system/docker.service.d/http-proxy.conf.bak
sudo rm /etc/systemd/system/docker.service.d/http-proxy.conf
sudo systemctl daemon-reload && sudo systemctl restart docker

# 2. Log in to Docker Hub
#    Use an access token (not password): hub.docker.com → Account Settings → Security
docker login --username bef18

# 3. Tag and push
docker tag pylom-notebooks:latest bef18/pylom-notebooks:latest
docker push bef18/pylom-notebooks:latest

# 4. Restore the proxy
sudo cp /etc/systemd/system/docker.service.d/http-proxy.conf.bak \
        /etc/systemd/system/docker.service.d/http-proxy.conf
sudo systemctl daemon-reload && sudo systemctl restart docker
```

> **Why the proxy blocks pushes:** Brev sets `HTTP_PROXY` and `HTTPS_PROXY` in
> `/etc/systemd/system/docker.service.d/http-proxy.conf`. The cache proxy handles
> GET (pulls) but returns `POST method is not allowed` for push operations.
> Removing the conf file and restarting Docker clears the env vars for the daemon.

---

## Setting up a new Brev machine (VM mode)

### Recommended: use start.sh

```bash
curl -fsSL https://raw.githubusercontent.com/bef-18/pylom-notebooks/main/start.sh | bash
```

This script:
1. Clones (or updates) `bef-18/pylom-notebooks` into `~/Tutorials/pyLOM/`
2. Writes `.vscode/settings.json` so Cursor auto-connects to `http://localhost:8889`
3. Pulls `bef18/pylom-notebooks:latest` from Docker Hub
4. Stops and removes any existing `pylom_notebooks` container
5. Starts the container on port 8889 with `~/Tutorials/pyLOM/` mounted as `/workspace/`
6. Waits until JupyterLab is responding before exiting

### Manual equivalent

```bash
# Clone notebooks
git clone https://github.com/bef-18/pylom-notebooks ~/Tutorials/pyLOM

# Pull image
docker pull bef18/pylom-notebooks:latest

# Start container
docker run -d --gpus all -p 8889:8888 \
  --name pylom_notebooks \
  -v ~/Tutorials/pyLOM:/workspace \
  bef18/pylom-notebooks:latest
```

> **Gotcha — root-owned files:** The container runs as root. If it creates files
> in the mounted `/workspace/` (e.g. `CYLINDER.h5` symlink), they will be owned
> by root on the host and cannot be removed with `rm`. Use `sudo rm -rf` instead.

---

## Connecting Cursor to the container

The `.vscode/settings.json` in the repo sets the Jupyter server automatically.
If you need to set it manually:

1. Open any `.ipynb` notebook in Cursor
2. Click the kernel selector (top-right)
3. **"Select Another Kernel..." → "Existing Jupyter Server..."**
4. Enter: `http://localhost:8889`
5. Select **Python 3**

To verify you are running inside the container (not the host Python):

```python
import sys, torch, pyLOM
print(sys.executable)           # /usr/local/bin/python  ← correct (container)
print("PyTorch:", torch.__version__)
print("CUDA:", torch.cuda.is_available())
print("pyLOM:", pyLOM.__version__)
```

If `sys.executable` shows `/home/ubuntu/.venv/...` you are on the host kernel — reconnect to `http://localhost:8889`.

---

## Brev Container Mode (alternative to VM mode)

When creating a Brev instance with **Container Mode**:

1. Select **Container Mode → Custom Container**
2. Image: `bef18/pylom-notebooks:latest`
3. Port: `8888` (Brev Container Mode handles port mapping differently — no conflict)
4. **"Configure JupyterLab" → No** (the container runs its own)
5. Deploy

Brev will pull and run the image automatically via `supervisord`. JupyterLab will
be accessible at the URL shown in the Brev console. Verify with:

```bash
curl -s http://localhost:8888/api | python3 -m json.tool | grep version
```

> **Note:** In Container Mode, Brev manages the container lifecycle via systemd
> (`brev_container.service`). Do not run `docker run` manually — Brev has already
> started the container.

---

## Useful management commands

```bash
# Check the container is running
docker ps

# View JupyterLab logs
docker logs pylom_notebooks

# Open a shell inside the running container
docker exec -it pylom_notebooks bash

# Stop / start / remove
docker stop pylom_notebooks
docker start pylom_notebooks
docker rm   pylom_notebooks

# Verify GPU and key packages inside the container
docker exec pylom_notebooks python -c "
import torch, cupy, pyLOM
print('PyTorch :', torch.__version__, '| CUDA:', torch.cuda.is_available())
print('CuPy    :', cupy.__version__)
print('pyLOM   :', pyLOM.__version__)
print('GPU     :', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')
"

# Check image size
docker images bef18/pylom-notebooks:latest
```

---

## Transferring the image without Docker Hub

```bash
# Export on source machine
docker save bef18/pylom-notebooks:latest | gzip > pylom-notebooks.tar.gz

# Copy to target machine
scp pylom-notebooks.tar.gz user@target-machine:~/

# Import and run on target machine
docker load < pylom-notebooks.tar.gz
bash <(curl -fsSL https://raw.githubusercontent.com/bef-18/pylom-notebooks/main/start.sh)
```

---

## Updating the image after changes

```bash
# 1. Edit Dockerfile / notebooks as needed
# 2. Rebuild (--no-cache only if Dockerfile changed; omit for notebook-only changes)
cd ~/Tutorials/pyLOM
docker compose build

# 3. Push (remove proxy first — see Push section)
docker tag pylom-notebooks:latest bef18/pylom-notebooks:latest
docker push bef18/pylom-notebooks:latest

# 4. On any other machine: re-run start.sh to pull the new version
curl -fsSL https://raw.githubusercontent.com/bef-18/pylom-notebooks/main/start.sh | bash
```

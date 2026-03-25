# =============================================================================
# pyLOM NN tutorial notebooks — self-contained Docker image
#
# Everything needed to run the notebooks is baked in:
#   - pyLOM source (patched) cloned from GitHub
#   - PyTorch cu126, CuPy 13.3.0, JupyterLab and all other dependencies
#   - CYLINDER.h5 dataset downloaded from Hugging Face (~418 MB)
#   - All four tutorial notebooks
#
# The image is fully portable: build once, save/load on any machine.
#
# Base: nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04
#   → compatible with NVIDIA driver >= 525 (reports CUDA ≤ 12.7)
#   → PyTorch cu126 wheel is the last build within that range
#   → CuPy 13.3.0 targets CUDA 12.x without requiring driver 12.8+
#
# ── Build ─────────────────────────────────────────────────────────────────────
#   docker compose build          (recommended — uses docker-compose.yml)
#   docker build -t pylom-notebooks .
#
# ── Transfer to another machine ───────────────────────────────────────────────
#   docker save pylom-notebooks:latest | gzip > pylom-notebooks.tar.gz
#   # copy the tarball + docker-compose.yml to the target machine, then:
#   docker load < pylom-notebooks.tar.gz
#   docker compose up
#
# ── Run directly ──────────────────────────────────────────────────────────────
#   docker run --gpus all -p 8888:8888 pylom-notebooks:latest
# =============================================================================

FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04

# ── Labels ───────────────────────────────────────────────────────────────────
LABEL maintainer="pyLOM tutorial image" \
      description="Self-contained JupyterLab environment for pyLOM NN notebooks" \
      cuda="12.6" \
      torch_wheel="cu126" \
      cupy="13.3.0"

# ── Build arguments ──────────────────────────────────────────────────────────
ARG PYLOM_COMMIT=5a8fcc4f72e4483e70f776cf5c3ef906075e9048
ARG DATA_URL=https://huggingface.co/datasets/bef-18/pyLOM_examples/resolve/main/CYLINDER.h5
ARG DEBIAN_FRONTEND=noninteractive

# ── 1. System packages ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 \
        python3.10-dev \
        python3-pip \
        git \
        wget \
        curl \
        build-essential \
        gfortran \
        libopenmpi-dev \
        openmpi-bin \
        libhdf5-dev \
        pkg-config \
        libgl1-mesa-glx \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1

# ── 2. Upgrade pip / build tools ─────────────────────────────────────────────
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel

# ── 3. Clone pyLOM at the exact tested commit ─────────────────────────────────
WORKDIR /opt
RUN git clone https://github.com/ArnauMiro/pyLowOrder.git \
 && cd pyLowOrder \
 && git checkout ${PYLOM_COMMIT}

# ── 4. Apply bug-fix patches ──────────────────────────────────────────────────
# 4a. plots.py — VTK version comparison tuple: (9,) → (9,2,2)
RUN sed -i \
    "s/pv.vtk_version_info < (9,)/pv.vtk_version_info < (9,2,2)/g" \
    /opt/pyLowOrder/pyLOM/utils/plots.py

# 4b. NN/GAVI/__init__.py — explicit module import before `del`
RUN sed -i \
    "/^from \.wrapper import vae_R/i from . import wrapper, utils" \
    /opt/pyLowOrder/pyLOM/NN/GAVI/__init__.py

# 4c. NN/__init__.py — explicit utils import before `del os, torch, utils`
RUN sed -i \
    "/^del os, torch, utils/i from . import utils" \
    /opt/pyLowOrder/pyLOM/NN/__init__.py

# 4d. NN/utils.py — handle numpy array input in Dataset._process_variables_out
RUN sed -i \
    "s/variable = variable\.clone()\.detach() #torch\.tensor(variable)/variable = variable.clone().detach() if isinstance(variable, torch.Tensor) else torch.tensor(variable)/" \
    /opt/pyLowOrder/pyLOM/NN/utils.py

# ── 5. Install pyLOM dependencies ─────────────────────────────────────────────
WORKDIR /opt/pyLowOrder
RUN pip install --no-cache-dir -r requirements.txt

# ── 6. Install pyLOM (editable, USE_COMPILED=OFF — pure Python) ───────────────
RUN pip install --no-cache-dir -e .

# ── 7. PyTorch — CUDA 12.6 wheel ─────────────────────────────────────────────
# Uses the cu126 index so the wheel is ABI-compatible with driver 12.7.
# torch>=2.11 (the default pip version) ships with CUDA 13.0 and requires
# driver >=12.8, which breaks on systems reporting "CUDA Version: 12.7".
RUN pip install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu126

# ── 8. CuPy 13.3.0 — CUDA 12.x compatible ────────────────────────────────────
# CuPy 14.x requires CUDA 12.9 (driver 12.8+). Pin to 13.3.0.
RUN pip install --no-cache-dir "cupy-cuda12x==13.3.0"

# ── 9. NN / visualisation / notebook dependencies ────────────────────────────
RUN pip install --no-cache-dir \
        pyvista \
        scipy \
        scikit-learn \
        torchsummary \
        optuna \
        jupyterlab \
        ipywidgets \
        tqdm

# ── 10. Download dataset ──────────────────────────────────────────────────────
# Stored under /data/ so it survives even when /workspace is overridden
# by a volume mount.  The entrypoint creates a symlink at /workspace/CYLINDER.h5.
RUN mkdir -p /data \
 && wget --progress=dot:giga -O /data/CYLINDER.h5 "${DATA_URL}"

# ── 11. Set up workspace and copy notebooks ───────────────────────────────────
RUN mkdir -p /workspace
COPY example_POD_cylinder.ipynb    /workspace/
COPY example_SHRED.ipynb           /workspace/
COPY example_VAE_cylinder.ipynb    /workspace/
COPY example_GAVI_R_cylinder.ipynb /workspace/

# ── 12. Jupyter configuration ─────────────────────────────────────────────────
RUN jupyter lab --generate-config \
 && printf '%s\n' \
    "c.ServerApp.ip = '0.0.0.0'" \
    "c.ServerApp.open_browser = False" \
    "c.ServerApp.allow_root = True" \
    "c.ServerApp.token = ''" \
    "c.ServerApp.password = ''" \
    >> /root/.jupyter/jupyter_lab_config.py

# ── 13. Entrypoint script ─────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── Environment ───────────────────────────────────────────────────────────────
ENV PYTHONUNBUFFERED=1 \
    PYVISTA_OFF_SCREEN=true \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

WORKDIR /workspace
EXPOSE 8888

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

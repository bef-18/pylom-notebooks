# pyLOM NN tutorial notebooks

Self-contained Docker environment for the [pyLOM](https://github.com/ArnauMiro/pyLowOrder) neural-network tutorial notebooks.

## What's included

| Notebook | Topic |
|---|---|
| `example_POD_cylinder.ipynb` | Proper Orthogonal Decomposition on 2-D cylinder flow |
| `example_SHRED.ipynb` | SHallow REcurrent Decoder (SHRED) — all 4 steps |
| `example_VAE_cylinder.ipynb` | 2-D Variational Autoencoder on cylinder flow |
| `example_GAVI_R_cylinder.ipynb` | GAVI-R: QR factorisation + VAE on temporal dynamics |

The dataset (`CYLINDER.h5`, ~418 MB) is downloaded automatically during `docker build` from the [Hugging Face repository](https://huggingface.co/datasets/bef-18/pyLOM_examples/tree/main).

## Requirements

- Docker ≥ 20.10
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- NVIDIA driver ≥ 525 (reports CUDA ≤ 12.7)

## Quick start

```bash
git clone https://github.com/bef-18/pylom-notebooks
cd pylom-notebooks
docker compose build    # ~20 min first time
docker compose up
```

Then open **http://localhost:8888/lab** — no token required.

## Notebook outputs

Checkpoints, plots, and reconstructed fields are written to the container's `/workspace/` directory.
The `./outputs/` folder on the host is mounted to `/workspace/outputs/` for persistent storage.

#!/usr/bin/env bash
# Entrypoint for the pylom-notebooks container.
#
# On first start (or when /workspace is a fresh volume) the CYLINDER.h5
# dataset that was baked into the image is not visible at /workspace/.
# This script symlinks it so notebooks can always use the relative path
# 'CYLINDER.h5' from their working directory.

set -e

WORKSPACE=/workspace
DATA_SRC=/data/CYLINDER.h5
DATA_LINK="${WORKSPACE}/CYLINDER.h5"

# Symlink the baked-in dataset if not already present
if [ ! -e "${DATA_LINK}" ]; then
    ln -s "${DATA_SRC}" "${DATA_LINK}"
    echo "[entrypoint] Linked ${DATA_SRC} -> ${DATA_LINK}"
else
    echo "[entrypoint] Dataset already present at ${DATA_LINK}"
fi

# Launch JupyterLab
exec jupyter lab \
    --notebook-dir="${WORKSPACE}" \
    --no-browser \
    --ip=0.0.0.0 \
    --port=8888

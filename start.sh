#!/usr/bin/env bash
# =============================================================================
# start.sh — Clone pyLOM notebooks and start the Docker container
#
# Usage:
#   bash start.sh
#
# What it does:
#   1. Clones bef-18/pylom-notebooks into ~/Tutorials/pyLOM  (or pulls if exists)
#   2. Adds .vscode/settings.json so Cursor auto-connects to the container
#   3. Pulls bef18/pylom-notebooks:latest from Docker Hub
#   4. Starts the container on port 8889
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/bef-18/pylom-notebooks"
WORKDIR="${HOME}/Tutorials/pyLOM"
IMAGE="bef18/pylom-notebooks:latest"
CONTAINER="pylom_notebooks"
PORT=8889

info() { echo -e "\n\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

# ── 1. Clone or update the notebooks repo ────────────────────────────────────
if [ -d "${WORKDIR}/.git" ]; then
    info "Repo already cloned — pulling latest changes..."
    sudo chown -R ubuntu:ubuntu "${WORKDIR}" 2>/dev/null || true
    git -C "${WORKDIR}" pull
    ok "Repo updated."
elif [ -d "${WORKDIR}" ]; then
    info "Directory exists but is not a git repo — removing and cloning fresh..."
    sudo rm -rf "${WORKDIR}"
    git clone "${REPO_URL}" "${WORKDIR}"
    ok "Repo cloned."
else
    info "Cloning ${REPO_URL} into ${WORKDIR}..."
    mkdir -p "$(dirname "${WORKDIR}")"
    git clone "${REPO_URL}" "${WORKDIR}"
    ok "Repo cloned."
fi

# ── 2. Cursor workspace settings — auto-connect to Docker kernel ──────────────
mkdir -p "${WORKDIR}/.vscode"
cat > "${WORKDIR}/.vscode/settings.json" << EOF
{
    "jupyter.jupyterServerType": "remote",
    "jupyter.serverURI": "http://localhost:${PORT}"
}
EOF
ok "Cursor settings written (.vscode/settings.json → http://localhost:${PORT})."

# ── 3. Pull the Docker image ──────────────────────────────────────────────────
info "Pulling Docker image ${IMAGE}..."
docker pull "${IMAGE}"
ok "Image pulled."

# ── 4. Stop and remove any existing container with the same name ──────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    info "Removing existing container '${CONTAINER}'..."
    docker stop "${CONTAINER}" 2>/dev/null || true
    docker rm   "${CONTAINER}"
fi

# ── 5. Start the container ────────────────────────────────────────────────────
info "Starting container on port ${PORT}..."
docker run -d --gpus all \
    -p "${PORT}:8888" \
    --name "${CONTAINER}" \
    -v "${WORKDIR}:/workspace" \
    "${IMAGE}"

# ── 6. Wait for JupyterLab to be ready ───────────────────────────────────────
info "Waiting for JupyterLab to start..."
for i in $(seq 1 20); do
    if curl -sf "http://localhost:${PORT}/api" > /dev/null 2>&1; then
        ok "JupyterLab is ready."
        break
    fi
    sleep 2
    if [ "${i}" -eq 20 ]; then
        die "JupyterLab did not start in time. Check logs: docker logs ${CONTAINER}"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " pyLOM notebooks environment is running"
echo "------------------------------------------------------------"
echo " Notebooks : ${WORKDIR}"
echo " Container : ${CONTAINER}  (${IMAGE})"
echo " Jupyter   : http://localhost:${PORT}"
echo ""
echo " Open the folder in Cursor — the kernel auto-connects."
echo " To stop:  docker stop ${CONTAINER}"
echo " Logs:     docker logs ${CONTAINER}"
echo "============================================================"

#!/usr/bin/env bash
# Linux equivalent of resolve_model_alias.bat.
# Resolves a user-facing model alias into the canonical model name, the on-disk
# directory name, and the remote repo name. Unlike the .bat (which exports vars
# back to the caller via endlocal), bash scripts cannot mutate the parent shell,
# so this prints three KEY=VALUE lines to stdout that the caller reads/evals.
set -euo pipefail

INPUT_MODEL="${1:-}"
if [[ -z "${INPUT_MODEL}" ]]; then
  echo "[ERROR] Empty model name." >&2
  exit 1
fi

MODEL_NAME="${INPUT_MODEL}"
case "${MODEL_NAME,,}" in
  soma|soma-rp|kimodo-soma-rp) MODEL_NAME="Kimodo-SOMA-RP-v1" ;;
  g1|g1-rp|kimodo-g1-rp)       MODEL_NAME="Kimodo-G1-RP-v1" ;;
  soma-seed|kimodo-soma-seed)  MODEL_NAME="Kimodo-SOMA-SEED-v1" ;;
  g1-seed|kimodo-g1-seed)      MODEL_NAME="Kimodo-G1-SEED-v1" ;;
  smplx|smplx-rp|kimodo-smplx-rp) MODEL_NAME="Kimodo-SMPLX-RP-v1" ;;
esac

if [[ "${MODEL_NAME:0:7}" != "Kimodo-" ]]; then
  echo "[ERROR] Unsupported model alias: ${INPUT_MODEL}" >&2
  exit 1
fi

MODEL_DIR_NAME="${MODEL_NAME}"
MODEL_REPO_NAME="${MODEL_NAME}"
# SOMA-RP-v1 ships from the v1.1 repo, matching the .bat special-case.
if [[ "${MODEL_NAME}" == "Kimodo-SOMA-RP-v1" ]]; then
  MODEL_REPO_NAME="Kimodo-SOMA-RP-v1.1"
fi

echo "MODEL_NAME=${MODEL_NAME}"
echo "MODEL_DIR_NAME=${MODEL_DIR_NAME}"
echo "MODEL_REPO_NAME=${MODEL_REPO_NAME}"
exit 0

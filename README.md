# NvlabKimodoQuickServer

Offline Windows launcher package for running the Kimodo Unity bridge and validating generation with a `tpose` smoke test.

## What this directory does

- Builds/repairs an offline Python runtime (`python312` + `.venv`) for Kimodo.
- Installs core runtime packages (PyTorch via `torchruntime`, `kimodo`, `motion_correction`, `bitsandbytes`).
- Ensures required model folders under `models\`.
- Launches `kimodo.bridge.bridge_server` in offline mode for Unity integration.
- Provides a one-shot bridge integration test (`test_unity_bridge_generate_tpose.bat`).
- Exports neutral skeleton pose JSON files from Kimodo assets.

## Main entry scripts

- `setup_kimodo_offline.bat`
  - End-to-end offline setup.
  - Creates `.kimodo_offline_setup_complete` sentinel on success.
  - Writes log to `setup_kimodo_offline.log` (unless run in background mode).
  - Runs `models\clonemodel.bat` in background when required models are missing.

- `start_kimodo_bridge_offline.bat`
  - Validates setup state and required models.
  - Sets offline HF/Transformers env vars and cache paths.
  - Starts bridge server:
    - module: `kimodo.bridge.bridge_server`
    - args: `--model`, `--kimodo-root`
  - Creates `serverport` and runtime log (`bridge_runtime.log`) in root.

- `test_unity_bridge_generate_tpose.bat`
  - Writes request JSONL with commands: `ping`, `generate`, `quit`.
  - Pipes request to `start_kimodo_bridge_offline.bat`.
  - Writes test log to `bridge_test_generate_tpose.log`.
  - Checks for `"ready"`, `"done"`, `"bye"` statuses.
  - Prints frame/joint summary from returned motion payload.

- `export_kimodo_neutral_poses.bat`
  - Calls `tools\export_kimodo_neutral_poses.py`.
  - Exports neutral pose JSONs from `kimodo\kimodo\assets\skeletons` to `neutral_pose_exports\`.

## Directory structure (key parts)

- `kimodo\`:
  - Kimodo source tree (bridge server and python package).
- `models\`:
  - Model repositories/checkpoints used by offline bridge.
- `wheels\`:
  - Prebuilt `motion_correction` wheels.
- `tools\`:
  - Utility scripts (neutral pose export).
- `get-pip\`:
  - Local `get-pip.py` source used for pip bootstrap.

## Required models for bridge startup

At minimum:

- `models\Kimodo-SOMA-RP-v1\model.safetensors`
- One text encoder source:
  - `models\Meta-Llama-3-8B-Instruct\...` (full model), or
  - `models\KIMODO-Meta3_llm2vec_NF4\model.safetensors`

## Typical usage

From `C:\nvlab\NvlabKimodoQuickServer`:

```bat
setup_kimodo_offline.bat
test_unity_bridge_generate_tpose.bat
```

Or start bridge directly:

```bat
start_kimodo_bridge_offline.bat --model Kimodo-SOMA-RP-v1 --kimodo-root C:\nvlab\NvlabKimodoQuickServer
```

## Important runtime artifacts

- `.setup.lock`: setup in progress marker.
- `.kimodo_offline_setup_complete`: setup success sentinel.
- `run\`: setup completion marker folder.
- `setup_kimodo_offline.log`: setup output log.
- `clonemodel.log`: model clone log.
- `bridge_test_generate_tpose.log`: smoke-test output log.
- `bridge_runtime.log`: bridge server runtime log.
- `serverport`: active bridge host:port.

## Notes

- The setup script is stateful and skips already-satisfied steps.
- `clonemodel.bat` uses `git` + `git lfs`; ensure both are available on PATH.
- Test success criteria is practical bridge behavior (`ready` + `done` + `bye`) rather than only process exit code.

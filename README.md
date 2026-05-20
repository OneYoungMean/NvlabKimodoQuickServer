# NvlabKimodoQuickServer

Windows offline launcher for Kimodo bridge server (new clean pipeline):

- `setup.bat` (env only)
- `download_model.bat` (model assets)
- `run_server.bat` / `start_server.bat` (start bridge)
- `test\test_run_server_tpose.bat`

Legacy scripts are archived under `obstacle\`.

## Quick start

Run in `C:\nvlab\NvlabKimodoQuickServer`:

```bat
setup.bat --output console
start_server.bat --model Kimodo-SOMA-RP-v1 --output console
```

Or smoke test:

```bat
test\test_run_server_tpose.bat
```

## Script behavior

### `setup.bat`

Single-thread environment setup only:

1. Build/repair Python runtime and `.venv`
2. Install runtime dependencies
3. Runtime import check
4. Write setup sentinel `.setup_new_complete`

Options:

- `--output console|file`
- `--log <path>`
- `--force`

### `download_model.bat`

Single-thread model downloader/updater.

Main options:

- `--model <name>`: target Kimodo model directory/repo
- `--highvram`: use full text encoder stack (`Meta-Llama-3-8B-Instruct` + `LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised`)
- default (without `--highvram`): use `KIMODO-Meta3_llm2vec_NF4`
- `--unlock-stale`: rotate stale git lock
- `--force`: force sync even if required file exists
- `--output console|file`
- `--log <path>`
- `KIMODO_LLM2VEC_PEFT_REPO_URL`: optional override when default highvram PEFT repo is inaccessible from current network

Model name examples:

- `Kimodo-SOMA-RP-v1`
- `Kimodo-G1-RP-v1`
- `Kimodo-SMPLX-RP-v1`
- aliases like `soma`, `g1`, `smplx`, `soma-seed`

### `run_server.bat` / `start_server.bat`

`start_server.bat` is a thin wrapper over `run_server.bat`.

Pipeline:

1. Ensure setup sentinel exists, otherwise run `setup.bat`
2. Call `download_model.bat` with selected `--model` and `--highvram`
3. Configure offline env vars and start `kimodo.bridge.bridge_server`

Parameter options:

- `--model <name>`
- `--highvram`
- `--output console|file`
- `--log <path>`
- `--force-setup`

Repeated start behavior:

- If `serverport` exists and requested params are the same as last run, script exits directly.
- If params differ, script sends `quit` to old server, waits for shutdown, then rebuilds with new params.
- In `--highvram` mode, launcher wires `KIMODO_LLM2VEC_DIR`, `KIMODO_LLM2VEC_PEFT_DIR`, and `TEXT_ENCODERS_DIR` to match full Llama + adapter loading.

### `test\test_run_server_tpose.bat`

TCP smoke test:

1. Start `start_server.bat`
2. Wait for `serverport`
3. Send `ping -> generate(tpose) -> quit`
4. Success when response contains `status=done`

Timeout rule:

- if setup/model likely needed: `1800s`
- otherwise: `60s`
- override by env `KIMODO_TEST_WAIT_TIMEOUT_SEC`

## Notes

- `download_model.bat` first checks `git` and `git lfs`; if missing on Windows, it bootstraps a local portable copy under `tools\` and only injects PATH for the current script context (no global/user PATH change).
- New pipeline should be used for run/setup/test; `obstacle\` is archival.

# NvlabKimodoQuickServer

This directory is a clean bridge runtime pipeline for Kimodo.

Target readers:
- AI agents integrating or operating the runtime automatically
- Developers replacing old `setup_kimodo_offline/start_kimodo_bridge_offline` flow

Core goals:
- deterministic setup/start/test
- single-thread script behavior
- model download decoupled from environment setup
- safer repeated start and restart logic

## What It Does

- Provision and validate runtime env (`setup.bat`).
- Download/update model assets (`download_model.bat`).
- Start Kimodo bridge server with model/VRAM options (`run_server.bat`, `start_server.bat`).
- Perform TCP smoke test (`test\test_run_server_tpose.bat`).

## New vs Legacy (Table)

| Aspect | New Pipeline (`setup/download_model/run_server`) | Legacy Pipeline (`setup_kimodo_offline/start_kimodo_bridge_offline`, now in `obstacle\`) |
|---|---|---|
| Setup responsibility | Env only | Env + model checks/download coupled together |
| Model download timing | Explicit `download_model.bat`, and integrated into run/start | Usually happens in setup chain |
| Repeated start behavior | Detects previous signature; same params reuse, different params quit+restart | No equivalent robust signature-based restart flow |
| High VRAM option | `--highvram` explicit | Mainly auto-detect by local files in old flow |
| Git bootstrap | Auto local portable `git/git-lfs` on Windows if missing | Assumes git/lfs already available |
| Test entry | `test\test_run_server_tpose.bat` (new run_server path) | legacy tpose tests in archived scripts |
| Script style | New minimal single-thread path | Legacy compatibility path |

## Quick Start

Run from `C:\nvlab\NvlabKimodoQuickServer`:

```bat
setup.bat --output console
start_server.bat --model Kimodo-SOMA-RP-v1 --output console
```

Smoke test:

```bat
test\test_run_server_tpose.bat
```

## Entry Scripts

- `setup.bat`
- `download_model.bat`
- `run_server.bat`
- `start_server.bat`
- `test\test_run_server_tpose.bat`

Added shell wrappers:

- `setup.sh`
- `download_model.sh`
- `run_server.sh`
- `start_server.sh`
- `test\test_run_server_tpose.sh`

Note: `.sh` wrappers call corresponding `.bat` via `cmd.exe`. They are intended for Git Bash/WSL-on-Windows environments. Pure Linux without `cmd.exe` is not supported by these wrappers.

## Protocol Supported by Server

Bridge server module:
- `kimodo.bridge.bridge_server`

Transport:
- TCP
- newline-delimited JSON request/response

Commands:

1. `ping`
```json
{"cmd":"ping"}
```
Returns: `pong` or `loading` or `error`.

2. `generate`
```json
{
  "cmd":"generate",
  "prompt":"tpose",
  "duration":5.0,
  "seed":42,
  "diffusion_steps":100,
  "constraints_json":""
}
```
Returns `done` with `motion_json_compact` on success.

3. `quit`
```json
{"cmd":"quit"}
```
Returns `bye`.

Common statuses:
- `initializing`
- `loading`
- `ready`
- `progress`
- `pong`
- `done`
- `bye`
- `error`

## Parameters and Model Switching

### `setup.bat`
- `--output console|file`
- `--log <path>`
- `--force`

### `download_model.bat`
- `--model <name>`
- `--highvram`
- `--target <all|soma|nf4>`
- `--unlock-stale`
- `--force`
- `--output console|file`
- `--log <path>`

### `run_server.bat` / `start_server.bat`
- `--model <name>`
- `--highvram`
- `--output console|file`
- `--log <path>`
- `--force-setup`

Supported model names include:
- `Kimodo-SOMA-RP-v1`
- `Kimodo-G1-RP-v1`
- `Kimodo-SMPLX-RP-v1`
- `Kimodo-SOMA-SEED-v1`
- `Kimodo-G1-SEED-v1`
- aliases like `soma`, `g1`, `smplx`, `soma-seed`

## Server Config Behavior

`run_server.bat` will:

1. verify setup sentinel `.setup_new_complete`
2. run setup if missing
3. run model download for selected model/vram mode
4. set local runtime env vars (`HF_HOME`, offline flags, `CHECKPOINT_DIR`, `KIMODO_ROOT_PATH`, etc.)
5. start `python -m kimodo.bridge.bridge_server`

Repeated start logic:
- same signature + existing `serverport` -> skip and reuse
- different signature + existing `serverport` -> send `quit`, wait, restart

## Tests and Examples

Main test:
- `test\test_run_server_tpose.bat`
- wrapper: `test\test_run_server_tpose.sh`

What it validates:
- start server
- wait for `serverport`
- `ping -> generate(tpose) -> quit`
- detect `status=done`

Timeout rule:
- setup/model likely needed: `1800s`
- already prepared: `60s`
- override: `KIMODO_TEST_WAIT_TIMEOUT_SEC`

## Notes

- On Windows, `download_model.bat` checks `git` and `git-lfs` first. If missing, it can bootstrap local portable copies under `tools\` without modifying global PATH.
- Model source normalization supports ModelScope `.../models/...` URLs.
- Pipeline scripts are intentionally single-threaded for stability.

## Known Issues

- `.sh` wrappers depend on `cmd.exe` and are not native Linux launchers.
- Restricted network can break git clone/lfs pulls, especially large model repos.
- Partial model directory states may require `--force` or lock rotation (`--unlock-stale`).
- Existing stale `serverport` or hung old process may require manual inspection if graceful `quit` fails.

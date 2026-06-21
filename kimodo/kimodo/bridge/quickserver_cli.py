from __future__ import annotations

import argparse
import dataclasses
from dataclasses import dataclass
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from typing import Sequence

from . import quickserver_assets as assets
from .quickserver_setup import ProjectPaths, SetupLogger, archive_path, discover_project_paths


BRIDGE_LOG_NAME = "bridge_server.log"
WATCHDOG_LOG_NAME = "watchdog.log"


@dataclass
class PrepareResult:
    resolved_model: assets.ResolvedModel
    models_root: Path
    using_external_models: bool
    runtime_hints: assets.RuntimeHints
    encoder_route: str


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Kimodo QuickServer unified Python entrypoint")
    subparsers = parser.add_subparsers(dest="action", required=True)

    def add_common(run_parser: argparse.ArgumentParser) -> None:
        run_parser.add_argument("--model", default=assets.DEFAULT_MODEL_NAME)
        run_parser.add_argument("--highvram", action="store_true")
        run_parser.add_argument("--output", choices=("console", "file"), default="console")
        run_parser.add_argument("--log")
        run_parser.add_argument("--models-root")
        run_parser.add_argument("--venv")
        run_parser.add_argument("--device")
        run_parser.add_argument("--force-setup", action="store_true")
        run_parser.add_argument("--cpu-text-encoder", default=os.environ.get("KIMODO_CPU_TEXT_ENCODER", "int8"))
        run_parser.add_argument("--watchpid")
        run_parser.add_argument("--config-only", action="store_true")
        run_parser.add_argument("--unlock-stale", action="store_true")
        run_parser.add_argument("--force", action="store_true")

    add_common(subparsers.add_parser("prepare-models"))
    add_common(subparsers.add_parser("run"))
    config_only = subparsers.add_parser("config-only")
    add_common(config_only)
    config_only.set_defaults(config_only=True)
    return parser


def _build_bridge_command(paths: ProjectPaths, prepared: PrepareResult, device: str | None) -> list[str]:
    command = [
        sys.executable,
        "-u",
        "-m",
        "kimodo.bridge.bridge_server",
        "--model",
        prepared.resolved_model.local_name,
        "--kimodo-root",
        str(paths.root_dir),
    ]
    if device:
        command.extend(["--device", device])
    return command


def _project_paths(root_dir: str) -> ProjectPaths:
    return discover_project_paths(root_dir)


def _prepare_logger(
    paths: ProjectPaths,
    output_mode: str,
    log_path: str | None,
    default_name: str,
    append: bool = False,
) -> SetupLogger:
    final_log_path = Path(log_path).resolve() if log_path else paths.log_dir / default_name
    paths.log_dir.mkdir(parents=True, exist_ok=True)
    return SetupLogger(output_mode, final_log_path, append=append)


def _required_encoder_assets(encoder_route: str) -> list[assets.AssetSpec]:
    if encoder_route == "int8":
        return [assets.INT8_ASSET]
    if encoder_route == "full":
        return [assets.FULL_BASE_ASSET, assets.FULL_PEFT_ASSET]
    return [assets.NF4_ASSET]


def _prepare_models(paths: ProjectPaths, args: argparse.Namespace, logger: SetupLogger) -> PrepareResult:
    resolved_model = assets.resolve_main_model(args.model)
    models_root, using_external_models = assets.resolve_models_root(paths.root_dir, args.models_root)
    hints = assets.normalize_runtime_hints(args.device, args.cpu_text_encoder)
    encoder_route = assets.choose_prepare_encoder_route(bool(args.highvram), hints)

    logger.log(f"[INFO] model={resolved_model.local_name}")
    logger.log(f"[INFO] models_root={models_root}")
    logger.log(f"[INFO] encoder_route={encoder_route}")

    allow_download = not using_external_models
    if using_external_models:
        logger.log(f"[STEP] External models root enabled; validating local assets only: {models_root}")
    else:
        models_root.mkdir(parents=True, exist_ok=True)

    download_counter = [0]
    main_asset = assets.AssetSpec(
        label="main model",
        local_dir_name=resolved_model.local_name,
        modelscope_repo=resolved_model.modelscope_repo,
        huggingface_repo=resolved_model.huggingface_repo,
    )
    assets.ensure_asset_present(
        main_asset,
        assets.local_model_dir(models_root, resolved_model),
        logger,
        paths.recovery_flag_dir,
        download_counter,
        allow_download=allow_download,
    )

    for encoder_asset in _required_encoder_assets(encoder_route):
        assets.ensure_asset_present(
            encoder_asset,
            models_root / encoder_asset.local_dir_name,
            logger,
            paths.recovery_flag_dir,
            download_counter,
            allow_download=allow_download,
        )

    if assets.should_inject_once(
        paths.recovery_flag_dir,
        "model_missing_after_download",
        "KIMODO_TEST_INJECT_MODEL_MISSING_AFTER_DOWNLOAD_ONCE",
    ):
        main_dir = assets.local_model_dir(models_root, resolved_model)
        logger.log(f"[TEST] Injected model-missing-once by archiving downloaded asset dir: {main_dir}")
        assets.archive_path(main_dir, paths.recycle_dir)

    logger.log("[OK] prepare-models complete.")
    return PrepareResult(
        resolved_model=resolved_model,
        models_root=models_root,
        using_external_models=using_external_models,
        runtime_hints=hints,
        encoder_route=encoder_route,
    )


def _runtime_import_preflight(logger: SetupLogger) -> None:
    import motion_correction  # noqa: F401
    import torch
    import kimodo  # noqa: F401

    logger.log(f"torch={torch.__version__}")
    logger.log(f"cuda={torch.version.cuda}")


def _launch_bridge(paths: ProjectPaths, args: argparse.Namespace, prepared: PrepareResult, logger: SetupLogger) -> int:
    bridge_log_path = logger.log_path
    watchdog_log_path = paths.log_dir / WATCHDOG_LOG_NAME
    bridge_pid_file = paths.root_dir / ".bridge.pid"
    port_file = paths.root_dir / "serverport"
    archive_path(port_file, paths.recycle_dir)
    archive_path(bridge_pid_file, paths.recycle_dir)
    if args.output == "file":
        archive_path(bridge_log_path, paths.recycle_dir)
        archive_path(watchdog_log_path, paths.recycle_dir)

    runtime_env = assets.build_runtime_env(
        root_dir=paths.root_dir,
        source_root=paths.source_root,
        models_root=prepared.models_root,
        encoder_route=prepared.encoder_route,
        highvram=bool(args.highvram),
        hints=prepared.runtime_hints,
        cpu_text_encoder=args.cpu_text_encoder,
    )
    runtime_env.update(assets.build_offline_cache_env(paths.root_dir))
    runtime_env["KIMODO_IDLE_TIMEOUT_SEC"] = os.environ.get("KIMODO_IDLE_TIMEOUT_SEC", "600")

    for cache_dir in (
        Path(runtime_env["HF_HOME"]),
        Path(runtime_env["TRANSFORMERS_CACHE"]),
        Path(runtime_env["HF_HUB_CACHE"]),
    ):
        cache_dir.mkdir(parents=True, exist_ok=True)

    launch_env = os.environ.copy()
    launch_env.update(runtime_env)
    launch_env["KIMODO_BRIDGE_LOG"] = str(bridge_log_path)
    launch_env["KIMODO_BRIDGE_LOG_DIRECT_ONLY"] = "1" if args.output == "file" else "0"
    bridge_log_path.parent.mkdir(parents=True, exist_ok=True)
    bridge_log_path.touch(exist_ok=True)

    command = _build_bridge_command(paths, prepared, prepared.runtime_hints.normalized_device)

    logger.log("[STEP] Launching bridge...")
    popen_kwargs = {
        "cwd": str(paths.root_dir),
        "env": launch_env,
        "text": True,
        "encoding": "utf-8",
        "errors": "replace",
    }
    if args.output == "file":
        with bridge_log_path.open("a", encoding="utf-8", newline="\n") as bridge_log_stream:
            popen_kwargs["stdout"] = bridge_log_stream
            popen_kwargs["stderr"] = bridge_log_stream
            launch_proc = subprocess.Popen(command, **popen_kwargs)
            bridge_pid_file.write_text(f"{launch_proc.pid}\n", encoding="utf-8", newline="\n")
            runtime_env["KIMODO_BRIDGE_PID"] = str(launch_proc.pid)
            logger.log(f"[INFO] Runtime device: {prepared.runtime_hints.normalized_device or '<auto>'}")
            logger.log(f"[INFO] Text encoder route: {prepared.encoder_route}")
            logger.log(f"[INFO] Text encoder dir: {runtime_env['KIMODO_LLM2VEC_DIR']}")
            logger.log(f"[INFO] Bridge PID: {launch_proc.pid}")
            watchdog_rc = _run_watchdog(paths, launch_proc.pid, port_file, bridge_log_path, launch_env, args.watchpid)
            launch_proc.poll()
    else:
        launch_proc = subprocess.Popen(command, **popen_kwargs)
        bridge_pid_file.write_text(f"{launch_proc.pid}\n", encoding="utf-8", newline="\n")
        runtime_env["KIMODO_BRIDGE_PID"] = str(launch_proc.pid)
        logger.log(f"[INFO] Runtime device: {prepared.runtime_hints.normalized_device or '<auto>'}")
        logger.log(f"[INFO] Text encoder route: {prepared.encoder_route}")
        logger.log(f"[INFO] Text encoder dir: {runtime_env['KIMODO_LLM2VEC_DIR']}")
        logger.log(f"[INFO] Bridge PID: {launch_proc.pid}")
        watchdog_rc = _run_watchdog(paths, launch_proc.pid, port_file, bridge_log_path, launch_env, args.watchpid)
        launch_proc.poll()

    archive_path(bridge_pid_file, paths.recycle_dir)
    return watchdog_rc


def _run_watchdog(
    paths: ProjectPaths,
    bridge_pid: int,
    port_file: Path,
    bridge_log_path: Path,
    launch_env: dict[str, str],
    watchpid: str | None,
) -> int:
    startup_interval = int(os.environ.get("KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC", "1"))
    startup_max_fails = int(os.environ.get("KIMODO_WATCHDOG_STARTUP_MAX_FAILS", "180"))
    runtime_interval = int(os.environ.get("KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC", "1"))
    idle_no_log_max = int(os.environ.get("KIMODO_WATCHDOG_IDLE_NOLOG_MAX", "300"))
    watchdog_log_path = paths.log_dir / WATCHDOG_LOG_NAME
    watchdog_log_path.parent.mkdir(parents=True, exist_ok=True)
    last_mtime = 0
    startup_fails = 0
    started_ok = False

    def _write_watchdog(line: str) -> None:
        with watchdog_log_path.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(line + "\n")
            stream.flush()

    def _is_running(pid: int) -> bool:
        if pid <= 0:
            return False
        if os.name == "nt":
            import ctypes.wintypes

            handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, int(pid))
            if not handle:
                return False
            try:
                code = ctypes.wintypes.DWORD()
                if not ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
                    return False
                return int(code.value) == 259
            finally:
                ctypes.windll.kernel32.CloseHandle(handle)
        return Path(f"/proc/{pid}").exists()

    def _kill_bridge() -> None:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/PID", str(bridge_pid), "/T", "/F"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            try:
                os.kill(bridge_pid, signal.SIGTERM)
            except Exception:
                pass

    _write_watchdog(
        f"[INFO] Bridge watchdog started. pid={bridge_pid} startup_interval={startup_interval}s "
        f"startup_max_fails={startup_max_fails} runtime_interval={runtime_interval}s idle_nolog_max={idle_no_log_max}"
    )

    while True:
        if not _is_running(bridge_pid):
            return 0 if started_ok else 1

        if not started_ok:
            if port_file.exists():
                started_ok = True
                try:
                    last_mtime = int(bridge_log_path.stat().st_mtime)
                except Exception:
                    last_mtime = 0
                time.sleep(runtime_interval)
                continue
            startup_fails += 1
            if startup_fails >= startup_max_fails:
                _write_watchdog(f"[ERROR] serverport not found within {startup_max_fails} checks. Killing pid={bridge_pid}")
                _kill_bridge()
                return 1
            _write_watchdog(f"[INFO] Waiting serverport ({startup_fails}/{startup_max_fails})")
            time.sleep(startup_interval)
            continue

        if watchpid and os.name == "nt":
            if not _is_running(int(watchpid)):
                _write_watchdog(f"[WARN] Owner pid missing. owner_pid={watchpid} bridge_pid={bridge_pid}")
                _kill_bridge()
                return 0

        try:
            now_mtime = int(bridge_log_path.stat().st_mtime)
        except Exception:
            now_mtime = last_mtime
        if now_mtime == last_mtime:
            idle_no_log_max -= 1
        else:
            idle_no_log_max = int(os.environ.get("KIMODO_WATCHDOG_IDLE_NOLOG_MAX", "300"))
            last_mtime = now_mtime
        if idle_no_log_max <= 0:
            _write_watchdog(f"[INFO] No bridge log update for runtime window. Killing pid={bridge_pid}")
            _kill_bridge()
            return 0
        time.sleep(runtime_interval)


def main(argv: Sequence[str] | None = None, *, root_dir: str | None = None, source_root: str | None = None) -> int:
    raw_args = list(argv or [])
    parser = _build_parser()
    if any(arg in ("-h", "--help") for arg in raw_args):
        parser.print_help()
        return 0
    args = parser.parse_args(raw_args)
    paths = _project_paths(root_dir or str(Path(__file__).resolve().parents[3]))
    if source_root:
        paths = dataclasses.replace(paths, source_root=Path(source_root).resolve())
    bridge_log_path = Path(args.log).resolve() if getattr(args, "log", None) else paths.log_dir / BRIDGE_LOG_NAME
    watchdog_log_path = paths.log_dir / WATCHDOG_LOG_NAME

    action = args.action
    if action == "config-only":
        args.config_only = True
        action = "run"

    if action == "prepare-models":
        if args.output == "file":
            archive_path(bridge_log_path, paths.recycle_dir)
        with _prepare_logger(paths, args.output, args.log, BRIDGE_LOG_NAME, append=False) as logger:
            try:
                _prepare_models(paths, args, logger)
            except Exception as exc:
                logger.log(f"[ERROR] prepare-models failed: {exc}")
                return 1
        return 0

    if args.output == "file":
        archive_path(bridge_log_path, paths.recycle_dir)
        archive_path(watchdog_log_path, paths.recycle_dir)

    with _prepare_logger(paths, args.output, args.log, BRIDGE_LOG_NAME, append=False) as prepare_logger:
        try:
            prepared = _prepare_models(paths, args, prepare_logger)
        except Exception as exc:
            prepare_logger.log(f"[ERROR] prepare-models failed: {exc}")
            return 1

    with _prepare_logger(paths, args.output, args.log, BRIDGE_LOG_NAME, append=True) as run_logger:
        try:
            run_logger.log("[STEP] Preflight runtime import check...")
            _runtime_import_preflight(run_logger)
            if args.config_only:
                run_logger.log("[OK] Config-only completed. Bridge not started.")
                return 0
            return _launch_bridge(paths, args, prepared, run_logger)
        except Exception as exc:
            run_logger.log(f"[ERROR] run failed: {exc}")
            return 1

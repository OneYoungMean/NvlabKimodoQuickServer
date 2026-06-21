from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import os
from pathlib import Path
import shutil
import threading
import time
from typing import Protocol


DEFAULT_MODEL_NAME = "Kimodo-SOMA-RP-v1"
GGUF_LOCAL_DIR = "KIMODO-Meta3_llm2vec_FP16-Q6_K"
NF4_LOCAL_DIR = "KIMODO-Meta3_llm2vec_NF4"
FULL_BASE_LOCAL_DIR = "Meta-Llama-3-8B-Instruct"
FULL_PEFT_LOCAL_DIR = "LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"


class LoggerLike(Protocol):
    def log(self, message: str) -> None: ...


@dataclass(frozen=True)
class MainModelSpec:
    local_name: str
    modelscope_repo: str
    huggingface_repo: str
    aliases: tuple[str, ...] = ()


@dataclass(frozen=True)
class AssetSpec:
    label: str
    local_dir_name: str
    modelscope_repo: str
    huggingface_repo: str | None


@dataclass(frozen=True)
class ResolvedModel:
    requested_name: str
    local_name: str
    modelscope_repo: str
    huggingface_repo: str


@dataclass(frozen=True)
class RuntimeHints:
    normalized_device: str | None
    setup_mode: str
    text_encoder_device_hint: str
    explicit_cpu_gguf: bool


MAIN_MODELS: tuple[MainModelSpec, ...] = (
    MainModelSpec(
        local_name="Kimodo-SOMA-RP-v1",
        modelscope_repo="nv-community/Kimodo-SOMA-RP-v1.1",
        huggingface_repo="nvidia/Kimodo-SOMA-RP-v1.1",
        aliases=("soma", "soma-rp", "kimodo-soma-rp"),
    ),
    MainModelSpec(
        local_name="Kimodo-SOMA-RP-v1.1",
        modelscope_repo="nv-community/Kimodo-SOMA-RP-v1.1",
        huggingface_repo="nvidia/Kimodo-SOMA-RP-v1.1",
    ),
    MainModelSpec(
        local_name="Kimodo-SMPLX-RP-v1",
        modelscope_repo="nv-community/Kimodo-SMPLX-RP-v1",
        huggingface_repo="nvidia/Kimodo-SMPLX-RP-v1",
        aliases=("smplx", "smplx-rp", "kimodo-smplx-rp"),
    ),
    MainModelSpec(
        local_name="Kimodo-G1-RP-v1",
        modelscope_repo="nv-community/Kimodo-G1-RP-v1",
        huggingface_repo="nvidia/Kimodo-G1-RP-v1",
        aliases=("g1", "g1-rp", "kimodo-g1-rp"),
    ),
    MainModelSpec(
        local_name="Kimodo-SOMA-SEED-v1",
        modelscope_repo="nv-community/Kimodo-SOMA-SEED-v1",
        huggingface_repo="nvidia/Kimodo-SOMA-SEED-v1",
        aliases=("soma-seed", "kimodo-soma-seed"),
    ),
    MainModelSpec(
        local_name="Kimodo-SOMA-SEED-v1.1",
        modelscope_repo="nv-community/Kimodo-SOMA-SEED-v1.1",
        huggingface_repo="nvidia/Kimodo-SOMA-SEED-v1.1",
    ),
    MainModelSpec(
        local_name="Kimodo-G1-SEED-v1",
        modelscope_repo="nv-community/Kimodo-G1-SEED-v1",
        huggingface_repo="nvidia/Kimodo-G1-SEED-v1",
        aliases=("g1-seed", "kimodo-g1-seed"),
    ),
)

GGUF_ASSET = AssetSpec(
    label="GGUF text encoder",
    local_dir_name=GGUF_LOCAL_DIR,
    modelscope_repo="oneyoungmean/KIMODO-Meta3_llm2vec_FP16-Q6_K",
    huggingface_repo="oneyoungmean/KIMODO-Meta3_llm2vec_FP16-Q6_K",
)
NF4_ASSET = AssetSpec(
    label="NF4 text encoder",
    local_dir_name=NF4_LOCAL_DIR,
    modelscope_repo="oneyoungmean/KIMODO-Meta3_llm2vec_NF4",
    huggingface_repo="Aero-Ex/KIMODO-Meta3_llm2vec_NF4",
)
FULL_BASE_ASSET = AssetSpec(
    label="full text encoder base",
    local_dir_name=FULL_BASE_LOCAL_DIR,
    modelscope_repo="LLM-Research/Meta-Llama-3-8B-Instruct",
    huggingface_repo="meta-llama/Meta-Llama-3-8B-Instruct",
)
FULL_PEFT_ASSET = AssetSpec(
    label="full text encoder peft",
    local_dir_name=FULL_PEFT_LOCAL_DIR,
    modelscope_repo="oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised",
    huggingface_repo="McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised",
)


def resolve_main_model(requested_name: str | None) -> ResolvedModel:
    raw_name = str(requested_name or DEFAULT_MODEL_NAME).strip()
    if not raw_name:
        raise ValueError("Empty model name.")
    lookup = raw_name.lower()
    for spec in MAIN_MODELS:
        if lookup == spec.local_name.lower() or lookup in spec.aliases:
            return ResolvedModel(
                requested_name=raw_name,
                local_name=spec.local_name,
                modelscope_repo=spec.modelscope_repo,
                huggingface_repo=spec.huggingface_repo,
            )
    if lookup.startswith("kimodo-"):
        return ResolvedModel(
            requested_name=raw_name,
            local_name=raw_name,
            modelscope_repo=f"nv-community/{raw_name}",
            huggingface_repo=f"nvidia/{raw_name}",
        )
    raise ValueError(f"Unsupported model alias: {raw_name}")


def normalize_runtime_hints(run_device: str | None, cpu_text_encoder: str) -> RuntimeHints:
    normalized_device: str | None = None
    setup_mode = "auto"
    text_encoder_device_hint = "auto"
    explicit_cpu_gguf = False
    raw_device = str(run_device or "").strip()
    if raw_device:
        lowered = raw_device.lower()
        if lowered == "cpu":
            normalized_device = "cpu"
            setup_mode = "cpu"
            text_encoder_device_hint = "cpu"
            explicit_cpu_gguf = str(cpu_text_encoder or "").strip().lower() == "gguf"
        elif lowered == "cuda":
            normalized_device = "cuda:0"
        elif lowered.startswith("cuda"):
            normalized_device = raw_device
        else:
            raise ValueError(f"Invalid --device value: {run_device}")
    return RuntimeHints(
        normalized_device=normalized_device,
        setup_mode=setup_mode,
        text_encoder_device_hint=text_encoder_device_hint,
        explicit_cpu_gguf=explicit_cpu_gguf,
    )


def detect_total_vram_gb() -> float:
    try:
        import torch

        if torch.cuda.is_available() and torch.cuda.device_count() > 0:
            props = torch.cuda.get_device_properties(0)
            return float(props.total_memory) / (1024 ** 3)
    except Exception:
        pass
    return 0.0


def should_use_gguf(total_vram_gb: float, force_override: str | None = None) -> bool:
    normalized = str(force_override or "").strip()
    if normalized == "1":
        return True
    if normalized == "0":
        return False
    return float(total_vram_gb) < 6.0


def choose_prepare_encoder_route(highvram: bool, hints: RuntimeHints, total_vram_gb: float | None = None) -> str:
    if hints.explicit_cpu_gguf:
        return "gguf"
    if total_vram_gb is None:
        total_vram_gb = detect_total_vram_gb()
    if should_use_gguf(total_vram_gb):
        return "gguf"
    return "full" if highvram else "nf4"


def default_models_root(root_dir: str | os.PathLike[str]) -> Path:
    return (Path(root_dir).resolve() / "models").resolve()


def resolve_models_root(root_dir: str | os.PathLike[str], models_root_arg: str | None) -> tuple[Path, bool]:
    root = Path(root_dir).resolve()
    raw_value = str(models_root_arg or os.environ.get("KIMODO_MODELS_ROOT") or "").strip()
    models_root = Path(raw_value).expanduser() if raw_value else default_models_root(root)
    if not models_root.is_absolute():
        models_root = (root / models_root).resolve()
    else:
        models_root = models_root.resolve()
    return models_root, models_root != default_models_root(root)


def default_gguf_model_path(models_root: str | os.PathLike[str]) -> str:
    return str((Path(models_root).resolve() / GGUF_LOCAL_DIR / f"{GGUF_LOCAL_DIR}.gguf").resolve())


def locate_gguf_file(model_dir: str | os.PathLike[str]) -> Path:
    return Path(model_dir).resolve() / f"{GGUF_LOCAL_DIR}.gguf"


def gguf_ready_path(models_root: str | os.PathLike[str]) -> Path:
    return Path(default_gguf_model_path(models_root))


def local_model_dir(models_root: str | os.PathLike[str], resolved_model: ResolvedModel) -> Path:
    return Path(models_root).resolve() / resolved_model.local_name


def archive_path(target: Path, recycle_dir: Path) -> None:
    if not target.exists():
        return
    recycle_dir.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    destination = recycle_dir / f"{target.name}.{timestamp}.{os.getpid()}.{int(time.time() * 1000) % 1000}"
    try:
        shutil.move(str(target), str(destination))
    except Exception:
        pass


def should_inject_once(recovery_flag_dir: Path, key: str, env_var: str) -> bool:
    if os.environ.get(env_var, "").strip() != "1":
        return False
    recovery_flag_dir.mkdir(parents=True, exist_ok=True)
    flag_path = recovery_flag_dir / f"{key}.done"
    if flag_path.exists():
        return False
    flag_path.write_text(
        "\n".join(
            [
                f"scenario={os.environ.get('KIMODO_TEST_SCENARIO_NAME', '')}",
                f"key={key}",
                f"time={time.strftime('%Y-%m-%d %H:%M:%S')}",
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )
    return True


def _format_bytes(value: int) -> str:
    size = float(max(0, int(value)))
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    for unit in units:
        if size < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024.0
    return f"{int(value)} B"


@contextmanager
def _suppress_modelscope_tqdm():
    try:
        import modelscope.hub.file_download as file_download
        import modelscope.hub.snapshot_download as snapshot_download_mod
    except Exception:
        yield
        return

    original_file_tqdm = getattr(file_download, "tqdm", None)
    original_snapshot_tqdm = getattr(snapshot_download_mod, "tqdm", None)
    original_tqdm_callback = getattr(file_download, "TqdmCallback", None)

    class _NoopTqdm:
        def __init__(self, *args, **kwargs):
            self.total = kwargs.get("total", 0)

        def update(self, *args, **kwargs):
            return None

        def refresh(self):
            return None

        def close(self):
            return None

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            self.close()
            return False

        def set_description(self, *args, **kwargs):
            return None

        def set_postfix(self, *args, **kwargs):
            return None

    class _NoopProgressCallback:
        def __init__(self, *args, **kwargs):
            pass

        def update(self, *args, **kwargs):
            return None

        def end(self):
            return None

    if original_file_tqdm is not None:
        file_download.tqdm = _NoopTqdm
    if original_snapshot_tqdm is not None:
        snapshot_download_mod.tqdm = _NoopTqdm
    if original_tqdm_callback is not None:
        file_download.TqdmCallback = _NoopProgressCallback

    try:
        yield
    finally:
        if original_file_tqdm is not None:
            file_download.tqdm = original_file_tqdm
        if original_snapshot_tqdm is not None:
            snapshot_download_mod.tqdm = original_snapshot_tqdm
        if original_tqdm_callback is not None:
            file_download.TqdmCallback = original_tqdm_callback


def _make_logged_progress_callback(logger: LoggerLike, label: str):
    log_lock = threading.Lock()

    class _LoggedProgressCallback:
        def __init__(self, filename: str, file_size: int):
            self.filename = str(filename)
            self.file_size = max(0, int(file_size or 0))
            self.downloaded = 0
            self._last_logged_at = 0.0
            self._started_at = time.monotonic()
            self._finished = False
            self._log(
                f"[DOWNLOAD] {label}: {self.filename} started "
                f"({self._size_text(self.file_size)})"
            )

        def _log(self, message: str) -> None:
            with log_lock:
                logger.log(message)

        def _size_text(self, value: int) -> str:
            return _format_bytes(value)

        def _status_text(self) -> str:
            if self.file_size > 0:
                downloaded = min(self.downloaded, self.file_size)
                percent = min(100, int(downloaded * 100 / self.file_size))
                return (
                    f"{self._size_text(downloaded)}/{self._size_text(self.file_size)} "
                    f"({percent}%)"
                )
            return f"{self._size_text(self.downloaded)} downloaded"

        def _maybe_log(self, final: bool = False) -> None:
            if self._finished and not final:
                return
            now = time.monotonic()
            if not final and now - self._last_logged_at < 5.0:
                return
            self._last_logged_at = now
            self._log(f"[DOWNLOAD] {label}: {self.filename} {self._status_text()}")

        def update(self, size: int):
            self.downloaded += int(size)
            self._maybe_log(final=False)

        def end(self):
            if self._finished:
                return
            self._finished = True
            if self.file_size > 0:
                self.downloaded = max(self.downloaded, self.file_size)
            elapsed = time.monotonic() - self._started_at
            self._log(
                f"[DOWNLOAD] {label}: {self.filename} complete "
                f"({self._status_text()}, {elapsed:.1f}s)"
            )

    return _LoggedProgressCallback


def ensure_asset_present(
    asset: AssetSpec,
    target_dir: Path,
    logger: LoggerLike,
    recovery_flag_dir: Path,
    download_counter: list[int],
) -> None:
    if should_inject_once(recovery_flag_dir, "download_net_bad", "KIMODO_TEST_INJECT_DOWNLOAD_NET_BAD_ONCE"):
        raise RuntimeError("Injected download network failure once.")
    logger.log(f"[STEP] Downloading {asset.label}: {asset.local_dir_name}")
    target_dir.mkdir(parents=True, exist_ok=True)
    if not asset.modelscope_repo:
        raise RuntimeError(f"Missing ModelScope repo id for {asset.label}.")

    from modelscope import snapshot_download as ms_snapshot_download

    try:
        progress_callbacks = [_make_logged_progress_callback(logger, asset.label)]
        with _suppress_modelscope_tqdm():
            ms_snapshot_download(
                model_id=asset.modelscope_repo,
                local_dir=str(target_dir),
                progress_callbacks=progress_callbacks,
            )
    except Exception as exc:
        raise RuntimeError(f"Failed to download {asset.label} via ModelScope: {exc}") from exc

    logger.log(f"[OK] {asset.label} ready via ModelScope: {asset.modelscope_repo}")
    download_counter[0] += 1
    if should_inject_once(recovery_flag_dir, "download_abort", "KIMODO_TEST_INJECT_DOWNLOAD_ABORT_ONCE"):
        raise RuntimeError("Injected download interrupt once.")


def build_runtime_env(
    root_dir: str | os.PathLike[str],
    source_root: str | os.PathLike[str],
    models_root: str | os.PathLike[str],
    highvram: bool,
    hints: RuntimeHints,
    cpu_text_encoder: str,
    gguf_model_path: str | None,
    gguf_ctx: str | None,
) -> dict[str, str]:
    root = Path(root_dir).resolve()
    models_path = Path(models_root).resolve()
    env: dict[str, str] = {
        "PYTHONPATH": str(Path(source_root).resolve()),
        "KIMODO_ROOT_PATH": str(root),
        "CHECKPOINT_DIR": str(models_path),
        "KIMODO_MODELS_ROOT": str(models_path),
        "KIMODO_HIGHVRAM": "1" if highvram else "0",
        "LOCAL_CACHE": "true",
        "TEXT_ENCODER": "llm2vec",
        "KIMODO_CPU_TEXT_ENCODER": str(cpu_text_encoder or "gguf"),
        "KIMODO_GGUF_MODEL_PATH": str(gguf_model_path or default_gguf_model_path(models_path)),
    }
    if hints.text_encoder_device_hint:
        env["KIMODO_TEXT_ENCODER_DEVICE_HINT"] = hints.text_encoder_device_hint
    if gguf_ctx:
        env["KIMODO_GGUF_CTX"] = str(gguf_ctx)
    if highvram:
        env["KIMODO_LLM2VEC_DIR"] = str(models_path / FULL_BASE_LOCAL_DIR)
        env["TEXT_ENCODERS_DIR"] = str(models_path)
        env["KIMODO_LLM2VEC_PEFT_DIR"] = str(models_path / FULL_PEFT_LOCAL_DIR)
    else:
        env["KIMODO_LLM2VEC_DIR"] = str(models_path / NF4_LOCAL_DIR)
        env["TEXT_ENCODERS_DIR"] = ""
        env["KIMODO_LLM2VEC_PEFT_DIR"] = ""
    if hints.explicit_cpu_gguf:
        env["KIMODO_FORCE_GGUF"] = "1"
    return env


def build_offline_cache_env(root_dir: str | os.PathLike[str]) -> dict[str, str]:
    root = Path(root_dir).resolve()
    hf_home = root / "hf_cache"
    return {
        "HF_HOME": str(hf_home),
        "TRANSFORMERS_CACHE": str(hf_home / "transformers"),
        "HF_HUB_CACHE": str(hf_home / "hub"),
        "HUGGINGFACE_HUB_CACHE": str(hf_home / "hub"),
        "TRANSFORMERS_OFFLINE": "1",
        "HF_HUB_OFFLINE": "1",
        "HF_DATASETS_OFFLINE": "1",
        "PYTHONUNBUFFERED": "1",
    }

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from torchruntime.device_db import get_gpus
from torchruntime.installer import get_install_commands
from torchruntime.platform_detection import get_torch_platform


def _run(cmd):
    completed = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed ({completed.returncode}): {' '.join(cmd)}\n{completed.stdout}")
    return completed.stdout


def _download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        return

    tmp = dest.with_suffix(dest.suffix + ".part")
    headers = {"User-Agent": "Mozilla/5.0"}
    if tmp.exists():
        headers["Range"] = f"bytes={tmp.stat().st_size}-"

    req = Request(url, headers=headers)
    mode = "ab" if tmp.exists() else "wb"
    with urlopen(req) as response, open(tmp, mode) as fp:
        shutil.copyfileobj(response, fp, length=1024 * 1024)

    if dest.exists():
        dest.unlink()
    tmp.replace(dest)


def _extract_downloads(report_data):
    downloads = []
    for entry in report_data.get("install", []):
        metadata = entry.get("metadata") or {}
        download_info = entry.get("download_info") or {}
        url = download_info.get("url")
        if not url:
            continue
        downloads.append(
            {
                "name": metadata.get("name"),
                "version": metadata.get("version"),
                "url": url,
            }
        )
    return downloads


def _strip_index_args(install_args: list[str]) -> list[str]:
    stripped = []
    skip_next = False
    for arg in install_args:
        if skip_next:
            skip_next = False
            continue
        if arg in ("--index-url", "--extra-index-url", "-i"):
            skip_next = True
            continue
        stripped.append(arg)
    return stripped


def _run_dry_run_report(python_exe: str, install_args: list[str], report_path: Path) -> dict:
    cmd = [python_exe, "-m", "pip", "install", "--dry-run", "--report", str(report_path)]
    cmd.extend(install_args)
    print("[PLAN]", " ".join(cmd))
    output = _run(cmd)
    if output.strip():
        print(output.rstrip())
    return json.loads(report_path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", required=True)
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--plan-file", required=True)
    parser.add_argument("--packages", nargs="*", default=["torch", "torchvision", "torchaudio"])
    args = parser.parse_args()

    cache_dir = Path(args.cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    plan_file = Path(args.plan_file)
    plan_file.parent.mkdir(parents=True, exist_ok=True)

    torch_platform = get_torch_platform(get_gpus(), packages=args.packages)
    install_commands = get_install_commands(torch_platform, args.packages)
    plan = {
        "platform": torch_platform,
        "packages": args.packages,
        "commands": [],
    }

    if torch_platform == "cpu":
        plan_file.write_text(json.dumps(plan, indent=2), encoding="utf-8")
        print(f"[INFO] torch platform={torch_platform}, nothing to download.")
        return 0

    total_downloads = 0
    for index, install_args in enumerate(install_commands):
        with tempfile.TemporaryDirectory() as tmp_dir:
            report_path = Path(tmp_dir) / f"report-{index}.json"
            report_data = _run_dry_run_report(args.python, install_args, report_path)
            downloads = _extract_downloads(report_data)
            command_plan = {
                "install_args": install_args,
                "offline_install_args": _strip_index_args(install_args),
                "downloads": downloads,
            }
            plan["commands"].append(command_plan)

            for item in downloads:
                total_downloads += 1
                file_name = Path(urlparse(item["url"]).path).name
                if not file_name:
                    continue
                dest = cache_dir / file_name
                if dest.exists() and dest.stat().st_size > 0:
                    continue
                print(f"[DL] {item.get('name')} {item.get('version')} -> {dest.name}")
                _download_file(item["url"], dest)

    plan_file.write_text(json.dumps(plan, indent=2), encoding="utf-8")

    if total_downloads == 0:
        print("[INFO] No new torch wheels required by dry-run plan.")

    for command_plan in plan["commands"]:
        offline_args = command_plan.get("offline_install_args") or []
        if not offline_args:
            continue
        final_cmd = [args.python, "-m", "pip", "install", "--no-index", "--find-links", str(cache_dir)]
        final_cmd.extend(offline_args)
        print("[INSTALL]", " ".join(final_cmd))
        output = _run(final_cmd)
        if output.strip():
            print(output.rstrip())

    print(f"[OK] torch runtime resolved for {torch_platform}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

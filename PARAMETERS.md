# NvlabKimodoQuickServer 参数说明

## 1. `bash\setup.bat`
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式下日志文件路径，默认 `log\setup.log`。
- `--force`: 强制重新 setup（会归档旧 sentinel）。

相关环境变量：
- `KIMODO_SETUP_BG=1`: 允许 setup 直出到当前控制台，不重定向到 `setup_buildenv_impl.log`。

## 2. `bash\setup_buildenv_impl.bat`
核心行为：
- 仅使用本地 `program\exe\uv\uv.exe`。
- 仅使用本地 `program\exe\git` 与 `git-lfs`。
- 创建/复用 `kimodo\.venv` 并安装依赖。

相关环境变量：
- `KIMODO_NETWORK_FALLBACK_HEAD_TIMEOUT_SEC`: index 探测超时秒数，默认 `3`。
- `KIMODO_PYTHON_ARCH`: 目前仅支持 x64；设为 `x86` 会直接报错退出。
- `KIMODO_BUILDENV_ONLY=1`: 只构建环境不做额外流程。

测试注入变量（默认关闭）：
- `KIMODO_TEST_INJECT_SETUP_ABORT_ONCE=1`
- `KIMODO_TEST_INJECT_SETUP_NET_BAD_ONCE=1`
- `KIMODO_TEST_SCENARIO_NAME=<name>`

## 3. `bash\download_model.bat`
- `--model <name|alias>`: 模型名称或别名（默认 `Kimodo-SOMA-RP-v1`）。
- `--highvram`: 下载 high-vram 依赖模型集。
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式日志路径，默认 `log\download_model.log`。
- `--unlock-stale`: 检测并旋转 `.git\index.lock`。
- `--force`: 强制同步。

相关环境变量：
- `KIMODO_LLM2VEC_NF4_REPO_URL`
- `KIMODO_META_LLAMA_REPO_URL`
- `KIMODO_LLM2VEC_PEFT_REPO_URL`

测试注入变量（默认关闭）：
- `KIMODO_TEST_INJECT_DOWNLOAD_ABORT_ONCE=1`
- `KIMODO_TEST_INJECT_DOWNLOAD_NET_BAD_ONCE=1`
- `KIMODO_TEST_INJECT_MODEL_MISSING_AFTER_DOWNLOAD_ONCE=1`

## 4. `run_server.bat`
- `--model <name|alias>`: 默认 `Kimodo-SOMA-RP-v1`。
- `--highvram`: 启用 high-vram 模式。
- `--models-root <path>`: 指定外部模型根目录（存在即跳过下载流程）。
- `--output <console|file>`: 输出模式，默认 `console`。
- `--log <path>`: `file` 模式下服务日志路径，默认 `log\run_server.log`。
- `--force-setup`: 归档 setup sentinel 后重新 setup。

关键运行变量：
- `KIMODO_MODELS_ROOT`: 默认 models 根目录（可被 `--models-root` 覆盖）。
- `KIMODO_IDLE_TIMEOUT_SEC`: 服务空闲退出秒数（当前设定 `600`）。

### 启动探活与 watchdog（已优化）
- `KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC`: 启动期探活间隔（默认 `1` 秒）。
- `KIMODO_WATCHDOG_STARTUP_MAX_FAILS`: 启动期最大连续失败次数（默认 `30`）。
- `KIMODO_WATCHDOG_CONNECT_TIMEOUT_MS`: 每次连接超时（默认 `800` ms）。
- `KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC`: 运行期检查间隔（默认 `1` 秒）。
- `KIMODO_WATCHDOG_IDLE_NOLOG_MAX`: 日志不更新次数阈值（默认 `300`）。

说明：
- 默认总启动探活窗口约 `30s`（`1s * 30`），比原 `3s * 10` 体感更快。

## 5. `example\example_run_server_tpose.bat`
- 默认流程：后台启动 `run_server` -> 读取 `serverport` -> 发送 `ping/generate(tpose)/quit`。
- 通过判定：客户端退出码 `0` 且出现 `status=done`。

相关环境变量：
- `KIMODO_TEST_OUTPUT=console|file`（默认 `console`）
- `KIMODO_TEST_WAIT_TIMEOUT_SEC`（默认 `600`）
- `KIMODO_TEST_MODEL`
- `KIMODO_TEST_HIGHVRAM=0|1`
- `KIMODO_TEST_MODELS_ROOT=<path>`
- `KIMODO_TEST_SERVER_WINDOW_STYLE=Normal|Hidden|Minimized|Maximized`

## 6. 日志约定
- 默认所有日志写入 `log\`。
- 典型文件：
  - `log\setup.log`
  - `log\download_model.log`
  - `log\run_server.log` 或调用方指定文件
  - `log\bridge_bootstrap_error.log`
  - `log\example_run_server_tpose.log`
  - `log\example_run_server_tpose_client.log`

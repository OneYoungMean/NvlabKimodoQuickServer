# NvlabKimodoQuickServer（中文）

## 语言说明
- 中文说明：`README_ZH.md`
- 英文说明：`README.md`

## 功能介绍
- 使用 `uv` 构建运行环境。
- 启动 Kimodo bridge 服务并支持模型参数。
- 提供 TCP 示例链路（`ping -> generate -> quit`）。

## 环境要求
- Windows 10/11 x64
- 本地工具位于 `program\exe\`：
  - `uv\uv.exe`
  - `git\cmd\git.exe`
  - `git\mingw32\bin\git-lfs.exe`
- 可用模型目录（推荐）：`C:\nvlab\models~`

## 安装
```bat
cd /d C:\nvlab\NvlabKimodoQuickServer
bash\setup.bat --output console
```

## Example
```bat
cd /d C:\nvlab\NvlabKimodoQuickServer
run_server.bat --model Kimodo-SOMA-RP-v1 --models-root C:\nvlab\models~ --output console
```

TCP 冒烟测试：
```bat
example\example_run_server_tpose.bat
```

控制台实时日志版本：
```bat
example\example_run_server_tpose_console_live.bat
```

## 参数文档
- 见 `PARAMETERS.md`

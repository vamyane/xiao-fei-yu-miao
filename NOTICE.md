# 第三方组件与许可（NOTICE）

本仓库（小肥鱼喵一键部署包）自身代码以 MIT 发布，但**包含或集成了第三方组件**，各自的许可与归属如下。

## 1. 随包分发的组件

### qq-bridge
- 仓库：https://github.com/Derpyu520/qq-bridge
- 许可：MIT
- 版权：Copyright (c) 2026 Derpyu520 and qq-bridge / QSH contributors
- 分发位置：`payload/qq-bridge/`（含完整 MIT LICENSE 文件）
- 本仓库对其所做的修改（均在同一 MIT 许可下）：
  1. 新增 `src/mcp-media.js`：媒体工具 MCP（AI 画图 / 发图 / TTS 语音），含白名单与限频。
  2. `dsh/agent-presets/qq-chat*/agent.cordis.yml`：DSH 0.2.1 兼容（移除已废弃的 `{{cwd}}` 模板变量）、补充媒体工具使用说明、更新语音说明。
  3. `plugins/qq-agent-presets/qq-tool-restrict.mjs`：安全白名单增加 `mcp__media__` 前缀。
  4. `plugins/qq-agent-presets/presets/*.patch.yml`：由上述源文件重新生成的预设补丁。
  5. `config.example.json` / `config.template.json`：默认值调整（晓伊音色、撒娇后期、频率限制、媒体配置）。
  6. 其他：安装/启动脚本与部署集成（不在 qq-bridge 上游代码内）。
- MIT 许可要求：在任何副本中保留上述版权声明与许可声明。本仓库及分发包均已保留 `payload/qq-bridge/LICENSE`。

### 7-Zip（7zr.exe）
- 项目：https://www.7-zip.org/
- 许可：GNU LGPL
- 用途：解压 ComfyUI 便携包（可选步骤）
- 位置：`payload/tools/7zr.exe`，并附 `LICENSE-7zip.txt`

## 2. 安装时才从官方渠道下载的组件（不随本仓库分发）

### Node.js
- 许可：MIT
- 分发：安装器在系统缺少 Node >=22.13 时，从 npmmirror 镜像下载官方便携包并解压到用户安装目录。

### ffmpeg（Gyan.dev 构建）
- 许可：LGPL/GPL（以 Gyan 构建说明为准）
- 分发：仅在系统无 ffmpeg 时，从 gyan.dev 官方构建页下载。

### ComfyUI
- 仓库：https://github.com/comfyanonymous/ComfyUI
- 许可：GPL-3.0
- 分发：安装器从 Comfy-Org 官方 GitHub Release 下载便携包，不在本仓库分发二进制。
- 画图模型：Counterfeit-V2.5（https://huggingface.co/gsdf/Counterfeit-V2.5），遵循模型作者许可；安装器从 hf-mirror 下载。

### DeepSeek Harness (DSH)
- 官网：https://deepseek-harness.github.io/
- 许可：闭源商业软件
- 本仓库**不包含、不修改、不再分发** DSH；安装器仅检测本机安装并生成配置。

### SnowLuma
- 仓库：https://github.com/SnowLuma/SnowLuma
- 许可：专有组件（EULA）
- 本仓库**不包含、不再分发、不自动部署** SnowLuma；安装器仅检测其是否运行、读取其 OneBot 配置以便桥接连接。
- SnowLuma EULA §5.4 明确：将其并入第三方安装包、Docker 镜像或通过自动化脚本部署，须事先取得书面授权。

### Microsoft Edge
- 用途：作为控制台界面窗口（`--app` 模式）的运行时。
- 未分发；Windows 10/11 默认自带。

## 3. 致谢

感谢以上所有开源/第三方项目的作者。若你是某组件的作者并希望调整归属方式、链接或分发方式，请通过本仓库 Issue 联系。

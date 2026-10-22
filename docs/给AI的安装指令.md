# 给 AI Agent 的安装指令（复制整段发给 DSH）

> 用途：用户已完成「小肥鱼喵一键部署」。把下面整段内容发给 DSH Agent，让它自动验收、修复、并按需补装画图能力。
> 变量（由安装器自动替换）：安装目录 `{{INSTALL_DIR}}`、SnowLuma 目录 `{{SNOWLUMA_DIR}}`、主号 QQ `{{MAIN_QQ}}`、DSH 端口 `{{DSH_PORT}}`。

---

你是运行在用户 Windows 电脑上的 DSH Agent。请按以下步骤**验收并修复**「小肥鱼喵」QQ 机器人部署。每一步先检查，已满足就跳过，不要重复安装。执行命令前先用只读方式确认路径存在。

## 0. 总览

整套系统由 5 部分组成：

| 组件 | 路径/端口 | 作用 |
| --- | --- | --- |
| DSH | 端口 `{{DSH_PORT}}` | 机器人「大脑」，运行 agent |
| SnowLuma | `{{SNOWLUMA_DIR}}`，端口 5099 / OneBot 3000、3001 | QQ 协议端 |
| qq-bridge | `{{INSTALL_DIR}}`，端口 3100 | QQ ↔ DSH 桥接 |
| 媒体 MCP | `{{INSTALL_DIR}}\src\mcp-media.js` | 画图 / 发图 / TTS 语音 |
| 小肥鱼喵 App | `{{INSTALL_DIR}}\app\小肥鱼喵.exe`，端口 5210 | 桌面控制台 |

验收标准：`{{INSTALL_DIR}}` 存在且 `node_modules` 已安装；DSH profile 里有 qq 预设与 4 个 MCP（snowluma / snowluma-host / web-search-safe / media）；计划任务 `QQBotStart`、`QQBotStop` 存在；端口 5099/3000/3001/3100 在监听；QQ 小号在线（OneBot `get_login_info` 返回 ok）。

## 1. 只读检查（不要修改）

```powershell
Test-Path '{{INSTALL_DIR}}\src\bridge.js'
Test-Path '{{INSTALL_DIR}}\node_modules'
Get-ChildItem '{{INSTALL_DIR}}\app' | Select-Object Name
foreach ($p in 5099,3000,3001,3100,8188,5210) { if (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) { "$p OK" } else { "$p DOWN" } }
schtasks /Query /TN QQBotStart
schtasks /Query /TN QQBotStop
```

检查 DSH profile（通常 `%USERPROFILE%\.dsh\profiles\desktop`）：

```powershell
Get-Content "$env:USERPROFILE\.dsh\profiles\desktop\cordis.patch.yml" | Select-String 'snowluma|web-search-safe|mcp-media'
```

检查配置：

```powershell
Get-Content '{{INSTALL_DIR}}\config.json' -Raw | ConvertFrom-Json | Select-Object @{n='dsh';e={$_.dsh.baseUrl}}, @{n='allow';e={$_.allow}}, @{n='tts';e={$_.media.ttsVoice}}, @{n='cutePost';e={$_.media.cutePost.enabled}}
```

## 2. 自动修复（仅在检查失败时执行）

**a) 端口 3100 不在**：

```powershell
Set-Location '{{INSTALL_DIR}}'
# 确认 config.json 的 dsh.baseUrl 与当前 DSH 端口一致；不一致就改
node -e "const fs=require('fs');const p='config.json';const c=JSON.parse(fs.readFileSync(p,'utf8'));c.dsh.baseUrl='http://127.0.0.1:{{DSH_PORT}}';fs.writeFileSync(p,JSON.stringify(c,null,2))"
Start-Process -FilePath (Get-Command node).Source -ArgumentList 'src/bridge.js' -WorkingDirectory '{{INSTALL_DIR}}' -WindowStyle Hidden
```

**b) DSH 预设/MCP 缺失**——重新执行桥接自带的安装脚本（profile 名按实际目录替换）：

```powershell
Set-Location '{{INSTALL_DIR}}'
node scripts\setup-dsh.mjs desktop
```

然后确认 `cordis.patch.yml` 包含 `mcp-media`；若没有，追加：

```yaml
- insert:
    - id: mcp-media
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: media
        transport: stdio
        command: '<node.exe 的绝对路径>'
        args:
          - '{{INSTALL_DIR}}\src\mcp-media.js'
        toolCallTimeoutMs: 300600
```

改完需要重启 DSH 或让用户重启 DSH 才会生效。

**c) 依赖缺失**：

```powershell
Set-Location '{{INSTALL_DIR}}'
npm install --no-audit --no-fund --registry https://registry.npmmirror.com
```

**d) QQ 不在线**：不要尝试自动登录。提醒用户：打开 `{{SNOWLUMA_DIR}}\launcher.bat`，浏览器进 http://127.0.0.1:5099 扫码登录；确认 OneBot WS(3001) 与 HTTP(3000) 已开启。

**e) 计划任务缺失**：用安装目录里的 `start-all.ps1` 重新创建（参考安装器的 schtasks 命令）。

## 3. 可选：补装 ComfyUI 画图

仅当用户要求画图且 8188 不在时执行（约 4GB 下载）：

1. 下载 `https://ghproxy.net/https://github.com/Comfy-Org/ComfyUI/releases/download/v0.42.1/ComfyUI_windows_portable_nvidia.7z`
2. 用 7z 解压到 `D:\ComfyUI`（可用 `{{INSTALL_DIR}}\deploy-kit\payload\tools\7zr.exe`，若还在）
3. 下载模型 `https://hf-mirror.com/gsdf/Counterfeit-V2.5/resolve/main/Counterfeit-V2.5_fp16.safetensors` 到 `D:\ComfyUI\ComfyUI_windows_portable\ComfyUI\models\checkpoints\`
4. 用 `{{INSTALL_DIR}}\start-all.ps1` 启动（会自动拉起 ComfyUI）
5. 确认 8188 就绪后，在控制台 App 里点「启动全部」

## 4. 安全与边界（必须遵守）

- 不要修改 DSH 与 SnowLuma 的安装目录或程序文件；不要自动点击/伪造 SnowLuma 的 EULA 与扫码。
- 不要读取、打印或上传用户的 DeepSeek API Key、QQ 密码、Cookie。
- 不要向陌生群/陌生人发消息；不要高频发送（机器人已限制 15 条/分钟、12 次唤醒/小时）。
- 所有改动前先备份：`config.json`、`cordis.patch.yml`。

## 5. 最终验收

依次确认并报告：

1. 5 项服务状态（DSH / SnowLuma / 桥接 / ComfyUI(可选) / QQ 在线）
2. 用主号 `{{MAIN_QQ}}` 发一条测试消息，确认收到回复
3. 报告安装目录、端口、已启用能力（表情包/画图/语音/撒娇音色）
4. 如仍有问题，输出「具体失败步骤 + 日志片段 + 建议修复命令」，不要笼统说“失败了”。

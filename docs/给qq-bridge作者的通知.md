# 给 qq-bridge 作者的说明（Issue 草稿）

> 用途：发布仓库后，可用 GitHub Issue 告知 qq-bridge 作者 Derpyu520，说明本项目的集成与修改，并致谢。
> 建议标题：`关于「小肥鱼喵」QQ 机器人一键部署包集成 qq-bridge 的说明与致谢`

---

你好 @Derpyu520，

我是 [你的 GitHub 用户名]，最近做了一个面向小白的 Windows 一键部署包「小肥鱼喵」，把 qq-bridge 集成进了一套完整的 QQ AI 机器人方案里（DSH + SnowLuma + qq-bridge + 媒体工具 + 桌面控制台）。

仓库链接：<发布后填写>

因为项目里**随包分发了 qq-bridge 源码（MIT）**，并按 MIT 保留了你仓库的 LICENSE 与版权声明，所以特意来同步一下，也感谢你做出这么好用的桥接。

## 我们做的修改（都在 MIT 下，公开可见）

1. 新增 `src/mcp-media.js`：媒体工具 MCP，提供「AI 画图（ComfyUI）/ 发图 / TTS 语音」，带白名单与限频。
2. `dsh/agent-presets/qq-chat*/agent.cordis.yml`：
   - 移除 DSH 0.2.1 已废弃的 `{{cwd}}` 模板变量（否则报 `unknown prompt variable`）；
   - 增加媒体工具使用说明与语音说明。
3. `plugins/qq-agent-presets/qq-tool-restrict.mjs`：安全白名单增加 `mcp__media__` 前缀。
4. 由上述源文件重新生成的 `presets/*.patch.yml`。
5. `config.template.json`：默认值调整（TTS 音色/撒娇后期、频率限制、媒体配置、白名单）。
6. 额外增加了安装器、控制台 App、启动脚本与教程，这些不依赖上游代码修改。

## 合规方面

- 我们没有打包、也没有自动部署 SnowLuma（遵守其 EULA §5.4），只检测端口并读取 OneBot 配置。
- 我们没有打包 DSH，只检测本机安装与端口。
- 分发包里保留了 `payload/qq-bridge/LICENSE` 原文与版权声明。

## 想请你确认的事

- 如果这些修改里有一部分你愿意收进上游（比如 `{{cwd}}` 兼容、媒体 MCP 思路、白名单扩展），我可以整理成 PR；
- 如果你对随包分发、README 致谢方式、链接位置有任何要求，或者希望我们改为只引用不随包，请告诉我，我会照做；
- 如果项目定位/命名上需要调整，也可以直接说。

再次感谢！如果这个项目打扰到你，我很抱歉，会立刻调整。

祝好
[你的名字]

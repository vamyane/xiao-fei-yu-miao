## 小肥鱼喵 · QQ AI 智能体一键部署包 v1.0.0

Windows 小白一键部署：**DSH（大脑）+ SnowLuma（QQ 网关）+ qq-bridge（桥接）+ 媒体工具（画图/语音/发图）+ 桌面控制台**。

### 下载
- 本 Release 附件：\xiao-fei-yu-miao-v1.0.zip\（9.1MB）
- 或在仓库 \dist/\ 目录下载

> SHA256：\$hash\

### 使用前提
1. 自行安装 **DSH**（https://deepseek-harness.github.io/）并完成初始化
2. 自行下载 **SnowLuma**（https://github.com/SnowLuma/SnowLuma/releases/latest），运行并扫码登录小号，开启 OneBot WS(3001)+HTTP(3000)
3. 准备 **DeepSeek API Key** 与 **QQ 小号**

### 三步部署
1. 解压 zip，双击 \小肥鱼喵一键部署.exe\
2. 填写 API Key / 主号 QQ / 安装目录，勾选两个“已就绪”，点开始
3. 完成后打开桌面「小肥鱼喵」，把 API Key 粘贴到 DSH 设置即可开聊

详细教程：\docs/小白安装教程.md\；AI 自动验收：\docs/给AI的安装指令.md\

### 合规说明
- **不包含 DSH / SnowLuma 二进制**：DSH 闭源商业软件；SnowLuma EULA §5.4 禁止并入第三方安装包或自动化部署。
- qq-bridge 以 MIT 许可随包分发，已保留原作者版权与 LICENSE；详见 \NOTICE.md\、\COMPLIANCE.md\。
- 第三方协议端登录存在 QQ 风控风险，请使用小号并遵守平台协议。

### 已知限制
- 未在全新机器上完成端到端验证（开发机已装 DSH/SnowLuma），欢迎 Issue 反馈 \install.log\。
- 首次安装约 5~15 分钟（取决于网速）；ComfyUI 可选，额外约 4GB。

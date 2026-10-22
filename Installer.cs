using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;

class Installer
{
    static Form form;
    static TextBox apiKey, mainQQ, botQQ, installDir, snowDir;
    static CheckBox chkComfy, chkDsh, chkSnow, chkAgree;
    static TextBox logBox;
    static ProgressBar bar;
    static Label status;
    static Button btnStart, btnOpenLog, btnOpenReport, btnOpenAi, btnOpenApp, btnClose;
    static bool running = false;
    static string kitDir = "";

    [STAThread]
    static void Main()
    {
        kitDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        BuildUi();
        Application.Run(form);
    }

    static Label MakeLabel(string text, int x, int y, int w, float size, bool bold, Color color)
    {
        Label l = new Label();
        l.Text = text;
        l.Left = x; l.Top = y;
        l.AutoSize = true;
        l.MaximumSize = new Size(w, 0);
        l.Font = new Font("Microsoft YaHei UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
        l.ForeColor = color;
        l.BackColor = Color.Transparent;
        return l;
    }

    static TextBox MakeBox(int x, int y, int w, string text)
    {
        TextBox t = new TextBox();
        t.Left = x; t.Top = y; t.Width = w;
        t.Text = text;
        t.BackColor = Color.FromArgb(26, 29, 36);
        t.ForeColor = Color.FromArgb(238, 242, 248);
        t.BorderStyle = BorderStyle.FixedSingle;
        t.Font = new Font("Microsoft YaHei UI", 9.5f);
        t.Height = 26;
        return t;
    }

    static Button MakeButton(string text, int x, int y, int w, int h, Color back, Color fore)
    {
        Button b = new Button();
        b.Text = text; b.Left = x; b.Top = y; b.Width = w; b.Height = h;
        b.BackColor = back; b.ForeColor = fore; b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderSize = 0;
        b.Font = new Font("Microsoft YaHei UI", 9f);
        b.Cursor = Cursors.Hand;
        return b;
    }

    static void BuildUi()
    {
        Color bg = Color.FromArgb(15, 17, 21);
        Color panel = Color.FromArgb(26, 29, 36);
        Color text = Color.FromArgb(238, 242, 248);
        Color muted = Color.FromArgb(152, 162, 179);
        Color green = Color.FromArgb(52, 211, 153);
        Color accent = Color.FromArgb(124, 92, 255);

        form = new Form();
        form.Text = "小肥鱼喵 · 一键部署";
        form.ClientSize = new Size(900, 800);
        form.StartPosition = FormStartPosition.CenterScreen;
        form.BackColor = bg;
        form.ForeColor = text;
        form.FormBorderStyle = FormBorderStyle.FixedSingle;
        form.MaximizeBox = false;
        form.AutoScaleMode = AutoScaleMode.None;

        string iconPath = Path.Combine(kitDir, "app.ico");
        if (File.Exists(iconPath)) { try { form.Icon = new Icon(iconPath); } catch { } }

        // 标题区
        Label title = MakeLabel("小肥鱼喵", 26, 12, 400, 20f, true, accent);
        form.Controls.Add(title);
        form.Controls.Add(MakeLabel("QQ 智能体 · 一键部署（DSH + SnowLuma + 桥接 + 控制台）", 26, 52, 700, 9.5f, false, muted));

        // 风险确认
        chkAgree = new CheckBox();
        chkAgree.Text = "我已了解：DSH/SnowLuma 需自行安装并同意其协议；第三方协议端存在 QQ 封号风险，请使用小号";
        chkAgree.Left = 26; chkAgree.Top = 84; chkAgree.Width = 850; chkAgree.Height = 26;
        chkAgree.ForeColor = Color.FromArgb(251, 191, 36);
        chkAgree.BackColor = Color.Transparent;
        form.Controls.Add(chkAgree);

        // API Key
        form.Controls.Add(MakeLabel("DeepSeek API Key（部署完成后自动复制，去 DSH 设置里粘贴）", 26, 122, 700, 9f, true, text));
        apiKey = MakeBox(26, 146, 560, "");
        apiKey.UseSystemPasswordChar = true;
        apiKey.Font = new Font("Consolas", 10.5f);
        form.Controls.Add(apiKey);

        // QQ
        form.Controls.Add(MakeLabel("你的主号 QQ", 26, 186, 250, 9f, true, text));
        mainQQ = MakeBox(26, 210, 250, "");
        mainQQ.Font = new Font("Consolas", 10.5f);
        form.Controls.Add(mainQQ);

        form.Controls.Add(MakeLabel("机器人小号 QQ（可选，扫码后自动识别）", 300, 186, 320, 9f, true, text));
        botQQ = MakeBox(300, 210, 250, "");
        botQQ.Font = new Font("Consolas", 10.5f);
        form.Controls.Add(botQQ);

        // 目录 + 下载按钮
        form.Controls.Add(MakeLabel("安装目录（桥接 + 控制台）", 26, 250, 300, 9f, true, text));
        installDir = MakeBox(26, 274, 330, @"D:\qq-bridge");
        form.Controls.Add(installDir);

        form.Controls.Add(MakeLabel("SnowLuma 目录", 380, 250, 200, 9f, true, text));
        snowDir = MakeBox(380, 274, 240, @"D:\SnowLuma");
        form.Controls.Add(snowDir);

        Button btnDshPage = MakeButton("下载 DSH", 640, 272, 95, 30, panel, text);
        btnDshPage.Click += (s, e) => OpenUrl("https://deepseek-harness.github.io/");
        form.Controls.Add(btnDshPage);

        Button btnSnowPage = MakeButton("下载 SnowLuma", 745, 272, 130, 30, panel, text);
        btnSnowPage.Click += (s, e) => OpenUrl("https://github.com/SnowLuma/SnowLuma/releases/latest");
        form.Controls.Add(btnSnowPage);

        // 就绪确认
        chkDsh = new CheckBox();
        chkDsh.Text = "DSH 已安装并完成初始化/登录";
        chkDsh.Left = 26; chkDsh.Top = 320; chkDsh.Width = 300;
        chkDsh.ForeColor = text; chkDsh.BackColor = Color.Transparent; chkDsh.Checked = true;
        form.Controls.Add(chkDsh);

        chkSnow = new CheckBox();
        chkSnow.Text = "SnowLuma 已启动并扫码登录";
        chkSnow.Left = 340; chkSnow.Top = 320; chkSnow.Width = 300;
        chkSnow.ForeColor = text; chkSnow.BackColor = Color.Transparent; chkSnow.Checked = true;
        form.Controls.Add(chkSnow);

        chkComfy = new CheckBox();
        chkComfy.Text = "额外安装 ComfyUI 画图（约 4GB 下载，可稍后加）";
        chkComfy.Left = 26; chkComfy.Top = 352; chkComfy.Width = 520;
        chkComfy.ForeColor = muted; chkComfy.BackColor = Color.Transparent;
        form.Controls.Add(chkComfy);

        // 开始按钮 + 状态
        btnStart = MakeButton("▶ 开始部署", 26, 390, 200, 44, green, Color.FromArgb(5, 46, 34));
        btnStart.Font = new Font("Microsoft YaHei UI", 10.5f, FontStyle.Bold);
        btnStart.Click += (s, e) => StartDeploy();
        form.Controls.Add(btnStart);

        status = MakeLabel("准备就绪", 250, 402, 620, 9.5f, false, muted);
        form.Controls.Add(status);

        bar = new ProgressBar();
        bar.Left = 26; bar.Top = 446; bar.Width = 848; bar.Height = 6;
        bar.Style = ProgressBarStyle.Marquee; bar.MarqueeAnimationSpeed = 0; bar.Visible = false;
        form.Controls.Add(bar);

        // 日志
        logBox = new TextBox();
        logBox.Multiline = true; logBox.ScrollBars = ScrollBars.Vertical; logBox.ReadOnly = true;
        logBox.Left = 26; logBox.Top = 462; logBox.Width = 848; logBox.Height = 270;
        logBox.BackColor = Color.FromArgb(10, 12, 16); logBox.ForeColor = Color.FromArgb(183, 194, 208);
        logBox.Font = new Font("Consolas", 9.5f); logBox.BorderStyle = BorderStyle.FixedSingle;
        form.Controls.Add(logBox);

        // 底部按钮
        btnOpenLog = MakeButton("打开日志文件", 26, 744, 130, 32, panel, muted);
        btnOpenLog.Visible = false; btnOpenLog.Click += (s, e) => OpenFile(Path.Combine(kitDir, "install.log"));
        form.Controls.Add(btnOpenLog);

        btnOpenReport = MakeButton("部署报告", 166, 744, 110, 32, panel, muted);
        btnOpenReport.Visible = false; btnOpenReport.Click += (s, e) => OpenFile(Path.Combine(installDir.Text, "部署完成报告.md"));
        form.Controls.Add(btnOpenReport);

        btnOpenAi = MakeButton("给 AI 的指令", 286, 744, 120, 32, panel, muted);
        btnOpenAi.Visible = false; btnOpenAi.Click += (s, e) => OpenFile(Path.Combine(installDir.Text, "docs", "给AI的安装指令.md"));
        form.Controls.Add(btnOpenAi);

        btnOpenApp = MakeButton("打开小肥鱼喵", 416, 744, 140, 32, Color.FromArgb(46, 100, 170), Color.White);
        btnOpenApp.Visible = false; btnOpenApp.Click += (s, e) => { try { Process.Start(Path.Combine(installDir.Text, "app", "小肥鱼喵.exe")); } catch { } };
        form.Controls.Add(btnOpenApp);

        btnClose = MakeButton("关闭", 744, 744, 130, 32, panel, muted);
        btnClose.Click += (s, e) => { if (!running) form.Close(); };
        form.Controls.Add(btnClose);
    }

    static void OpenUrl(string url) { try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { } }

    static void OpenFile(string path)
    {
        try { if (File.Exists(path)) Process.Start(new ProcessStartInfo("notepad.exe", "\"" + path + "\"") { UseShellExecute = false }); } catch { }
    }

    static void Log(string line)
    {
        if (logBox.InvokeRequired) { logBox.BeginInvoke(new Action(() => Log(line))); return; }
        logBox.AppendText(line + Environment.NewLine);
    }

    static void StartDeploy()
    {
        if (running) return;
        if (!chkAgree.Checked) { MessageBox.Show("请先勾选最上方的风险与协议说明。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        if (!chkDsh.Checked) { MessageBox.Show("请先安装 DSH 桌面版并完成初始化，再勾选确认。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        if (!chkSnow.Checked) { MessageBox.Show("请先启动 SnowLuma 并扫码登录小号，再勾选确认。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        if (mainQQ.Text.Trim() == "" || !System.Text.RegularExpressions.Regex.IsMatch(mainQQ.Text.Trim(), @"^\d{5,12}$")) { MessageBox.Show("请填写正确的主号 QQ（纯数字）。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        if (installDir.Text.Trim() == "") { MessageBox.Show("请填写安装目录。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

        running = true;
        btnStart.Enabled = false;
        chkComfy.Enabled = false; chkDsh.Enabled = false; chkSnow.Enabled = false; chkAgree.Enabled = false;
        bar.Visible = true; bar.MarqueeAnimationSpeed = 30;
        logBox.Clear();
        status.Text = "正在部署，请保持窗口打开…";
        status.ForeColor = Color.FromArgb(251, 191, 36);

        string deploy = Path.Combine(kitDir, "deploy.ps1");
        if (!File.Exists(deploy)) { Log("找不到 deploy.ps1"); EndDeploy(false); return; }

        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + deploy + "\" "
            + "-InstallDir \"" + installDir.Text.Trim() + "\" "
            + "-MainQQ " + mainQQ.Text.Trim() + " "
            + (botQQ.Text.Trim() != "" ? "-BotQQ " + botQQ.Text.Trim() + " " : "")
            + "-SnowLumaDir \"" + snowDir.Text.Trim() + "\" "
            + (chkComfy.Checked ? "-WithComfyUI " : "");

        try
        {
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", args);
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
            Process p = new Process();
            p.StartInfo = psi;
            p.OutputDataReceived += (s, e) => { if (!string.IsNullOrEmpty(e.Data)) Log(e.Data); };
            p.ErrorDataReceived += (s, e) => { if (!string.IsNullOrEmpty(e.Data)) Log("[stderr] " + e.Data); };
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            p.WaitForExit();
            Log("进程退出码：" + p.ExitCode);
            EndDeploy(p.ExitCode == 0);
        }
        catch (Exception ex)
        {
            Log("部署启动失败：" + ex.Message);
            EndDeploy(false);
        }
    }

    static void EndDeploy(bool ok)
    {
        running = false;
        bar.MarqueeAnimationSpeed = 0;
        bar.Visible = false;
        if (ok)
        {
            status.Text = "✅ 部署完成，小肥鱼喵已上线";
            status.ForeColor = Color.FromArgb(90, 230, 130);
            btnStart.Text = "重新部署";
            btnStart.Enabled = true;
            if (apiKey.Text.Trim() != "")
            {
                try { Clipboard.SetText(apiKey.Text.Trim()); } catch { }
                MessageBox.Show("部署完成！\r\n\r\nDeepSeek API Key 已复制到剪贴板：\r\n请打开 DSH 设置，把 Key 粘贴到模型配置里。\r\n然后点「打开小肥鱼喵」查看状态。", "部署完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            btnOpenLog.Visible = true; btnOpenReport.Visible = true; btnOpenAi.Visible = true; btnOpenApp.Visible = true;
        }
        else
        {
            status.Text = "❌ 部署未完成，请看日志";
            status.ForeColor = Color.FromArgb(248, 113, 113);
            btnStart.Enabled = true;
            btnOpenLog.Visible = true;
            MessageBox.Show("部署未完成。请查看窗口里的日志；也可以打开日志文件排查。\r\n\r\n常见原因：DSH 未初始化、SnowLuma 未启动、网络无法访问镜像。", "部署失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        chkComfy.Enabled = true; chkDsh.Enabled = true; chkSnow.Enabled = true; chkAgree.Enabled = true;
    }
}

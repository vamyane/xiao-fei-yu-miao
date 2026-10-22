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
    static Button btnStart, btnOpenLog, btnOpenApp, btnOpenReport, btnOpenAi, btnClose;
    static bool running = false;
    static string kitDir = "";
    static bool success = false;

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
        l.Left = x; l.Top = y; l.Width = w; l.Height = 24;
        l.Font = new Font("Microsoft YaHei UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
        l.ForeColor = color;
        l.BackColor = Color.Transparent;
        return l;
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
        form.ClientSize = new Size(900, 660);
        form.StartPosition = FormStartPosition.CenterScreen;
        form.BackColor = bg;
        form.ForeColor = text;
        form.FormBorderStyle = FormBorderStyle.FixedSingle;
        form.MaximizeBox = false;

        form.Controls.Add(MakeLabel("小肥鱼喵", 26, 18, 240, 20f, true, accent));
        form.Controls.Add(MakeLabel("QQ 智能体 · 一键部署（DSH + SnowLuma + 桥接 + 控制台）", 26, 46, 620, 9.5f, false, muted));

        chkAgree = new CheckBox();
        chkAgree.Text = "我已了解：DSH/SnowLuma 需自行安装并同意其协议；第三方协议端登录存在 QQ 封号风险，请使用小号。";
        chkAgree.Left = 28; chkAgree.Top = 82; chkAgree.Width = 840; chkAgree.Height = 26;
        chkAgree.ForeColor = Color.FromArgb(251, 191, 36);
        chkAgree.BackColor = Color.Transparent;
        form.Controls.Add(chkAgree);

        int top = 120;
        form.Controls.Add(MakeLabel("DeepSeek API Key（部署完成后自动复制，去 DSH 设置里粘贴）", 28, top, 600, 9f, true, text));
        apiKey = new TextBox(); apiKey.Left = 28; apiKey.Top = top + 26; apiKey.Width = 560; apiKey.Height = 30;
        apiKey.UseSystemPasswordChar = true; apiKey.BackColor = panel; apiKey.ForeColor = text; apiKey.BorderStyle = BorderStyle.FixedSingle;
        apiKey.Font = new Font("Consolas", 10.5f);
        form.Controls.Add(apiKey);

        form.Controls.Add(MakeLabel("你的主号 QQ", 28, top + 64, 200, 9f, true, text));
        mainQQ = new TextBox(); mainQQ.Left = 28; mainQQ.Top = top + 90; mainQQ.Width = 260; mainQQ.BackColor = panel; mainQQ.ForeColor = text; mainQQ.BorderStyle = BorderStyle.FixedSingle; mainQQ.Font = new Font("Consolas", 10.5f);
        form.Controls.Add(mainQQ);

        form.Controls.Add(MakeLabel("机器人小号 QQ（可选，扫码后自动识别可不填）", 320, top + 64, 400, 9f, true, text));
        botQQ = new TextBox(); botQQ.Left = 320; botQQ.Top = top + 90; botQQ.Width = 260; botQQ.BackColor = panel; botQQ.ForeColor = text; botQQ.BorderStyle = BorderStyle.FixedSingle; botQQ.Font = new Font("Consolas", 10.5f);
        form.Controls.Add(botQQ);

        int row2 = top + 132;
        form.Controls.Add(MakeLabel("安装目录（桥接 + 控制台）", 28, row2, 300, 9f, true, text));
        installDir = new TextBox(); installDir.Left = 28; installDir.Top = row2 + 26; installDir.Width = 360; installDir.Text = @"D:\qq-bridge"; installDir.BackColor = panel; installDir.ForeColor = text; installDir.BorderStyle = BorderStyle.FixedSingle;
        form.Controls.Add(installDir);

        form.Controls.Add(MakeLabel("SnowLuma 目录", 420, row2, 300, 9f, true, text));
        snowDir = new TextBox(); snowDir.Left = 420; snowDir.Top = row2 + 26; snowDir.Width = 300; snowDir.Text = @"D:\SnowLuma"; snowDir.BackColor = panel; snowDir.ForeColor = text; snowDir.BorderStyle = BorderStyle.FixedSingle;
        form.Controls.Add(snowDir);

        int row3 = row2 + 68;
        chkDsh = new CheckBox(); chkDsh.Text = "DSH 已安装并完成初始化/登录"; chkDsh.Left = 28; chkDsh.Top = row3; chkDsh.Width = 310; chkDsh.ForeColor = text; chkDsh.BackColor = Color.Transparent; chkDsh.Checked = true;
        form.Controls.Add(chkDsh);

        chkSnow = new CheckBox(); chkSnow.Text = "SnowLuma 已启动并扫码登录"; chkSnow.Left = 350; chkSnow.Top = row3; chkSnow.Width = 330; chkSnow.ForeColor = text; chkSnow.BackColor = Color.Transparent; chkSnow.Checked = true;
        form.Controls.Add(chkSnow);

        chkComfy = new CheckBox(); chkComfy.Text = "额外安装 ComfyUI 画图（约 4GB 下载，可稍后加）"; chkComfy.Left = 28; chkComfy.Top = row3 + 26; chkComfy.Width = 520; chkComfy.ForeColor = muted; chkComfy.BackColor = Color.Transparent;
        form.Controls.Add(chkComfy);

        Button btnDshPage = MakeButton("下载 DSH", 560, row3 - 4, 90, 28, panel, text);
        btnDshPage.Click += (s, e) => OpenUrl("https://deepseek-harness.github.io/");
        form.Controls.Add(btnDshPage);
        Button btnSnowPage = MakeButton("下载 SnowLuma", 660, row3 - 4, 120, 28, panel, text);
        btnSnowPage.Click += (s, e) => OpenUrl("https://github.com/SnowLuma/SnowLuma/releases/latest");
        form.Controls.Add(btnSnowPage);

        btnStart = MakeButton("▶ 开始部署", 28, row3 + 62, 200, 42, green, Color.FromArgb(5, 46, 34));
        btnStart.Font = new Font("Microsoft YaHei UI", 10.5f, FontStyle.Bold);
        btnStart.Click += (s, e) => StartDeploy();
        form.Controls.Add(btnStart);

        status = MakeLabel("准备就绪", 250, row3 + 72, 620, 9.5f, false, muted);
        form.Controls.Add(status);

        bar = new ProgressBar(); bar.Left = 28; bar.Top = row3 + 112; bar.Width = 844; bar.Height = 6;
        bar.Style = ProgressBarStyle.Marquee; bar.MarqueeAnimationSpeed = 0; bar.Visible = false;
        form.Controls.Add(bar);

        logBox = new TextBox();
        logBox.Multiline = true; logBox.ScrollBars = ScrollBars.Vertical; logBox.ReadOnly = true;
        logBox.Left = 28; logBox.Top = row3 + 128; logBox.Width = 844; logBox.Height = 280;
        logBox.BackColor = Color.FromArgb(10, 12, 16); logBox.ForeColor = Color.FromArgb(183, 194, 208);
        logBox.Font = new Font("Consolas", 9.5f); logBox.BorderStyle = BorderStyle.FixedSingle;
        form.Controls.Add(logBox);

        btnOpenLog = MakeButton("打开日志文件", 28, row3 + 418, 130, 30, panel, muted); btnOpenLog.Visible = false;
        btnOpenLog.Click += (s, e) => OpenFile(Path.Combine(kitDir, "install.log"));
        form.Controls.Add(btnOpenLog);

        btnOpenReport = MakeButton("部署报告", 168, row3 + 418, 110, 30, panel, muted); btnOpenReport.Visible = false;
        btnOpenReport.Click += (s, e) => OpenFile(Path.Combine(installDir.Text, "部署完成报告.md"));
        form.Controls.Add(btnOpenReport);

        btnOpenAi = MakeButton("给 AI 的指令", 288, row3 + 418, 120, 30, panel, muted); btnOpenAi.Visible = false;
        btnOpenAi.Click += (s, e) => OpenFile(Path.Combine(installDir.Text, "docs", "给AI的安装指令.md"));
        form.Controls.Add(btnOpenAi);

        btnOpenApp = MakeButton("打开小肥鱼喵", 418, row3 + 418, 140, 30, Color.FromArgb(46, 100, 170), Color.White); btnOpenApp.Visible = false;
        btnOpenApp.Click += (s, e) => { try { Process.Start(Path.Combine(installDir.Text, "app", "小肥鱼喵.exe")); } catch { } };
        form.Controls.Add(btnOpenApp);

        btnClose = MakeButton("关闭", 742, row3 + 418, 130, 30, panel, muted);
        btnClose.Click += (s, e) => { if (!running) form.Close(); };
        form.Controls.Add(btnClose);
    }

    static Button MakeButton(string text, int x, int y, int w, int h, Color back, Color fore)
    {
        Button b = new Button();
        b.Text = text; b.Left = x; b.Top = y; b.Width = w; b.Height = h;
        b.BackColor = back; b.ForeColor = fore; b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderSize = 0;
        b.Font = new Font("Microsoft YaHei UI", 9f);
        return b;
    }

    static void OpenUrl(string url) { try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { } }
    static void OpenFile(string path) { try { if (File.Exists(path)) Process.Start(new ProcessStartInfo("notepad.exe", "\"" + path + "\"") { UseShellExecute = false }); } catch { } }

    static void Log(string line)
    {
        if (logBox.InvokeRequired)
        {
            logBox.BeginInvoke(new Action(() => Log(line)));
            return;
        }
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
        success = false;
        btnStart.Enabled = false;
        chkComfy.Enabled = false;
        chkDsh.Enabled = false;
        chkSnow.Enabled = false;
        chkAgree.Enabled = false;
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
            success = true;
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

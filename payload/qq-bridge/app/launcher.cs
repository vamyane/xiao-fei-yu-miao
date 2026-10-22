using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Threading;

class Program
{
    const int Port = 5210;
    const string NodeExe = @"C:\Program Files\nodejs\node.exe";
    const string ServerJs = @"D:\qq-bridge\app\server.mjs";
    const string EdgeExe = @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe";
    const string Url = "http://127.0.0.1:5210";

    static bool Probe()
    {
        try
        {
            using (var client = new TcpClient())
            {
                var ar = client.BeginConnect("127.0.0.1", Port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(400)) return false;
                client.EndConnect(ar);
                return true;
            }
        }
        catch { return false; }
    }

    static void Main()
    {
        if (!Probe())
        {
            try
            {
                var psi = new ProcessStartInfo(NodeExe, "\"" + ServerJs + "\"");
                psi.WorkingDirectory = Path.GetDirectoryName(ServerJs);
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                System.Windows.Forms.MessageBox.Show("后台服务启动失败：" + ex.Message, "小肥鱼喵", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
                return;
            }
            for (int i = 0; i < 80 && !Probe(); i++) Thread.Sleep(200);
        }

        if (File.Exists(EdgeExe))
        {
            var psi = new ProcessStartInfo(EdgeExe, "--app=" + Url + " --window-size=1120,820 --window-position=110,60");
            psi.UseShellExecute = false;
            try { Process.Start(psi); return; } catch { }
        }
        Process.Start(new ProcessStartInfo("cmd.exe", "/c start " + Url) { CreateNoWindow = true, UseShellExecute = false });
    }
}


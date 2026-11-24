# Codex 置顶叠窗（透明背景，跟随对话 / 前台显示 / 开机自启）
param([switch]$AutoStart, [switch]$NoFollow, [switch]$ForceShow)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$cs = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class CodexHud : Form
{
    public string Model = "Codex";
    public string Speed = "";
    public string Tokens = "";
    public string Cache = "";
    public double Pct = 0;
    public bool FixedPos = false;
    public bool Veil = true;

    private Font fModel = new Font("Segoe UI", 18f, FontStyle.Bold, GraphicsUnit.Pixel);
    private Font fText = new Font("Segoe UI", 18f, FontStyle.Regular, GraphicsUnit.Pixel);
    private Font fSmall = new Font("Segoe UI", 14f, FontStyle.Regular, GraphicsUnit.Pixel);
    private StringFormat sf = StringFormat.GenericTypographic;

    private Color cText = Color.FromArgb(238, 241, 248);
    private Color cMuted = Color.FromArgb(196, 205, 220);
    private Color cAccent = Color.FromArgb(110, 168, 254);
    private Color cGreen = Color.FromArgb(87, 211, 140);
    private Color cFaint = Color.FromArgb(150, 160, 180);
    private Color cShadow = Color.FromArgb(170, 0, 0, 0);

    private bool dragging = false;
    private Point dragStart;
    private Point locStart;
    private bool resizing = false;

    public CodexHud()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        ShowInTaskbar = false;
        AutoScaleMode = AutoScaleMode.None;
        Width = 700;
        Height = 46;
        DoubleBuffered = true;
        SetStyle(ControlStyles.Opaque, true);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00080000; // WS_EX_LAYERED
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            return cp;
        }
    }

    protected override void OnPaintBackground(PaintEventArgs e) { }
    protected override void OnPaint(PaintEventArgs e) { }

    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Render(); }
    protected override void OnResize(EventArgs e) { base.OnResize(e); if (!resizing) Render(); }
    protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); if (Visible) Render(); }
    protected override void OnLocationChanged(EventArgs e) { base.OnLocationChanged(e); if (IsHandleCreated) Render(); }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left && !FixedPos)
        {
            dragging = true;
            dragStart = Cursor.Position;
            locStart = Location;
            Capture = true;
        }
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (dragging)
        {
            Point cur = Cursor.Position;
            Location = new Point(locStart.X + cur.X - dragStart.X, locStart.Y + cur.Y - dragStart.Y);
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (dragging)
        {
            dragging = false;
            Capture = false;
        }
        if (e.Button == MouseButtons.Right && ContextMenuStrip != null)
        {
            ContextMenuStrip.Show(Cursor.Position);
        }
        base.OnMouseUp(e);
    }

    public void Render()
    {
        if (!IsHandleCreated || Width <= 0 || Height <= 0) return;

        int desired = MeasureDesiredWidth();
        if (desired != Width)
        {
            resizing = true;
            Width = desired;
            resizing = false;
        }

        using (Bitmap bmp = new Bitmap(Width, Height, PixelFormat.Format32bppArgb))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.Clear(Color.Transparent);
                DrawContent(g);
            }
            Push(bmp);
        }
    }

    private static GraphicsPath Rounded(Rectangle r, float rad)
    {
        GraphicsPath p = new GraphicsPath();
        float d = rad * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    private static float TW(Graphics g, string s, Font f)
    {
        if (string.IsNullOrEmpty(s)) return 0f;
        return g.MeasureString(s, f, PointF.Empty, StringFormat.GenericTypographic).Width;
    }

    private int MeasureDesiredWidth()
    {
        using (Bitmap m = new Bitmap(1, 1))
        using (Graphics g = Graphics.FromImage(m))
        {
            float x = 10 + 16 + 16;
            x += TW(g, Model, fModel) + 12 + 13;
            if (!string.IsNullOrEmpty(Speed)) x += TW(g, Speed, fText) + 12 + 13;
            if (!string.IsNullOrEmpty(Tokens))
                x += TW(g, Tokens, fText) + 10 + TW(g, "·", fText) + 10 + TW(g, Cache, fText) + 12 + 13;
            string pctText = Pct > 0 ? ((int)Math.Round(Pct)).ToString() + "%" : "—";
            x += 18 + 7 + TW(g, pctText, fText);
            x += 14 + TW(g, "Codex", fSmall) + 12;
            int w = (int)Math.Ceiling(x);
            if (w < 240) w = 240;
            if (w > 1800) w = 1800;
            return w;
        }
    }

    private void DrawContent(Graphics g)
    {
        if (Veil)
        {
            using (GraphicsPath path = Rounded(new Rectangle(0, 0, Width - 1, Height - 1), Height / 2f))
            using (SolidBrush bg = new SolidBrush(Color.FromArgb(128, 16, 19, 26)))
            using (Pen border = new Pen(Color.FromArgb(80, 90, 102, 124)))
            {
                g.FillPath(bg, path);
                g.DrawPath(border, path);
            }
        }

        int cy = Height / 2;
        int x = 10;

        using (Pen grip = new Pen(Color.FromArgb(120, 205, 214, 228), 1.5f))
        {
            g.DrawLine(grip, x, cy - 4, x + 8, cy - 4);
            g.DrawLine(grip, x, cy, x + 8, cy);
            g.DrawLine(grip, x, cy + 4, x + 8, cy + 4);
        }
        x += 16;

        using (SolidBrush dot = new SolidBrush(cAccent)) g.FillEllipse(dot, x, cy - 4, 8, 8);
        x += 16;

        x = Draw(g, Model, fModel, x, cy, cText) + 12;
        x = Sep(g, x, cy) + 12;

        if (!string.IsNullOrEmpty(Speed))
        {
            x = Draw(g, Speed, fText, x, cy, cMuted) + 12;
            x = Sep(g, x, cy) + 12;
        }

        if (!string.IsNullOrEmpty(Tokens))
        {
            x = Draw(g, Tokens, fText, x, cy, cText) + 10;
            x = Draw(g, "·", fText, x, cy, cMuted) + 10;
            x = Draw(g, Cache, fText, x, cy, cGreen) + 12;
            x = Sep(g, x, cy) + 12;
        }

        int d = 18;
        Rectangle ring = new Rectangle(x, cy - d / 2, d, d);
        using (Pen track = new Pen(Color.FromArgb(120, 130, 150), 2.5f)) g.DrawEllipse(track, ring);
        if (Pct > 0)
        {
            float sweep = (float)Math.Min(100.0, Math.Max(0.0, Pct)) * 3.6f;
            using (Pen arc = new Pen(cAccent, 2.5f))
            {
                arc.StartCap = LineCap.Round;
                arc.EndCap = LineCap.Round;
                g.DrawArc(arc, ring, -90f, sweep);
            }
        }
        x += d + 7;
        string pctText = Pct > 0 ? ((int)Math.Round(Pct)).ToString() + "%" : "—";
        x = Draw(g, pctText, fText, x, cy, cAccent);

        SizeF tag = g.MeasureString("Codex", fSmall);
        Draw(g, "Codex", fSmall, Width - (int)tag.Width - 12, cy, cFaint);
    }

    private int Draw(Graphics g, string s, Font f, int x, int cy, Color c)
    {
        SizeF sz = g.MeasureString(s, f, PointF.Empty, sf);
        float y = cy - sz.Height / 2f;
        using (SolidBrush sh = new SolidBrush(cShadow)) g.DrawString(s, f, sh, x + 1, y + 1, sf);
        using (SolidBrush br = new SolidBrush(c)) g.DrawString(s, f, br, x, y, sf);
        return x + (int)Math.Ceiling(sz.Width);
    }

    private int Sep(Graphics g, int x, int cy)
    {
        using (Pen p = new Pen(Color.FromArgb(90, 160, 175, 200), 1f)) g.DrawLine(p, x, cy - 8, x, cy + 8);
        return x + 1;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE { public int cx; public int cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct BLENDFUNCTION { public byte BlendOp; public byte BlendFlags; public byte SourceConstantAlpha; public byte AlphaFormat; }

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

    private void Push(Bitmap bmp)
    {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = IntPtr.Zero;
        IntPtr oldBmp = IntPtr.Zero;
        try
        {
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            oldBmp = SelectObject(memDc, hBmp);
            POINT ptDst = new POINT { X = Left, Y = Top };
            SIZE size = new SIZE { cx = bmp.Width, cy = bmp.Height };
            POINT ptSrc = new POINT { X = 0, Y = 0 };
            BLENDFUNCTION bf = new BLENDFUNCTION { BlendOp = 0, BlendFlags = 0, SourceConstantAlpha = 255, AlphaFormat = 1 };
            UpdateLayeredWindow(Handle, screenDc, ref ptDst, ref size, memDc, ref ptSrc, 0, ref bf, 2);
        }
        finally
        {
            if (oldBmp != IntPtr.Zero) SelectObject(memDc, oldBmp);
            if (hBmp != IntPtr.Zero) DeleteObject(hBmp);
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}

public class Win32
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
'@

Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing, System
try { [Win32]::SetProcessDPIAware() | Out-Null } catch {}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Version = '1.0.1'
$pidFile = Join-Path $here 'overlay.pid'
$settingsFile = Join-Path $here 'overlay.json'
$logFile = Join-Path $here 'overlay.log'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName = 'CodexHud'

# single instance
if (Test-Path -LiteralPath $pidFile) {
    $oldPid = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { exit }
}

# rotate a bloated log
if (Test-Path -LiteralPath $logFile) {
    try { if ((Get-Item -LiteralPath $logFile).Length -gt 2MB) { Remove-Item -LiteralPath $logFile -Force } } catch {}
}

Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

$settings = @{ x = $null; y = $null; fixed = $false; follow = $false; startup = $true; veil = $true }
if (Test-Path -LiteralPath $settingsFile) {
    try {
        $loaded = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $loaded.x) { $settings.x = [int]$loaded.x }
        if ($null -ne $loaded.y) { $settings.y = [int]$loaded.y }
        if ($null -ne $loaded.fixed) { $settings.fixed = [bool]$loaded.fixed }
        if ($null -ne $loaded.follow) { $settings.follow = [bool]$loaded.follow }
        if ($null -ne $loaded.startup) { $settings.startup = [bool]$loaded.startup }
        if ($null -ne $loaded.veil) { $settings.veil = [bool]$loaded.veil }
    } catch {}
}

function Save-Settings {
    try {
        $obj = [pscustomobject]@{
            x = $form.Left; y = $form.Top
            fixed = [bool]$miFixed.Checked
            follow = [bool]$miFollow.Checked
            startup = [bool]$miStartup.Checked
            veil = [bool]$miVeil.Checked
        }
        $obj | ConvertTo-Json -Compress | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    } catch {}
}

$form = New-Object CodexHud
$form.FixedPos = $settings.fixed
$form.Veil = $settings.veil

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$script:menuOpen = $false
$script:sawChat = $false
$menu.Add_Opened({ $script:menuOpen = $true })
$menu.Add_Closed({ $script:menuOpen = $false })
$miFixed = New-Object System.Windows.Forms.ToolStripMenuItem '固定位置'
$miFixed.CheckOnClick = $true
$miFixed.Checked = $settings.fixed
$miFollow = New-Object System.Windows.Forms.ToolStripMenuItem '跟随 Codex 窗口'
$miFollow.CheckOnClick = $true
$miFollow.Checked = $settings.follow
$miVeil = New-Object System.Windows.Forms.ToolStripMenuItem '半透明背景'
$miVeil.CheckOnClick = $true
$miVeil.Checked = $settings.veil
$miStartup = New-Object System.Windows.Forms.ToolStripMenuItem '开机自启（与 ChatGPT 一起）'
$miStartup.CheckOnClick = $true
$miStartup.Checked = $true
$miRefresh = New-Object System.Windows.Forms.ToolStripMenuItem '立即刷新'
$miDashboard = New-Object System.Windows.Forms.ToolStripMenuItem '打开统计看板'
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem '退出'
$menu.Items.Add($miFixed) | Out-Null
$menu.Items.Add($miFollow) | Out-Null
$menu.Items.Add($miVeil) | Out-Null
$menu.Items.Add($miStartup) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add($miRefresh) | Out-Null
$menu.Items.Add($miDashboard) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add($miExit) | Out-Null
$form.ContextMenuStrip = $menu

function Get-RunEntry { Get-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue }
$miStartup.Checked = [bool](Get-RunEntry)

function Set-Startup([bool]$on) {
    try {
        if ($on) {
            $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $here 'overlay.ps1') + '" -AutoStart'
            Set-ItemProperty -Path $runKey -Name $runName -Value $cmd
        } else {
            Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Fmt-Tok([double]$n) {
    if ($n -ge 1e6) { return ('{0:0.0}M' -f ($n / 1e6)) }
    if ($n -ge 1e4) { return ('{0:0.0}k' -f ($n / 1e3)) }
    return ('{0:N0}' -f $n)
}

function Get-ActiveThreadId {
    $p = Join-Path $env:USERPROFILE '.codex\.codex-global-state.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    $st = $j.'electron-persisted-atom-state'
    if (-not $st) { return $null }
    $tabs = $st.'settings-workspace-tabs-v1'
    if (-not $tabs) { return $null }
    $cid = $null
    foreach ($prop in $tabs.PSObject.Properties) {
        $v = $prop.Value
        if ($v -and $v.clientThreadId) { $cid = [string]$v.clientThreadId; break }
    }
    if (-not $cid) { return $null }
    if ($cid -match '^local:(.+)$') { return $Matches[1] }
    if ($cid -match '^client-new-thread:') {
        foreach ($op in $j.PSObject.Properties) {
            if ($op.Name -like 'electron-owner-atoms:*') {
                $bind = $op.Value.'client-thread-bindings-v1'
                if ($bind) {
                    $hit = $bind.PSObject.Properties[$cid]
                    if ($hit -and $hit.Value) { return [string]$hit.Value }
                }
            }
        }
        return 'draft'
    }
    return $null
}

function Get-SessionFile([string]$id) {
    if (-not $id -or $id -eq 'draft') { return $null }
    $dir = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -Recurse -Filter ('*' + $id + '*.jsonl') -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-LatestSession {
    $dir = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Read-Stats([string]$file) {
    if (-not $file) { return $null }
    $len = (Get-Item -LiteralPath $file).Length
    $read = [int][Math]::Min(1048576, $len)
    $buf = New-Object byte[] $read
    $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
    try {
        [void]$fs.Seek($len - $read, 'Begin')
        $got = 0
        while ($got -lt $read) {
            $n = $fs.Read($buf, $got, $read - $got)
            if ($n -le 0) { break }
            $got += $n
        }
    } finally {
        $fs.Dispose()
    }

    $text = [Text.Encoding]::UTF8.GetString($buf, 0, $got)
    $lines = $text -split "`n"

    $records = New-Object System.Collections.ArrayList
    $thread = $null
    $window = 0
    $model = ''

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ($line -like '*"token_usage_record"*') {
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.payload -and $o.payload.usage) {
                [void]$records.Add([pscustomobject]@{
                    ts     = $o.timestamp
                    usage  = $o.payload.usage
                    thread = $o.payload.thread_token_usage
                })
                if ($null -eq $thread -and $o.payload.thread_token_usage) { $thread = $o.payload.thread_token_usage }
            }
            if ($records.Count -ge 8 -and $window -gt 0 -and $model) { break }
        } elseif ($line -like '*"token_count"*') {
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.payload.info.model_context_window -gt 0) { $window = [int]$o.payload.info.model_context_window }
        } elseif ($line -like '*"turn_context"*') {
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.payload.model) { $model = [string]$o.payload.model }
            if ($records.Count -ge 8 -and $window -gt 0 -and $model) { break }
        }
    }

    if ($records.Count -eq 0) { return $null }

    $latest = $records[0]
    $u = $latest.usage
    $th = $thread
    if (-not $th) { $th = $u }

    $total = [double]$th.total_tokens
    if ($total -le 0) { $total = [double]$th.input_tokens + [double]$th.output_tokens }
    $inp = [double]$th.input_tokens
    $cached = [double]$th.cached_input_tokens
    $cachePct = if ($inp -gt 0) { [Math]::Round(100.0 * $cached / $inp) } else { 0 }

    $ctxPct = 0.0
    if ($window -gt 0) { $ctxPct = 100.0 * [double]$u.input_tokens / $window }

    $speed = 0.0
    $n = [Math]::Min($records.Count, 6)
    if ($n -ge 2) {
        try {
            $tNew = [DateTimeOffset]::Parse($records[0].ts).ToUnixTimeMilliseconds()
            $tOld = [DateTimeOffset]::Parse($records[$n - 1].ts).ToUnixTimeMilliseconds()
            $dt = ($tNew - $tOld) / 1000.0
            if ($dt -ge 1.0) {
                $sum = 0.0
                for ($k = 0; $k -lt $n; $k++) { $sum += [double]$records[$k].usage.output_tokens }
                $speed = $sum / $dt
            }
        } catch {}
    }

    if (-not $model) { $model = 'Codex' }

    return [pscustomobject]@{
        Model = $model
        Speed = $speed
        Total = $total
        Cache = $cachePct
        Ctx   = $ctxPct
    }
}

try { Add-Type -AssemblyName System.Runtime.WindowsRuntime } catch {}

$script:asTaskGeneric = $null
function Get-AsTaskGeneric {
    if (-not $script:asTaskGeneric) {
        $script:asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
    }
    return $script:asTaskGeneric
}

function Await($op, [Type]$type) {
    $g = Get-AsTaskGeneric
    $task = $g.MakeGenericMethod($type).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

$script:ocrEngine = $null
function Log([string]$m) {
    try {
        Add-Content -LiteralPath (Join-Path $here 'overlay.log') -Value ((Get-Date).ToString('HH:mm:ss') + ' ' + $m) -Encoding UTF8
    } catch {}
}
function Init-Ocr {
    if ($script:ocrEngine) { return }
    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
    [Windows.Media.Ocr.OcrEngine, Windows.Media, ContentType = WindowsRuntime] | Out-Null
    $script:ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
}

function Get-HeaderTitle {
    try {
        Init-Ocr
        if (-not $script:ocrEngine) { return $null }
        $p = Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Select-Object -First 1
        if (-not $p) { return $null }
        $r = New-Object Win32+RECT
        if (-not [Win32]::GetWindowRect($p.MainWindowHandle, [ref]$r)) { return $null }
        $w = $r.Right - $r.Left
        $h = $r.Bottom - $r.Top
        if ($w -lt 400 -or $h -lt 300) { return $null }
        $x = [int]($w * 0.20)
        $y = [int]($h * 0.04)
        $cw = [int]($w * 0.22)
        $ch = [int]($h * 0.06)
        $win = New-Object System.Drawing.Bitmap $w, $h
        $gw = [System.Drawing.Graphics]::FromImage($win)
        $hdc = $gw.GetHdc()
        [void][Win32]::PrintWindow($p.MainWindowHandle, $hdc, 2)
        $gw.ReleaseHdc($hdc)
        $gw.Dispose()
        $bmp = New-Object System.Drawing.Bitmap $cw, $ch
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.DrawImage($win, (New-Object System.Drawing.Rectangle 0, 0, $cw, $ch), (New-Object System.Drawing.Rectangle $x, $y, $cw, $ch), [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $win.Dispose()
        $tmp = Join-Path $env:TEMP 'codex-hud-ocr.png'
        $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()

        $bytes = [IO.File]::ReadAllBytes($tmp)
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $hash = [BitConverter]::ToString($sha.ComputeHash($bytes))
        $sha.Dispose()
        if ($script:lastOcrHash -eq $hash -and $script:lastOcrText) { return $script:lastOcrText }

        $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmp)) ([Windows.Storage.StorageFile])
        $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $sb = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $res = Await ($script:ocrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
        $script:lastOcrHash = $hash
        $script:lastOcrText = $res.Text
        Log ('ocr=[' + $res.Text + ']')
        return $res.Text
    } catch {
        Log ('ocr-fail: ' + $_.Exception.Message)
        return $null
    }
}

$script:idxCache = $null
$script:idxAt = [DateTime]::MinValue
$script:lastId = $null
$script:lastOcrHash = $null
$script:lastOcrText = $null
$script:lastLogKey = $null
$script:lastState = $null
function Get-ThreadIndex {
    if ($script:idxCache -and ((Get-Date) - $script:idxAt).TotalSeconds -lt 60) { return $script:idxCache }
    $path = Join-Path $env:USERPROFILE '.codex\session_index.jsonl'
    $list = @()
    if (Test-Path -LiteralPath $path) {
        try {
            foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) {
                if (-not $line.Trim()) { continue }
                try {
                    $o = $line | ConvertFrom-Json
                    if ($o.id -and $o.thread_name) {
                        $list += [pscustomobject]@{ id = [string]$o.id; name = [string]$o.thread_name; updated = [string]$o.updated_at }
                    }
                } catch {}
            }
        } catch {}
    }
    $script:idxCache = $list
    $script:idxAt = Get-Date
    return $list
}

function Normalize-Text([string]$s) {
    return ($s -replace '[\s\u3000]+', '')
}

function Get-Bigrams([string]$s) {
    $d = @{}
    if ($s.Length -lt 2) { return $d }
    for ($i = 0; $i -lt $s.Length - 1; $i++) { $d[$s.Substring($i, 2)] = 1 }
    return $d
}

function Get-Dice([string]$a, [string]$b) {
    $ba = Get-Bigrams $a
    $bb = Get-Bigrams $b
    $ca = $ba.Count
    $cb = $bb.Count
    if ($ca -eq 0 -or $cb -eq 0) { return 0.0 }
    $common = 0
    foreach ($k in $ba.Keys) { if ($bb.ContainsKey($k)) { $common++ } }
    return (2.0 * $common) / ($ca + $cb)
}

function Get-ActiveThreadIdByTitle {
    $text = Get-HeaderTitle
    if (-not $text) { return $null }
    $norm = Normalize-Text $text
    if ($norm.Length -lt 2) { return $null }
    $best = $null
    $bestScore = 0.0
    foreach ($e in Get-ThreadIndex) {
        $n = Normalize-Text $e.name
        if ($n.Length -lt 2) { continue }
        $score = Get-Dice $norm $n
        if ($norm.Contains($n) -or $n.Contains($norm)) { $score = 1.0 }
        if ($score -gt $bestScore) {
            $best = $e
            $bestScore = $score
        }
    }
    if ($best -and $bestScore -ge 0.55) {
        return [string]$best.id
    }
    return $null
}

function Get-ChatState {    $procs = Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue
    if (-not $procs) { return 'none' }
    $win = $procs | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $win) { return 'hidden' }
    if ([Win32]::IsIconic($win.MainWindowHandle)) { return 'hidden' }
    $fg = [Win32]::GetForegroundWindow()
    $fgPid = [uint32]0
    [void][Win32]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $fgProc = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
    if ($fgPid -eq $PID) { return 'foreground' }
    if ($fgProc -and $fgProc.ProcessName -eq 'ChatGPT') { return 'foreground' }
    return 'background'
}

function Move-Follow {
    $p = Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
    if (-not $p) { return }
    if ([Win32]::IsIconic($p.MainWindowHandle)) { return }
    $r = New-Object Win32+RECT
    if (-not [Win32]::GetWindowRect($p.MainWindowHandle, [ref]$r)) { return }
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top
    if ($w -le 200 -or $h -le 200) { return }
    $x = $r.Right - $form.Width - 24
    $y = $r.Top + 48
    if ($y -lt $r.Top) { $y = $r.Top + 48 }
    $form.Location = New-Object System.Drawing.Point($x, $y)
}

function Update-Hud {
    $state = 'none'
    try { $state = Get-ChatState } catch { $state = 'none' }

    if ($state -ne 'none') { $script:sawChat = $true }
    if ($state -ne $script:lastState) { Log ('state=' + $state); $script:lastState = $state }

    if ($state -eq 'none') {
        if ($script:sawChat) {
            if ($timer) { $timer.Stop() }
            $form.Close()
        } else {
            if ($form.Visible) { $form.Hide() }
        }
        return
    }

    $show = $ForceShow -or ($state -eq 'foreground') -or $script:menuOpen
    if ($show) {
        if (-not $form.Visible) { $form.Show() }
    } else {
        if ($form.Visible) { $form.Hide() }
    }

    if (-not $show) { return }

    $id = $null
    if (-not $script:menuOpen) {
        try { $id = Get-ActiveThreadIdByTitle } catch {}
        if ($id) { $script:lastId = $id }
    }
    if (-not $id -and $script:lastId) { $id = $script:lastId }
    if (-not $id) { try { $id = Get-ActiveThreadId } catch {} }
    $f = $null
    if ($id -and $id -ne 'draft') { $f = Get-SessionFile $id }
    if (-not $f) { $f = Get-LatestSession }

    if (-not $f) {
        $form.Model = '等待消息'
        $form.Speed = ''
        $form.Tokens = ''
        $form.Cache = ''
        $form.Pct = 0
        $form.Render()
        return
    }

    $s = $null
    try { $s = Read-Stats $f.FullName } catch { $s = $null }

    if ($null -eq $s) {
        $form.Model = 'Codex'
        $form.Speed = '等待会话'
        $form.Tokens = ''
        $form.Cache = ''
        $form.Pct = 0
    } else {
        $form.Model = $s.Model
        $form.Speed = if ($s.Speed -ge 1) { ('{0:N0} tok/s' -f $s.Speed) } else { '—' }
        $form.Tokens = ('{0} tok' -f (Fmt-Tok $s.Total))
        $form.Cache = ('缓存命中 {0}%' -f $s.Cache)
        $form.Pct = $s.Ctx
    }
    if ($script:lastLogKey -ne ($id + '|' + $f.FullName)) {
        Log ('id=' + $id + ' file=' + $f.Name)
        $script:lastLogKey = $id + '|' + $f.FullName
    }
    $form.Render()

    if ($miFollow.Checked -and -not $miFixed.Checked) { Move-Follow }
}

# 初始位置
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$x = if ($null -ne $settings.x) { [int]$settings.x } else { $wa.Left + [int](($wa.Width - $form.Width) / 2) }
$y = if ($null -ne $settings.y) { [int]$settings.y } else { $wa.Top + 8 }
$form.Location = New-Object System.Drawing.Point($x, $y)

$miFixed.Add_Click({
    $form.FixedPos = $miFixed.Checked
    if ($miFixed.Checked) { $miFollow.Checked = $false }
    Save-Settings
})
$miFollow.Add_Click({ Save-Settings })
$miVeil.Add_Click({ $form.Veil = $miVeil.Checked; $form.Render(); Save-Settings })
$miStartup.Add_Click({ Set-Startup $miStartup.Checked; Save-Settings })
$miRefresh.Add_Click({ Update-Hud })
$miDashboard.Add_Click({
    $idx = Join-Path $here 'index.html'
    $upd = Join-Path $here 'update.cmd'
    if (Test-Path -LiteralPath $idx) { Start-Process -FilePath $idx }
    elseif (Test-Path -LiteralPath $upd) { Start-Process -FilePath $upd }
})
$miExit.Add_Click({
    $timer.Stop()
    Save-Settings
    $form.Close()
})
$form.Add_LocationChanged({ if ($miFixed.Checked) { Save-Settings } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    try { Update-Hud } catch {}
    try { [void][Win32]::SetWindowPos($form.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } catch {}
})
$timer.Start()

$form.Add_Shown({
    try { [void][Win32]::SetWindowPos($form.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } catch {}
})

# 等 ChatGPT 出现；不存在时保持隐藏
$context = New-Object System.Windows.Forms.ApplicationContext
$form.Add_Closed({ $context.ExitThread() })
Log ('start v' + $script:Version)
Update-Hud

[System.Windows.Forms.Application]::Run($context)

$timer.Stop()
if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }

# Codex 置顶叠窗（透明背景，跟随对话 / 前台显示 / 开机自启）
param([switch]$AutoStart, [switch]$NoFollow, [switch]$ForceShow, [switch]$CostTest)
if ($env:CODEX_HUD_FORCE_SHOW -eq '1') { $ForceShow = $true }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$cs = @'
using System;
using System.Collections.Generic;
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
    public double UiScale = 1.0;
    public Rectangle RSpeed, RCache, RContext;
    public string ClickedSegment = "";
    public int ClickedX = 0;
    public event EventHandler SegmentClick;

    private Font fModel = new Font("Segoe UI", 18f, FontStyle.Bold, GraphicsUnit.Pixel);
    private Font fText = new Font("Segoe UI", 18f, FontStyle.Regular, GraphicsUnit.Pixel);
    private Font fSmall = new Font("Segoe UI", 14f, FontStyle.Regular, GraphicsUnit.Pixel);
    private StringFormat sf = StringFormat.GenericTypographic;

    private Color cAccent = Color.FromArgb(97, 124, 183);
    private Color cShadow = Color.FromArgb(170, 0, 0, 0);

    private bool dragging = false;
    private Point dragStart;
    private Point locStart;
    private bool resizing = false;
    private Point pressPos;
    private bool moved = false;

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

    public void SetScale(double s)
    {
        if (s < 0.7) s = 0.7;
        if (s > 1.7) s = 1.7;
        UiScale = s;
        if (fModel != null) fModel.Dispose();
        if (fText != null) fText.Dispose();
        if (fSmall != null) fSmall.Dispose();
        fModel = new Font("Segoe UI", (float)(15.0 * s), FontStyle.Bold, GraphicsUnit.Pixel);
        fText = new Font("Segoe UI", (float)(15.0 * s), FontStyle.Regular, GraphicsUnit.Pixel);
        fSmall = new Font("Segoe UI", (float)(14.0 * s), FontStyle.Regular, GraphicsUnit.Pixel);
        Height = (int)Math.Round(34.0 * s);
        Render();
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

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0084) { m.Result = (IntPtr)1; return; }
        base.WndProc(ref m);
    }

    protected override void OnPaintBackground(PaintEventArgs e) { }

    public event EventHandler HoverEnter;
    public event EventHandler HoverLeave;

    protected override void OnMouseEnter(EventArgs e)
    {
        base.OnMouseEnter(e);
        if (HoverEnter != null) HoverEnter(this, e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (HoverLeave != null) HoverLeave(this, e);
    }
    protected override void OnPaint(PaintEventArgs e) { }

    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Render(); }
    protected override void OnResize(EventArgs e) { base.OnResize(e); if (!resizing) Render(); }
    protected override void OnVisibleChanged(EventArgs e) { base.OnVisibleChanged(e); if (Visible) Render(); }
    protected override void OnLocationChanged(EventArgs e)
    {
        base.OnLocationChanged(e);
        if (!IsHandleCreated) return;
        if (dragging) return;
        Render();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            pressPos = e.Location;
            moved = false;
        }
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
        if (Math.Abs(e.X - pressPos.X) > 4 || Math.Abs(e.Y - pressPos.Y) > 4) moved = true;
        if (!dragging)
        {
            bool hit = RSpeed.Contains(e.Location) || RCache.Contains(e.Location) || RContext.Contains(e.Location);
            Cursor = hit ? Cursors.Hand : Cursors.Default;
        }
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
        if (e.Button == MouseButtons.Left && !moved)
        {
            ClickedSegment = "";
            if (RSpeed.Contains(e.Location)) { ClickedSegment = "speed"; ClickedX = e.X; }
            else if (RCache.Contains(e.Location)) { ClickedSegment = "cache"; ClickedX = e.X; }
            else if (RContext.Contains(e.Location)) { ClickedSegment = "ctx"; ClickedX = e.X; }
            if (ClickedSegment != "" && SegmentClick != null) SegmentClick(this, EventArgs.Empty);
        }
        if (moved && !dragging && IsHandleCreated) Render();
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
            x += 14;
            int w = (int)Math.Ceiling(x);
            if (w < 240) w = 240;
            if (w > 1800) w = 1800;
            return w;
        }
    }

    private void DrawContent(Graphics g)
    {
        Color tText = Color.FromArgb(49, 52, 57);
        Color tMuted = Color.FromArgb(89, 94, 101);
        
        Color tGreen = tMuted;
        cShadow = Color.Transparent;

        using (GraphicsPath path = Rounded(new Rectangle(0, 0, Width - 1, Height - 1), Height / 2f))
        using (SolidBrush bg = new SolidBrush(Veil ? Color.FromArgb(242, 247, 248, 249) : Color.FromArgb(1, 0, 0, 0)))
        using (Pen border = new Pen(Veil ? Color.FromArgb(170, 215, 218, 222) : Color.FromArgb(1, 0, 0, 0)))
        {
            g.FillPath(bg, path);
            g.DrawPath(border, path);
        }

        int cy = Height / 2;
        int x = 10;

        using (Pen grip = new Pen(Veil ? Color.FromArgb(120, 205, 214, 228) : Color.FromArgb(140, 40, 40, 45), 1.5f))
        {
            g.DrawLine(grip, x, cy - 4, x + 8, cy - 4);
            g.DrawLine(grip, x, cy, x + 8, cy);
            g.DrawLine(grip, x, cy + 4, x + 8, cy + 4);
        }
        x += 16;

        using (SolidBrush dot = new SolidBrush(cAccent)) g.FillEllipse(dot, x, cy - 4, 8, 8);
        x += 16;

        x = Draw(g, Model, fModel, x, cy, tText) + 12;
        x = Sep(g, x, cy) + 12;

        int rs = x;
        if (!string.IsNullOrEmpty(Speed))
        {
            x = Draw(g, Speed, fText, x, cy, tMuted) + 12;
            x = Sep(g, x, cy) + 12;
        }
        RSpeed = new Rectangle(rs, 0, Math.Max(1, x - rs), Height);

        int rc = x;
        if (!string.IsNullOrEmpty(Tokens))
        {
            x = Draw(g, Tokens, fText, x, cy, tText) + 10;
            x = Draw(g, "·", fText, x, cy, tMuted) + 10;
            x = Draw(g, Cache, fText, x, cy, tGreen) + 12;
            x = Sep(g, x, cy) + 12;
        }
        RCache = new Rectangle(rc, 0, Math.Max(1, x - rc), Height);

        int rx = x;
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
        RContext = new Rectangle(rx, 0, Math.Max(1, x - rx + 8), Height);

        
        
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

public class CostPopup : Form
{
    private string _title = "";
    private string[] _rows = new string[0];
    private string _foot = "";
    private string _rawTitle = "";
    private string[] _rawRows = new string[0];
    private string _kind = "default";
    private string _headerValue = "";
    private double _progress = -1.0;
    private int _fullW = 320;
    private int _fullH = 100;
    private double _anim = 1.0;
    private double _scale = 1.0;
    public bool DarkText = false;

    private Font _fText = MakeFont(16f);

    private Color cAccent = Color.FromArgb(97, 124, 183);

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] private struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

    private static Font MakeFont(float px)
    {
        Font f = null;
        try { f = new Font("Segoe UI Variable Text Semibold", px, FontStyle.Regular, GraphicsUnit.Pixel); } catch {}
        if (f == null || f.Name != "Segoe UI Variable Text Semibold")
        {
            if (f != null) f.Dispose();
            f = new Font("Segoe UI", px, FontStyle.Bold, GraphicsUnit.Pixel);
        }
        return f;
    }

    // Receive mouse button events only while the card is open. Windows still
    // delivers the original click to the control under the pointer.
    [StructLayout(LayoutKind.Sequential)] private struct RawDevice {
        public ushort Page, Usage;
        public uint Flags;
        public IntPtr Target;
    }
    [DllImport("user32.dll")] private static extern bool RegisterRawInputDevices(RawDevice[] devices, uint count, uint size);
    [DllImport("user32.dll")] private static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);
    [DllImport("user32.dll")] private static extern int GetMessagePos();
    public CodexHud Hud;
    public event EventHandler OutsidePress;
    protected override void OnVisibleChanged(EventArgs e) {
        base.OnVisibleChanged(e);
        RawDevice device = new RawDevice { Page = 1, Usage = 2, Flags = Visible ? 0x100u : 1u, Target = Visible ? Handle : IntPtr.Zero };
        RegisterRawInputDevices(new RawDevice[] { device }, 1, (uint)Marshal.SizeOf(typeof(RawDevice)));
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0xff && Visible && OutsidePress != null) {
            uint header = (uint)(8 + 2 * IntPtr.Size);
            uint size = header + 24;
            IntPtr data = Marshal.AllocHGlobal((int)size);
            try {
                if (GetRawInputData(m.LParam, 0x10000003, data, ref size, header) == header + 24 && Marshal.ReadInt32(data) == 0) {
                    int buttons = Marshal.ReadInt16(data, (int)header + 4);
                    if ((buttons & 0x155) != 0) {
                        int pos = GetMessagePos();
                        Point pt = new Point((short)pos, (short)(pos >> 16));
                        bool segment = false;
                        if (Hud != null && Hud.Bounds.Contains(pt) && (buttons & 1) != 0) {
                            Point local = Hud.PointToClient(pt);
                            Rectangle speed = Hud.RSpeed, cache = Hud.RCache, context = Hud.RContext; segment = speed.Contains(local) || cache.Contains(local) || context.Contains(local);
                        }
                        if (!Bounds.Contains(pt) && !segment) OutsidePress(this, EventArgs.Empty);
                    }
                }
            } finally { Marshal.FreeHGlobal(data); }
        }
        base.WndProc(ref m);
    }

    public CostPopup()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        SetStyle(ControlStyles.Opaque, true);
        Width = 10;
        Height = 10;
    }

    public void SetScale(double s)
    {
        if (s < 0.7) s = 0.7;
        if (s > 1.7) s = 1.7;
        _scale = s;
        if (_fText != null) _fText.Dispose();
        _fText = MakeFont((float)(16.0 * s));
        SetContent(_rawTitle, _rawRows, _foot);
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00080000;
            cp.ExStyle |= 0x08000000;
            cp.ExStyle |= 0x00000080;
            return cp;
        }
    }

    private static void FillRound(Graphics g, Brush brush, Rectangle r, int radius)
    {
        using (GraphicsPath p = Rounded(r, radius)) g.FillPath(brush, p);
    }
    private static GraphicsPath Rounded(Rectangle r, int radius)
    {
        GraphicsPath p = new GraphicsPath();
        int d = radius * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public void SetContent(string title, string[] rows, string foot)
    {
        _rawTitle = _title = title ?? "";
        _rawRows = _rows = rows ?? new string[0];
        _foot = foot ?? "";
        _kind = "default";
        _headerValue = "";
        _progress = -1.0;

        if (_title.StartsWith("ctx|"))
        {
            _kind = "context";
            string[] hp = _title.Split(new [] { '|' }, 3);
            _title = hp.Length > 1 ? hp[1] : "上下文已用";
            _headerValue = hp.Length > 2 ? hp[2] : "";
            if (_rows.Length > 0)
            {
                string[] pp = _rows[0].Split(new [] { '|' }, 3);
                if (pp.Length > 1) double.TryParse(pp[1], out _progress);
                if (pp.Length > 2 && String.IsNullOrEmpty(_headerValue)) _headerValue = pp[2];
                string[] rest = new string[Math.Max(0, _rows.Length - 1)];
                for (int i = 1; i < _rows.Length; i++) rest[i - 1] = _rows[i];
                _rows = rest;
            }
        }
        else
        {
            string[] hp = _title.Split(new [] { '|' }, 2);
            if (hp.Length == 2) { _title = hp[0]; _headerValue = hp[1]; }
        }

        int rowHeight = (int)Math.Round(34.0 * _scale);
        int top = (int)Math.Round(62.0 * _scale);
        int bottom = (int)Math.Round(18.0 * _scale);
        int width = (int)Math.Round((_kind == "context" ? 440.0 : 454.0) * _scale);
        _fullW = width;
        _fullH = top + _rows.Length * rowHeight + bottom;
        if (_kind == "context") _fullH += (int)Math.Round(42.0 * _scale);
        if (_fullH < (int)Math.Round(130.0 * _scale)) _fullH = (int)Math.Round(130.0 * _scale);
        Render();
    }
    public void SetAnim(double t)
    {
        _anim = Math.Max(0.02, Math.Min(1.0, t));
        Render();
    }

    private void Render()
    {
        int w = _fullW;
        int fullH = _fullH;
        int h = Math.Max(2, (int)Math.Round(fullH * _anim));
        if (Width != w || Height != h) Size = new Size(w, h);
        using (Bitmap bmp = new Bitmap(w, h))
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.Clear(Color.Transparent);
            Color panel = DarkText ? Color.FromArgb(250, 255, 255, 255) : Color.FromArgb(245, 255, 255, 255);
            Color borderColor = Color.FromArgb(225, 229, 234);
            Color text = Color.FromArgb(35, 39, 45);
            Color muted = Color.FromArgb(105, 111, 120);
            Color faint = Color.FromArgb(224, 227, 231);
            Color blue = Color.FromArgb(92, 137, 232);
            Color purple = Color.FromArgb(150, 125, 238);
            using (GraphicsPath path = Rounded(new Rectangle(0, 0, w - 1, fullH - 1), (int)Math.Round(18.0 * _scale)))
            using (SolidBrush bg = new SolidBrush(panel))
            using (Pen border = new Pen(borderColor, 1f))
            {
                g.FillPath(bg, path);
                g.DrawPath(border, path);
            }

            Font titleFont = new Font("Segoe UI", (float)(16.0 * _scale), FontStyle.Regular, GraphicsUnit.Pixel);
            Font valueFont = new Font("Segoe UI", (float)(16.0 * _scale), FontStyle.Regular, GraphicsUnit.Pixel);
            Font rowFont = new Font("Segoe UI", (float)(16.0 * _scale), FontStyle.Regular, GraphicsUnit.Pixel);
            try
            {
                int pad = (int)Math.Round(24.0 * _scale);
                int y = (int)Math.Round(18.0 * _scale);
                using (SolidBrush tb = new SolidBrush(text))
                using (SolidBrush vb = new SolidBrush(text))
                using (SolidBrush mb = new SolidBrush(muted))
                using (SolidBrush bb = new SolidBrush(blue))
                using (SolidBrush pb = new SolidBrush(purple))
                {
                    string icon = _kind == "context" ? "" : (_title == "Token 用量" ? "◉" : "◌");
                    if (!String.IsNullOrEmpty(icon))
                    {
                        g.DrawString(icon, titleFont, mb, pad, y - 1);
                        pad += (int)Math.Round(27.0 * _scale);
                    }
                    g.DrawString(_title, titleFont, tb, pad, y);
                    if (!String.IsNullOrEmpty(_headerValue))
                    {
                        SizeF vs = g.MeasureString(_headerValue, valueFont);
                        g.DrawString(_headerValue, valueFont, vb, w - (int)Math.Round(24.0 * _scale) - vs.Width, y);
                    }
                    int lineY = (int)Math.Round(51.0 * _scale);
                    using (Pen line = new Pen(faint, 1f)) g.DrawLine(line, (int)Math.Round(24.0 * _scale), lineY, w - (int)Math.Round(24.0 * _scale), lineY);
                    y = (int)Math.Round(66.0 * _scale);

                    if (_kind == "context")
                    {
                        int barX = (int)Math.Round(24.0 * _scale);
                        int barW = w - (int)Math.Round(48.0 * _scale);
                        int barH = (int)Math.Round(6.0 * _scale);
                        using (SolidBrush track = new SolidBrush(Color.FromArgb(235, 238, 241))) FillRound(g, track, new Rectangle(barX, y, barW, barH), barH / 2);
                        int fillW = (int)Math.Round(barW * Math.Max(0.0, Math.Min(100.0, _progress)) / 100.0);
                        if (fillW > 0) using (SolidBrush fill = new SolidBrush(blue)) FillRound(g, fill, new Rectangle(barX, y, fillW, barH), barH / 2);
                        y += (int)Math.Round(28.0 * _scale);
                    }

                    for (int i = 0; i < _rows.Length; i++)
                    {
                        string row = _rows[i] ?? "";
                        string label = row;
                        string right = "";
                        string[] parts = row.Split(new [] { '|' }, 2);
                        if (parts.Length == 2) { label = parts[0]; right = parts[1]; }
                        if (_kind == "context")
                        {
                            using (SolidBrush swatch = new SolidBrush(i == 0 ? Color.FromArgb(180, 178, 170) : (i == 1 ? purple : blue)))
                                g.FillRectangle(swatch, (int)Math.Round(24.0 * _scale), y + (int)Math.Round(7.0 * _scale), (int)Math.Round(10.0 * _scale), (int)Math.Round(10.0 * _scale));
                            pad = (int)Math.Round(46.0 * _scale);
                        }
                        else pad = (int)Math.Round(24.0 * _scale);
                        g.DrawString(label, rowFont, mb, pad, y);
                        if (!String.IsNullOrEmpty(right))
                        {
                            SizeF rs = g.MeasureString(right, rowFont);
                            g.DrawString(right, rowFont, mb, w - (int)Math.Round(24.0 * _scale) - rs.Width, y);
                        }
                        y += (int)Math.Round(34.0 * _scale);
                    }
                }
            }
            finally
            {
                titleFont.Dispose(); valueFont.Dispose(); rowFont.Dispose();
            }
            Push(bmp);
        }
    }
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
            byte alpha = (byte)Math.Max(20, Math.Min(255, (int)(255 * (0.35 + 0.65 * _anim))));
            BLENDFUNCTION bf = new BLENDFUNCTION { BlendOp = 0, BlendFlags = 0, SourceConstantAlpha = alpha, AlphaFormat = 1 };
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
'@

Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing, System
try { [Win32]::SetProcessDPIAware() | Out-Null } catch {}

$sqlCs = @'
using System;
using System.Runtime.InteropServices;

public class SqliteLog
{
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_open_v2(string filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_text(IntPtr stmt, int i);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern long sqlite3_column_int64(IntPtr stmt, int i);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_close(IntPtr db);

    public static string LatestResumeThread(string path, out long ts)
    {
        ts = 0;
        IntPtr db;
        if (sqlite3_open_v2(path, out db, 1, IntPtr.Zero) != 0) return null;
        try
        {
            string sql = "SELECT thread_id, ts FROM logs WHERE id > (SELECT IFNULL(MAX(id),0)-512 FROM logs) AND thread_id IS NOT NULL AND feedback_log_body LIKE '%thread/resume%' ORDER BY id DESC LIMIT 1";
            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(sql + "\0");
            IntPtr stmt;
            if (sqlite3_prepare_v2(db, bytes, bytes.Length, out stmt, IntPtr.Zero) != 0) return null;
            try
            {
                if (sqlite3_step(stmt) == 100)
                {
                    IntPtr p = sqlite3_column_text(stmt, 0);
                    if (p != IntPtr.Zero) ts = sqlite3_column_int64(stmt, 1);
                    if (p != IntPtr.Zero) return Marshal.PtrToStringAnsi(p);
                }
            }
            finally { sqlite3_finalize(stmt); }
        }
        finally { sqlite3_close(db); }
        return null;
    }

    public class ModelCharge {
        public string Model;
        public long Requests;
        public double Amount;
    }

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern double sqlite3_column_double(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_text16(IntPtr stmt, int column);

    public static ModelCharge[] SessionCharges(string path, Guid session) {
        IntPtr db, stmt = IntPtr.Zero;
        int opened = sqlite3_open_v2(path, out db, 1, IntPtr.Zero);
        try {
            if (opened != 0) throw new InvalidOperationException("CC Switch database unavailable");
            string id = session.ToString("D");
            string sql = "SELECT model, COUNT(*), SUM(CAST(total_cost_usd AS REAL)) " +
                "FROM proxy_request_logs WHERE app_type='codex' AND session_id IN ('" + id + "','codex_" + id + "') " +
                "GROUP BY model ORDER BY 3 DESC, model";
            byte[] query = System.Text.Encoding.UTF8.GetBytes(sql + "\0");
            if (sqlite3_prepare_v2(db, query, query.Length, out stmt, IntPtr.Zero) != 0)
                throw new InvalidOperationException("CC Switch billing table unavailable");
            var rows = new System.Collections.Generic.List<ModelCharge>();
            int status;
            while ((status = sqlite3_step(stmt)) == 100) {
                rows.Add(new ModelCharge { Model = Marshal.PtrToStringUni(sqlite3_column_text16(stmt, 0)),
                    Requests = sqlite3_column_int64(stmt, 1), Amount = sqlite3_column_double(stmt, 2) });
            }
            if (status != 101) throw new InvalidOperationException("CC Switch billing query interrupted");
            return rows.ToArray();
        } finally {
            if (stmt != IntPtr.Zero) sqlite3_finalize(stmt);
            if (db != IntPtr.Zero) sqlite3_close(db);
        }
    }

    public static string ThreadModel(string path, string threadId)
    {
        IntPtr db;
        if (sqlite3_open_v2(path, out db, 1, IntPtr.Zero) != 0) return null;
        try
        {
            string sql = "SELECT model FROM threads WHERE id = '" + threadId.Replace("'", "''") + "' LIMIT 1";
            byte[] bytes = System.Text.Encoding.UTF8.GetBytes(sql + "\0");
            IntPtr stmt;
            if (sqlite3_prepare_v2(db, bytes, bytes.Length, out stmt, IntPtr.Zero) != 0) return null;
            try
            {
                if (sqlite3_step(stmt) == 100)
                {
                    IntPtr p = sqlite3_column_text(stmt, 0);
                    if (p != IntPtr.Zero) return Marshal.PtrToStringAnsi(p);
                }
            }
            finally { sqlite3_finalize(stmt); }
        }
        finally { sqlite3_close(db); }
        return null;
    }
}
'@
try { Add-Type -TypeDefinition $sqlCs } catch {}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Version = '1.4.0'
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

$settings = @{ x = $null; y = $null; fixed = $false; follow = $false; startup = $true; veil = $true; scale = 1.0 }
if (Test-Path -LiteralPath $settingsFile) {
    try {
        $loaded = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $loaded.x) { $settings.x = [int]$loaded.x }
        if ($null -ne $loaded.y) { $settings.y = [int]$loaded.y }
        if ($null -ne $loaded.fixed) { $settings.fixed = [bool]$loaded.fixed }
        if ($null -ne $loaded.follow) { $settings.follow = [bool]$loaded.follow }
        if ($null -ne $loaded.startup) { $settings.startup = [bool]$loaded.startup }
        if ($null -ne $loaded.veil) { $settings.veil = [bool]$loaded.veil }
        if ($null -ne $loaded.scale) { $settings.scale = [double]$loaded.scale }
        if ($settings.scale -lt 0.7) { $settings.scale = 0.7 }
        if ($settings.scale -gt 1.7) { $settings.scale = 1.7 }
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
            scale = [double]$settings.scale
        }
        $obj | ConvertTo-Json -Compress | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    } catch {}
}

function Apply-Scale([double]$s) {
    $settings.scale = $s
    $form.SetScale($s)
    if ($script:popup) { $script:popup.SetScale($s) }
    if ($script:sizeItems) {
        foreach ($it in $script:sizeItems) {
            $it.Checked = ([Math]::Abs([double]$it.Tag - $s) -lt 0.01)
        }
    }
    Save-Settings
}

$script:priceFile = Join-Path $here 'prices.json'
if (-not (Test-Path -LiteralPath $script:priceFile)) {
    $defaultPrices = @'
{
  "currency": "$",
  "note": "Sample USD prices per 1M tokens. Edit to match your provider.",
  "default": { "input": 1.0, "cached": 0.1, "output": 4.0 },
  "models": {
    "gpt-5.5": { "input": 1.25, "cached": 0.125, "output": 10.0 },
    "gpt-5.6-sol": { "input": 1.25, "cached": 0.125, "output": 10.0 },
    "gpt-6-sol": { "input": 1.25, "cached": 0.125, "output": 10.0 },
    "gpt-6.1-sol": { "input": 1.25, "cached": 0.125, "output": 10.0 },
    "gpt-6-luna": { "input": 0.25, "cached": 0.025, "output": 2.0 },
    "gpt-6-Astra": { "input": 2.5, "cached": 0.25, "output": 15.0 },
    "gpt-6-astra": { "input": 2.5, "cached": 0.25, "output": 15.0 },
    "ccs-dp/cc/deepseek-v4.1-flash": { "input": 0.28, "cached": 0.028, "output": 0.42 },
    "ccs-dp/cc/deepseek-flash": { "input": 0.28, "cached": 0.028, "output": 0.42 },
    "ccs-dp/qwen3.8-flash": { "input": 0.15, "cached": 0.015, "output": 0.6 }
  }
}
'@
    try { [IO.File]::WriteAllText($script:priceFile, $defaultPrices, (New-Object Text.UTF8Encoding($true))) } catch {}
}

$script:priceTable = $null
$script:usageCacheKey = ''
$script:usageCache = $null
$script:rxModel = [regex]'"model":"([^"]+)"'
$script:rxIn = [regex]'"input_tokens":(\d+)'
$script:rxCached = [regex]'"cached_input_tokens":(\d+)'
$script:rxCacheWrite = [regex]'"cache_write_input_tokens":(\d+)'
$script:rxOut = [regex]'"output_tokens":(\d+)'

function Get-PriceTable {
    if ($script:priceTable) { return $script:priceTable }
    try {
        $script:priceTable = Get-Content -LiteralPath $script:priceFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $script:priceTable = [pscustomobject]@{
            currency = '$'
            default = [pscustomobject]@{ input = 1.0; cached = 0.1; output = 4.0 }
            models = [pscustomobject]@{}
        }
    }
    return $script:priceTable
}

function Get-PriceFor([string]$model) {
    $pt = Get-PriceTable
    $entry = $null
    if ($pt.models) {
        foreach ($p in $pt.models.PSObject.Properties) {
            if ($p.Name -eq $model) { $entry = $p.Value; break }
        }
        if (-not $entry) {
            foreach ($p in $pt.models.PSObject.Properties) {
                if ($model -like ('*' + $p.Name + '*') -or $p.Name -like ('*' + $model + '*')) { $entry = $p.Value; break }
            }
        }
    }
    if (-not $entry) { $entry = $pt.default }
    return $entry
}

function Get-UsageCost($u, $price) {
    $inp = [double]$u.input
    $cached = [double]$u.cached
    if ($cached -gt $inp) { $cached = $inp }
    $uncached = [double]$u.cache_write + [Math]::Max(0.0, $inp - $cached)
    return ($uncached * [double]$price.input + $cached * [double]$price.cached + [double]$u.output * [double]$price.output) / 1000000.0
}

function Read-ModelUsage([string]$file) {
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return @{} }
    $fi = Get-Item -LiteralPath $file
    $key = $file + '|' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks
    if ($script:usageCacheKey -eq $key -and $script:usageCache) { return $script:usageCache }

    $map = @{}
    $cur = ''
    try { $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite') } catch { return $map }
    $rd = New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8)
    try {
        while ($null -ne ($line = $rd.ReadLine())) {
            if ($line.Contains('"turn_context"')) {
                $m = $script:rxModel.Match($line)
                if ($m.Success) { $cur = $m.Groups[1].Value }
            } elseif ($line.Contains('"token_usage_record"')) {
                $mi = $script:rxIn.Match($line)
                if (-not $mi.Success) { continue }
                $mc = $script:rxCached.Match($line)
                $mw = $script:rxCacheWrite.Match($line)
                $mo = $script:rxOut.Match($line)
                $model = if ($cur) { $cur } else { 'unknown' }
                if (-not $map.ContainsKey($model)) {
                    $map[$model] = [pscustomobject]@{ model = $model; input = [long]0; cached = [long]0; cache_write = [long]0; output = [long]0 }
                }
                $map[$model].input += [long]$mi.Groups[1].Value
                if ($mc.Success) { $map[$model].cached += [long]$mc.Groups[1].Value }
                if ($mw.Success) { $map[$model].cache_write += [long]$mw.Groups[1].Value }
                if ($mo.Success) { $map[$model].output += [long]$mo.Groups[1].Value }
            }
        }
    } finally { $rd.Dispose() }

    $script:usageCacheKey = $key
    $script:usageCache = $map
    return $map
}

function Update-CostPopup {
    if (-not $script:activeFile) { return }
    $title = 'CC Switch · 会话费用'
    $db = Join-Path $env:USERPROFILE '.cc-switch\cc-switch.db'
    $match = [regex]::Match([IO.Path]::GetFileNameWithoutExtension($script:activeFile), '[0-9a-fA-F-]{36}$')
    $session = [Guid]::Empty
    $rows = @('当前会话暂无费用记录')
    if (-not [IO.File]::Exists($db)) {
        $rows = @('未找到 CC Switch 数据库')
    } elseif ([Guid]::TryParse($match.Value, [ref]$session)) {
        try {
            $charges = [SqliteLog]::SessionCharges($db, $session)
            if ($charges.Length -gt 0) {
                $total = ($charges | Measure-Object -Property Amount -Sum).Sum
                $title += ('|${0:N4}' -f $total)
                $rows = foreach ($charge in $charges) {
                    '{0} · {1} 次|${2:N4}' -f $charge.Model, $charge.Requests, $charge.Amount
                }
            }
        } catch { $rows = @('暂时无法读取 CC Switch 费用记录') }
    }
    $script:popup.SetContent($title, [string[]]@($rows), '')
}

function Format-Duration([double]$ms) {
    $s = [int][Math]::Round($ms / 1000.0)
    if ($s -lt 60) { return ('{0}秒' -f $s) }
    return ('{0}分{1}秒' -f [Math]::Floor($s / 60), ($s % 60))
}

$script:detailKey = ''
$script:detail = $null
function Get-SessionDetail([string]$file) {
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $null }
    $fi = Get-Item -LiteralPath $file
    $key = $file + '|' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks
    if ($script:detailKey -eq $key -and $script:detail) { return $script:detail }

    $turns = 0; $steps = 0
    $durMs = 0.0; $toolMs = 0.0
    $ttftSum = 0.0; $ttftN = 0
    $outTok = 0L; $inTok = 0L; $cachedTok = 0L; $totalTok = 0L
    $lastIn = 0L; $lastCached = 0L; $lastOut = 0L
    $window = 0
    $sysChars = 0; $toolsChars = 0
    $toolTypes = @('CommandExecution', 'McpToolCall', 'WebSearch', 'FileChange', 'PatchApply', 'ImageGeneration', 'ComputerUse', 'ToolCall')

    try { $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite') } catch { return $null }
    $rd = New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8)
    try {
        while ($null -ne ($line = $rd.ReadLine())) {
            if ($line.Contains('"task_complete"')) {
                try {
                    $o = $line | ConvertFrom-Json
                    $turns++
                    if ($o.payload.duration_ms) { $durMs += [double]$o.payload.duration_ms }
                    if ($o.payload.time_to_first_token_ms -gt 0) { $ttftSum += [double]$o.payload.time_to_first_token_ms; $ttftN++ }
                } catch {}
            } elseif ($line.Contains('"item_completed"')) {
                try {
                    $o = $line | ConvertFrom-Json
                    $steps++
                    $it = $o.payload.item
                    if ($it -and ($toolTypes -contains [string]$it.type)) {
                        $dt = [double]$o.payload.completed_at_ms - [double]$o.payload.started_at_ms
                        if ($dt -gt 0) { $toolMs += $dt }
                    }
                } catch {}
            } elseif ($line.Contains('"token_count"')) {
                try {
                    $o = $line | ConvertFrom-Json
                    $u = $o.payload.info.total_token_usage
                    if ($u) {
                        $inTok = [long]$u.input_tokens
                        $cachedTok = [long]$u.cached_input_tokens
                        $outTok = [long]$u.output_tokens
                        $totalTok = [long]$u.total_tokens
                    }
                    $lu = $o.payload.info.last_token_usage
                    if ($lu) {
                        $lastIn = [long]$lu.input_tokens
                        $lastCached = [long]$lu.cached_input_tokens
                        $lastOut = [long]$lu.output_tokens
                    }
                    if ($o.payload.info.model_context_window -gt 0) { $window = [int]$o.payload.info.model_context_window }
                } catch {}
            } elseif ($line.Contains('"world_state"')) {
                try {
                    $o = $line | ConvertFrom-Json
                    if ($o.payload.state.tools) {
                        $json = $o.payload.state.tools | ConvertTo-Json -Compress -Depth 8
                        if ($json.Length -gt $toolsChars) { $toolsChars = $json.Length }
                    }
                } catch {}
            } elseif ($line.Contains('"response_item"')) {
                try {
                    $o = $line | ConvertFrom-Json
                    $role = [string]$o.payload.role
                    if ($role -eq 'developer' -or $role -eq 'system') {
                        $len = 0
                        foreach ($c in $o.payload.content) { if ($c.text) { $len += ([string]$c.text).Length } }
                        if ($len -gt $sysChars) { $sysChars = $len }
                    }
                } catch {}
            }
        }
    } finally { $rd.Dispose() }

    $modelMs = [Math]::Max(0.0, $durMs - $toolMs)
    $tps = if ($modelMs -gt 0) { $outTok / ($modelMs / 1000.0) } else { 0.0 }
    $ttft = if ($ttftN -gt 0) { $ttftSum / $ttftN } else { 0.0 }
    $cachePct = if ($inTok -gt 0) { 100.0 * $cachedTok / $inTok } else { 0.0 }
    $used = $lastIn
    $pctCtx = if ($window -gt 0) { 100.0 * $used / $window } else { 0.0 }
    $sysTok = [long]([Math]::Round($sysChars / 4.0))
    $toolTok = [long]([Math]::Round($toolsChars / 4.0))
    $msgTok = [Math]::Max(0, $used - $sysTok - $toolTok)

    $script:detail = [pscustomobject]@{
        Turns = $turns; Steps = $steps; ModelMs = $modelMs; ToolMs = $toolMs
        TtftMs = $ttft; Tps = $tps; Output = $outTok; Input = $inTok; Cached = $cachedTok
        Total = $totalTok; Window = $window; CachePct = $cachePct; CtxPct = $pctCtx
        Used = $used; SysTok = $sysTok; ToolTok = $toolTok; MsgTok = $msgTok
        LastInput = $lastIn; LastCached = $lastCached; LastOutput = $lastOut
    }
    $script:detailKey = $key
    return $script:detail
}

function Show-InfoPopup([string]$seg) {
    if ($script:popupPinned -and $script:pinnedSeg -eq $seg) {
        Hide-CostPopup
        return
    }
    if (-not $script:activeFile) { return }
    Log ('info=' + $seg)
    $d = Get-SessionDetail $script:activeFile
    if (-not $d) { return }
    $title = ''
    $rows = New-Object System.Collections.ArrayList
    if ($seg -eq 'speed') {
        $title = ('会话统计|{0}轮 {1}步' -f $d.Turns, $d.Steps)
        [void]$rows.Add(('模型用时|{0}' -f (Format-Duration $d.ModelMs)))
        [void]$rows.Add(('工具调用用时|{0}' -f (Format-Duration $d.ToolMs)))
        [void]$rows.Add(('首 token 平均（TTFT）|{0:N1}秒' -f ($d.TtftMs / 1000.0)))
        [void]$rows.Add(('输出速度（TPS）|{0:N0} tok/s' -f $d.Tps))
    } elseif ($seg -eq 'cache') {
        $title = ('Token 用量|{0:N0} tok' -f $d.Total)
        [void]$rows.Add(('缓存命中|{0:N0}%' -f $d.CachePct))
        [void]$rows.Add(('未缓存输入|{0:N0} tok' -f ($d.Input - $d.Cached)))
        [void]$rows.Add(('缓存读取|{0:N0} tok' -f $d.Cached))
        [void]$rows.Add(('输出|{0:N0} tok' -f $d.Output))
    } elseif ($seg -eq 'ctx') {
        $title = ('ctx|上下文已用 {0:N0}%|' -f $d.CtxPct)
        [void]$rows.Add(('progress|{0}|~{1} / {2}' -f $d.CtxPct, (Fmt-Tok $d.Used), (Fmt-Tok $d.Window)))
        [void]$rows.Add(('系统提示词|~{0}' -f (Fmt-Tok $d.SysTok)))
        [void]$rows.Add(('工具定义|~{0}' -f (Fmt-Tok $d.ToolTok)))
        [void]$rows.Add(('对话消息|~{0}' -f (Fmt-Tok $d.MsgTok)))
    }    
    $script:popup.DarkText = $true
    $script:popup.SetContent($title, [string[]]$rows.ToArray(), '')
    $script:anchorX = 0
    $x = $form.Left + $form.ClickedX
    $scr = [System.Windows.Forms.Screen]::FromControl($form)
    if ($x + $script:popup.Width -gt $scr.WorkingArea.Right) { $x = $scr.WorkingArea.Right - $script:popup.Width - 8 }
    if ($x -lt $scr.WorkingArea.Left) { $x = $scr.WorkingArea.Left }
    $script:popup.Left = $x
    $below = $form.Bottom + 4
    $script:popup.Top = if ($below + $script:popup.Height -le $scr.WorkingArea.Bottom) { $below } else { [Math]::Max($scr.WorkingArea.Top, $form.Top - $script:popup.Height - 4) }
    if (-not $script:popup.Visible) { $script:popup.Show() }
    $script:popup.SetAnim(1.0)
    $script:popupPinned = $true
    $script:pinnedSeg = $seg
    Log ('info=' + $seg + ' veil=' + $form.Veil + ' dark=' + $script:popup.DarkText + ' w=' + $script:popup.Width + ' h=' + $script:popup.Height)
    try { [void][Win32]::SetWindowPos($script:popup.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } catch {}
}

function Show-CostPopup {
    if ($script:menuOpen) { return }
    if (-not $script:popup -or -not $script:activeFile) { return }
    try { Update-CostPopup } catch { Log ('cost-err ' + $_.Exception.Message); return }
    $x = $form.Left
    $y = $form.Top + $form.Height + 6
    $script:anchorX = 0
    $script:popup.Left = $x
    $script:popup.Top = $y
    if (-not $script:popup.Visible) {
        $script:popup.SetAnim(0.02)
        $script:popup.Show()
        $script:animStep = 0
        $animTimer.Start()
    } else {
        $script:popup.SetAnim(1.0)
    }
    try { [void][Win32]::SetWindowPos($script:popup.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } catch {}
}

function Hide-CostPopup {
    try {
        if ($animTimer) { $animTimer.Stop() }
        $script:popupPinned = $false
        $script:pinnedSeg = ''
        if ($script:popup -and $script:popup.Visible) { $script:popup.Hide() }
    } catch {}
}

$form = New-Object CodexHud
$popup = New-Object CostPopup
$popup.Hud = $form
$popup.add_OutsidePress({ Hide-CostPopup })
$script:popup = $popup
$script:popupHover = $false
$script:popupPinned = $false
$script:pinnedSeg = ''
$script:anchorX = 0
$script:activeFile = ''
$form.FixedPos = $settings.fixed
$form.Veil = $settings.veil
$form.SetScale($settings.scale)
$popup.SetScale($settings.scale)
$popup.DarkText = (-not $settings.veil)

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$script:menuOpen = $false
$script:sawChat = $false
$menu.Add_Opened({ $script:menuOpen = $true; Hide-CostPopup })
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
$miSize = New-Object System.Windows.Forms.ToolStripMenuItem '窗口大小'
$script:sizeItems = @()
$sizeChoices = @(
    @{ Name = '小'; Value = 0.85 },
    @{ Name = '标准'; Value = 1.0 },
    @{ Name = '大'; Value = 1.15 },
    @{ Name = '特大'; Value = 1.3 }
)
foreach ($pair in $sizeChoices) {
    $si = New-Object System.Windows.Forms.ToolStripMenuItem $pair.Name
    $si.Tag = [double]$pair.Value
    $si.Checked = ([Math]::Abs($settings.scale - [double]$pair.Value) -lt 0.01)
    $si.Add_Click({ Apply-Scale ([double]$this.Tag) })
    $miSize.DropDownItems.Add($si) | Out-Null
    $script:sizeItems += $si
}
$menu.Items.Add($miSize) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
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

function Get-ActiveThreadIdFromLogs {
    $db = Join-Path $env:USERPROFILE '.codex\logs_2.sqlite'
    if (-not (Test-Path -LiteralPath $db)) { return $null }
    try {
        $ts = [long]0
        $tid = [SqliteLog]::LatestResumeThread($db, [ref]$ts)
        if ($tid) {
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ts
            return [pscustomobject]@{ id = [string]$tid; age = $age }
        }
    } catch {}
    return $null
}

function Get-ThreadModel([string]$id) {
    if (-not $id -or $id -eq 'draft') { return '' }
    if ($id -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return '' }
    $db = Join-Path $env:USERPROFILE '.codex\state_5.sqlite'
    if (-not (Test-Path -LiteralPath $db)) { return '' }
    try { return [string]([SqliteLog]::ThreadModel($db, $id)) } catch { return '' }
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

$script:sessionPaths = @{}
function Get-SessionFile([string]$id) {
    if (-not $id -or $id -eq 'draft') { return $null }
    $dir = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    if ($script:sessionPaths[$id] -and [IO.File]::Exists($script:sessionPaths[$id])) {
        return Get-Item -LiteralPath $script:sessionPaths[$id]
    }
    $found = Get-ChildItem -LiteralPath $dir -Recurse -Filter ('*' + $id + '*.jsonl') -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($found) { $script:sessionPaths[$id] = $found.FullName }
    return $found
}

function Get-LatestSession {
    $dir = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Read-Stats([string]$file, [string]$modelFallback = '') {
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
            if (-not $model -and $o.payload.model) { $model = [string]$o.payload.model }
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

    if (-not $model -and $modelFallback) { $model = $modelFallback }
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
        if ($script:lastOcrHash -eq $hash) { return $script:lastOcrText }

        $stream = $null; $sb = $null
        try {
        $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmp)) ([Windows.Storage.StorageFile])
        $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $sb = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $res = Await ($script:ocrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
        $script:lastOcrHash = $hash
        $script:lastOcrText = $res.Text
        Log ('ocr=[' + $res.Text + ']')
        return $res.Text
        } finally {
            if ($sb -is [IDisposable]) { $sb.Dispose() }
            if ($stream -is [IDisposable]) { $stream.Dispose() }
        }
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
    $path = Join-Path $env:USERPROFILE '.codex\session_index.jsonl'
    $stamp = $null
    if (Test-Path -LiteralPath $path) {
        try { $stamp = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks } catch {}
    }
    if ($script:idxCache -and $script:idxStamp -eq $stamp) { return $script:idxCache }
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
    $script:idxStamp = $stamp
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
        Hide-CostPopup
        if ($form.Visible) { $form.Hide() }
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
    $source = ''
    if (-not $script:menuOpen) {
        try { $id = Get-ActiveThreadIdByTitle } catch {}
        if ($id) { $source = 'ocr' }
        else {
            $logHit = Get-ActiveThreadIdFromLogs
            if ($logHit -and $logHit.age -ge 0 -and $logHit.age -le 4) {
                $id = $logHit.id
                $source = 'logs'
            }
        }
    }
    if (-not $id -and -not $script:menuOpen) {
        $latest = Get-LatestSession
        if ($latest -and ((Get-Date) - $latest.LastWriteTime).TotalSeconds -le 90) {
            $m = [regex]::Match($latest.Name, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$')
            if ($m.Success) { $id = $m.Groups[1].Value; $source = 'latest' }
        }
    }
    if (-not $id -and $script:lastId) { $id = $script:lastId; $source = 'last' }
    if (-not $id) {
        try { $id = Get-ActiveThreadId } catch {}
        $source = 'state'
    }
    if ($id -and $id -ne $script:lastId) { Hide-CostPopup }
    if ($id) { $script:lastId = $id }
    $f = $null
    if ($id -and $id -ne 'draft') { $f = Get-SessionFile $id }
    if (-not $f -and -not $id) { $f = Get-LatestSession }
    $script:activeFile = if ($f) { $f.FullName } else { '' }

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
    $dbModel = ''
    if ($id -and $id -ne 'draft') { try { $dbModel = Get-ThreadModel $id } catch {} }
    $statsKey = $f.FullName + '|' + $f.Length + '|' + $f.LastWriteTimeUtc.Ticks + '|' + $dbModel
    if ($statsKey -eq $script:statsKey) { $s = $script:cachedStats }
    else {
        try { $s = Read-Stats $f.FullName $dbModel } catch { $s = $null }
        $script:statsKey = $statsKey
        $script:cachedStats = $s
    }
    if ($s -and $script:lastStatsLog -ne $id) {
        Log ('model=' + $s.Model + ' total=' + $s.Total)
        $script:lastStatsLog = $id
    }

    if ($null -eq $s) {
        $form.Model = if ($dbModel) { $dbModel } else { 'Codex' }
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
        Log ('id=' + $id + ' source=' + $source + ' file=' + $f.Name)
        $script:lastLogKey = $id + '|' + $f.FullName
    }
    $form.Render()
    if ($script:popup.Visible -and -not $script:popupPinned) { try { Show-CostPopup } catch {} }

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
$miVeil.Add_Click({ $form.Veil = $miVeil.Checked; $form.Render(); $popup.DarkText = (-not $miVeil.Checked); Hide-CostPopup; Save-Settings })
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
    Hide-CostPopup
    $script:popup.Close()
    Save-Settings
    $form.Close()
})
$form.Add_LocationChanged({
    if ($script:popup -and $script:popup.Visible) {
        $px = $form.Left + [Math]::Max(0, [int]$script:anchorX)
        try { [void][Win32]::SetWindowPos($script:popup.Handle, [IntPtr](-1), $px, $form.Top + $form.Height + 6, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010) } catch {}
    }
    if ($miFixed.Checked) { Save-Settings }
})

$script:popupHover = $false
$script:animStep = 0
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 15
$animTimer.Add_Tick({
    $script:animStep++
    $t = [Math]::Min(1.0, $script:animStep / 12.0)
    $e = 1.0 - [Math]::Pow(1.0 - $t, 3)
    try { $script:popup.SetAnim($e) } catch {}
    if ($t -ge 1.0) { $animTimer.Stop() }
})
$hideCostTimer = New-Object System.Windows.Forms.Timer
$hideCostTimer.Interval = 300
$hideCostTimer.Add_Tick({
    $hideCostTimer.Stop()
    try {
        $p = [System.Windows.Forms.Cursor]::Position
        if ($script:popupPinned) { return }
        if ($script:popupHover -or $script:popup.Bounds.Contains($p)) { return }
        Hide-CostPopup
    } catch {}
})
$form.add_HoverEnter({ $hideCostTimer.Stop(); if (-not $script:popupPinned) { Show-CostPopup } })
$form.add_SegmentClick({ if ($form.ClickedSegment) { Show-InfoPopup $form.ClickedSegment } })
$form.add_HoverLeave({ $hideCostTimer.Stop(); $hideCostTimer.Start() })
$popup.Add_MouseEnter({ $script:popupHover = $true; $hideCostTimer.Stop() })
$popup.Add_MouseLeave({ $script:popupHover = $false; $hideCostTimer.Stop(); $hideCostTimer.Start() })
$form.Add_VisibleChanged({ if (-not $form.Visible) { Hide-CostPopup } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 650
$timer.Add_Tick({
    try { Update-Hud } catch {}
    try { [void][Win32]::SetWindowPos($form.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } catch {}
    try { if ($script:popup -and $script:popup.Visible) { [void][Win32]::SetWindowPos($script:popup.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } } catch {}
})
$timer.Start()

$form.Add_Shown({
    try { [void][Win32]::SetWindowPos($form.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0010) } catch {}
})

# 等 ChatGPT 出现；不存在时保持隐藏
$context = New-Object System.Windows.Forms.ApplicationContext
$form.Add_Closed({ $context.ExitThread() })
Log ('start v' + $script:Version + ' force=' + $ForceShow)
Update-Hud

if ($CostTest) {
    Write-Output ('scale=' + $settings.scale + ' height=' + $form.Height)
    $f = Get-LatestSession
    if ($f) {
        $map = Read-ModelUsage $f.FullName
        foreach ($u in $map.Values) {
            $pr = Get-PriceFor $u.model
            Write-Output ('{0} in={1} cached={2} out={3} cost={4:N4}' -f $u.model, $u.input, $u.cached, $u.output, (Get-UsageCost $u $pr))
        }
    }
    exit
}

[System.Windows.Forms.Application]::Run($context)

$timer.Stop()
if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue }








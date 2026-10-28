// ============================================================
// MODO GAMING - programa de la bandeja del sistema
// Icono junto al reloj para cambiar de modo con un clic.
// Los modos se aplican con tareas programadas elevadas que crea el
// instalador, asi no aparece la ventana de UAC en cada cambio.
// ============================================================
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

static class Programa
{
    [STAThread]
    static void Main()
    {
        bool nuevo;
        using (var mutex = new Mutex(true, "Local\\ModoGamingBandeja", out nuevo))
        {
            if (!nuevo) return; // ya hay uno abierto
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new Bandeja());
        }
    }
}

class Modo
{
    public string Id, Nombre, Letra; public Color Color;
    public Modo(string id, string nombre, string letra, Color color) { Id = id; Nombre = nombre; Letra = letra; Color = color; }
}

class Bandeja : ApplicationContext
{
    static readonly Modo[] Modos = {
        new Modo("gaming",        "Gaming eficiente (hasta 3.3 GHz, max 85 C)", "G", Color.FromArgb(46, 160, 67)),
        new Modo("gamingfresco",  "Gaming fresco (hasta 3.2 GHz, max 85 C)", "F", Color.FromArgb(0, 150, 160)),
        new Modo("cpuloose",      "CPU suelto (hasta 3.2 GHz, max 85 C)", "C", Color.FromArgb(230, 126, 34)),
        new Modo("dinamico",      "Gaming dinamico (2.9-4.2 GHz turbo, max 85 C)", "T", Color.FromArgb(200, 60, 140)),
        new Modo("altorend",     "Alto rendimiento seguro (max 85 C)", "A", Color.FromArgb(200, 40, 40)),
        new Modo("ahorro",        "Ahorro de energia",                 "E", Color.FromArgb(40, 120, 200)),
        new Modo("ahorrosinsusp", "Ahorro de energia sin suspension",  "D", Color.FromArgb(90, 80, 200)),
        new Modo("normal",        "Normal fresco (hasta 3.3 GHz, max 85 C)", "N", Color.FromArgb(120, 160, 60)),
        new Modo("original",      "Windows original (sin regulador)", "W", Color.FromArgb(110, 110, 110)),
    };
    const string NombreInicio = "ModoGaming";

    readonly string carpetaApp = Path.GetDirectoryName(Application.ExecutablePath);
    readonly string carpetaDatos = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ModoGaming");
    string ArchivoModo { get { return Path.Combine(carpetaDatos, "modo_actual.txt"); } }
    string ArchivoLog { get { return Path.Combine(carpetaDatos, "ultimo.log"); } }

    readonly NotifyIcon icono = new NotifyIcon();
    readonly ContextMenuStrip menu = new ContextMenuStrip();
    readonly System.Windows.Forms.Timer espera = new System.Windows.Forms.Timer();
    DateTime marcaAntes; Modo pedido; int intentos;
    ToolStripMenuItem itemRevertir, itemInicio;

    public Bandeja()
    {
        Directory.CreateDirectory(carpetaDatos);
        foreach (var m in Modos)
        {
            var item = new ToolStripMenuItem(m.Nombre, CrearIcono(m).ToBitmap()) { Tag = m };
            item.Click += (s, e) => Aplicar((Modo)((ToolStripMenuItem)s).Tag);
            menu.Items.Add(item);
        }
        itemRevertir = new ToolStripMenuItem("Revertir solo CPU suelto");
        itemRevertir.Click += (s, e) => Aplicar(new Modo("revertircpu", "Revertir CPU suelto", "G", Modos[0].Color));
        menu.Items.Add(itemRevertir);
        menu.Items.Add(new ToolStripSeparator());

        var cerrar = new ToolStripMenuItem("Cerrar lo que usa CPU...");
        cerrar.Click += (s, e) => CerrarCpu();
        menu.Items.Add(cerrar);
        var log = new ToolStripMenuItem("Ver detalles del ultimo cambio");
        log.Click += (s, e) => { if (File.Exists(ArchivoLog)) Process.Start("notepad.exe", "\"" + ArchivoLog + "\""); };
        menu.Items.Add(log);
        menu.Items.Add(new ToolStripSeparator());

        itemInicio = new ToolStripMenuItem("Iniciar con Windows") { CheckOnClick = true };
        itemInicio.Checked = IniciaConWindows();
        itemInicio.Click += (s, e) => CambiarInicio(itemInicio.Checked);
        menu.Items.Add(itemInicio);
        var salir = new ToolStripMenuItem("Salir");
        salir.Click += (s, e) => { icono.Visible = false; icono.Dispose(); ExitThread(); };
        menu.Items.Add(salir);
        menu.Opening += (s, e) => Refrescar();

        icono.ContextMenuStrip = menu;
        icono.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) MostrarMenu(); };
        icono.Visible = true;

        espera.Interval = 1000;
        espera.Tick += (s, e) => RevisarCambio();
        Refrescar();
    }

    void MostrarMenu()
    {
        var mi = typeof(NotifyIcon).GetMethod("ShowContextMenu", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
        if (mi != null) mi.Invoke(icono, null);
    }

    string ModoActual()
    {
        try { return File.Exists(ArchivoModo) ? File.ReadAllText(ArchivoModo).Trim() : "original"; } catch { return "original"; }
    }

    void Refrescar()
    {
        var actual = ModoActual();
        var m = Modos.FirstOrDefault(x => x.Id == actual) ?? Modos.Last();
        foreach (ToolStripItem it in menu.Items)
        {
            var mi = it as ToolStripMenuItem;
            if (mi != null && mi.Tag is Modo) mi.Checked = ((Modo)mi.Tag).Id == actual;
        }
        itemRevertir.Enabled = actual == "cpuloose";
        icono.Icon = CrearIcono(m);
        var texto = "Modo Gaming: " + m.Nombre;
        icono.Text = texto.Length > 63 ? texto.Substring(0, 63) : texto;
    }

    void Aplicar(Modo m)
    {
        if (espera.Enabled) { Avisar("Espera un momento", "Todavia se esta aplicando el cambio anterior.", ToolTipIcon.Warning); return; }
        marcaAntes = File.Exists(ArchivoModo) ? File.GetLastWriteTimeUtc(ArchivoModo) : DateTime.MinValue;
        pedido = m; intentos = 0;
        if (!EjecutarTarea(m.Id))
        {
            // Sin tarea instalada: pedir administrador con UAC
            try
            {
                var psi = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(carpetaApp, "motor.ps1") + "\" -Modo " + m.Id)
                { Verb = "runas", UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden };
                Process.Start(psi);
            }
            catch { Avisar("No se cambio el modo", "Se cancelo el permiso de administrador.", ToolTipIcon.Warning); return; }
        }
        icono.Text = "Modo Gaming: aplicando " + (m.Nombre.Length > 30 ? m.Nombre.Substring(0, 30) : m.Nombre) + "...";
        espera.Start();
    }

    bool EjecutarTarea(string id)
    {
        try
        {
            var psi = new ProcessStartInfo("schtasks.exe", "/run /tn \"\\ModoGaming\\" + id + "\"")
            { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            using (var p = Process.Start(psi)) { p.WaitForExit(10000); return p.ExitCode == 0; }
        }
        catch { return false; }
    }

    void RevisarCambio()
    {
        intentos++;
        var marca = File.Exists(ArchivoModo) ? File.GetLastWriteTimeUtc(ArchivoModo) : DateTime.MinValue;
        bool cambio = marca != marcaAntes;
        if (!cambio && intentos < 90) return;
        espera.Stop();
        Refrescar();
        if (!cambio) { Avisar("Sin respuesta", "El modo no se aplico. Mira 'Ver detalles del ultimo cambio'.", ToolTipIcon.Warning); return; }
        var avisos = LeerAvisos();
        var actual = Modos.FirstOrDefault(x => x.Id == ModoActual());
        var titulo = pedido.Id == "revertircpu" ? "CPU suelto revertido" : (actual != null ? actual.Nombre : pedido.Nombre) + " activado";
        Avisar(titulo, avisos.Length > 0 ? avisos : "Listo.", avisos.Length > 0 ? ToolTipIcon.Warning : ToolTipIcon.Info);
    }

    string LeerAvisos()
    {
        try
        {
            var lineas = File.ReadAllLines(ArchivoLog).Where(l => l.StartsWith("[!]")).Select(l => l.Substring(3).Trim()).Distinct().ToArray();
            var t = string.Join("\n", lineas);
            return t.Length > 250 ? t.Substring(0, 250) : t;
        }
        catch { return ""; }
    }

    void CerrarCpu()
    {
        var motor = Path.Combine(carpetaApp, "motor.ps1");
        Process.Start(new ProcessStartInfo("cmd.exe",
            "/c title Cerrar lo que usa CPU & powershell -NoProfile -ExecutionPolicy Bypass -File \"" + motor + "\" -Modo cerrarcpu & pause")
        { UseShellExecute = true });
    }

    void Avisar(string titulo, string texto, ToolTipIcon tipo) { icono.ShowBalloonTip(4000, titulo, texto, tipo); }

    bool IniciaConWindows()
    {
        using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            return k != null && k.GetValue(NombreInicio) != null;
    }

    void CambiarInicio(bool si)
    {
        using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
        {
            if (si) k.SetValue(NombreInicio, "\"" + Application.ExecutablePath + "\"");
            else k.DeleteValue(NombreInicio, false);
        }
    }

    static readonly System.Collections.Generic.Dictionary<string, Icon> iconos = new System.Collections.Generic.Dictionary<string, Icon>();

    static Icon CrearIcono(Modo m)
    {
        Icon ya;
        if (iconos.TryGetValue(m.Id, out ya)) return ya;
        return iconos[m.Id] = DibujarIcono(m);
    }

    static Icon DibujarIcono(Modo m)
    {
        using (var bmp = new Bitmap(32, 32))
        using (var g = Graphics.FromImage(bmp))
        using (var fondo = new SolidBrush(m.Color))
        using (var fuente = new Font("Segoe UI", 15, FontStyle.Bold, GraphicsUnit.Pixel))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.FillEllipse(fondo, 1, 1, 30, 30);
            var f = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString(m.Letra, fuente, Brushes.White, new RectangleF(0, 1, 32, 32), f);
            return Icon.FromHandle(bmp.GetHicon());
        }
    }
}

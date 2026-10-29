// ============================================================
// MODO GAMING - INSTALADOR / ACTUALIZADOR (un solo .exe para compartir)
// Lleva adentro: instalar.ps1, desinstalar.ps1, motor.ps1, gobernador.ps1,
// ModoGaming.cs y el lector de temperatura (carpeta lhm).
// Los extrae en una carpeta temporal, ejecuta instalar.ps1 y la borra.
// Sirve para instalar por primera vez y para actualizar.
// Compilar: ver compilar-setup.ps1 (en esta carpeta)
// ============================================================
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("Modo Gaming - Instalador")]
[assembly: AssemblyProduct("Modo Gaming")]
[assembly: AssemblyCompany("ibrek")]
[assembly: AssemblyVersion("1.2.0.0")]
[assembly: AssemblyFileVersion("1.2.0.0")]

class Setup
{
    static int Main()
    {
        Console.Title = "Modo Gaming - Instalar / Actualizar";
        Console.WriteLine("==========================================");
        Console.WriteLine("  MODO GAMING v1.2 - instalar / actualizar");
        Console.WriteLine("==========================================");
        Console.WriteLine();

        int codigo = 1;
        string tmp = Path.Combine(Path.GetTempPath(), "ModoGamingSetup_" + Guid.NewGuid().ToString("N").Substring(0, 8));
        try
        {
            Directory.CreateDirectory(tmp);
            Assembly asm = Assembly.GetExecutingAssembly();
            foreach (string nombre in asm.GetManifestResourceNames())
            {
                if (!nombre.StartsWith("pkg/")) continue;
                string relativo = nombre.Substring(4).Replace('/', Path.DirectorySeparatorChar);
                string destino = Path.GetFullPath(Path.Combine(tmp, relativo));
                if (!destino.StartsWith(tmp + Path.DirectorySeparatorChar)) continue;   // nunca fuera de la carpeta temporal
                Directory.CreateDirectory(Path.GetDirectoryName(destino));
                using (Stream s = asm.GetManifestResourceStream(nombre))
                using (FileStream f = File.Create(destino))
                    s.CopyTo(f);
            }

            Console.WriteLine("Archivos listos. Acepta el permiso de administrador cuando Windows lo pida.");
            Console.WriteLine();
            string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            ProcessStartInfo psi = new ProcessStartInfo(ps,
                "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(tmp, "instalar.ps1") + "\"");
            psi.UseShellExecute = false;
            psi.WorkingDirectory = tmp;
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit();
                codigo = p.ExitCode;
            }
        }
        catch (Exception e)
        {
            Console.WriteLine("[!] Error: " + e.Message);
        }
        finally
        {
            try { Directory.Delete(tmp, true); } catch { }
        }

        Console.WriteLine();
        Console.WriteLine(codigo == 0 ? "Listo." : "[!] No se completo. Revisa %LOCALAPPDATA%\\ModoGaming\\instalacion.log");
        Console.WriteLine("Presiona una tecla para cerrar...");
        try { Console.ReadKey(true); } catch { }
        return codigo;
    }
}

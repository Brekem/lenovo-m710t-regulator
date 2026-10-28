# ============================================================
# Compila ModoGaming-Setup.exe (instalador/actualizador para compartir)
# Uso: clic derecho > Ejecutar con PowerShell (no hace falta administrador)
# Toma los archivos de la carpeta BATS y el lector de temperatura de
# C:\Program Files\ModoGaming\lhm (o del paquete de winget) y los mete en el .exe.
# El .exe queda en BATS\Compartir\ModoGaming-Setup.exe
# ============================================================
$ErrorActionPreference = 'Stop'
$prog = $PSScriptRoot
$bats = Split-Path $prog
$build = Join-Path $env:TEMP 'mg-build'
$salida = Join-Path $bats 'Compartir\ModoGaming-Setup.exe'

Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $build 'pkg\lhm') | Out-Null
$pkg = Join-Path $build 'pkg'

Copy-Item (Join-Path $prog 'instalar.ps1'), (Join-Path $prog 'desinstalar.ps1'), (Join-Path $prog 'ModoGaming.cs') $pkg
Copy-Item (Join-Path $bats 'motor.ps1'), (Join-Path $bats 'gobernador.ps1') $pkg

$lhm = 'C:\Program Files\ModoGaming\lhm'
if (-not (Test-Path (Join-Path $lhm 'LibreHardwareMonitorLib.dll'))) {
    $lhm = (Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\LibreHardwareMonitor.LibreHardwareMonitor*') -Directory | Select-Object -First 1).FullName
}
if (-not $lhm -or -not (Test-Path (Join-Path $lhm 'LibreHardwareMonitorLib.dll'))) { throw "No se encontro LibreHardwareMonitorLib.dll" }
Get-ChildItem $lhm -Filter *.dll -File | Where-Object { $_.Name -notmatch '^(Aga\.Controls|OxyPlot|Microsoft\.Win32\.TaskScheduler)' } | Copy-Item -Destination (Join-Path $pkg 'lhm')
@'
LibreHardwareMonitorLib y sus dependencias (carpeta lhm)
Se incluyen sin modificar para leer la temperatura del CPU.
LibreHardwareMonitor: Mozilla Public License 2.0
Codigo fuente: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
Las demas DLL (System.*, Microsoft.Bcl.*): .NET, licencia MIT.
'@ | Set-Content (Join-Path $pkg 'lhm\LICENCIAS.txt') -Encoding ASCII

# Cada archivo del paquete va como recurso "pkg/<ruta>"
$recursos = Get-ChildItem $pkg -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($pkg.Length + 1).Replace('\', '/')
    "/resource:`"$($_.FullName)`",pkg/$rel"
}
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
New-Item -ItemType Directory -Force (Split-Path $salida) | Out-Null
$rsp = Join-Path $build 'csc.rsp'
(@('/nologo', '/target:exe', '/optimize+', "/out:`"$salida`"") + $recursos + "`"$(Join-Path $prog 'Setup.cs')`"") | Set-Content $rsp -Encoding ASCII
& $csc "@$rsp"
if ($LASTEXITCODE -ne 0) { throw "Error al compilar Setup.cs" }
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
"Listo: $salida ({0:N1} MB)" -f ((Get-Item $salida).Length / 1MB)

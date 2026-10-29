# ============================================================
# REGULADOR TERMICO (funciona en TODOS los modos menos "Windows original")
# El motor le dice el techo de velocidad del modo (gobernador.cfg) y el regulador
# sube el CPU hasta ese techo y lo baja de a poco si se calienta:
#   - Llega a $CALIENTE C  -> baja $PASO MHz (y espera antes de volver a bajar)
#   - Se mantiene en $FRESCO C o menos un rato -> sube $PASO MHz (hasta el techo del modo)
#   - Llega a $LIMITE C (emergencia) -> baja $PASO_URGENTE MHz de golpe, sin esperar
#   - Nunca baja de $MIN_MHZ (equivalente al CPU minimo de ARC Raiders)
# El margen entre 84 y 80 C evita que se quede saltando de arriba abajo.
# Se apaga solo cuando cambias de modo.
# En los modos de juego: si dejas la PC sola ($MIN_INACTIVO min sin teclado/raton y sin
# el juego abierto), vuelve sola a "Normal fresco" para no gastar luz ni calentar de gusto.
# Lee la temperatura con LibreHardwareMonitorLib (carpeta lhm, solo administradores).
# ============================================================
param(
    [int]$CALIENTE = 84,   # C: a partir de aqui baja (para no llegar a 85)
    [int]$FRESCO   = 80,   # C: por debajo de esto puede subir
    [int]$LIMITE   = 85    # C: freno de emergencia, baja rapido
)
$PASO_URGENTE = 200
$MIN_MHZ   = 2900   # piso de emergencia: 2.9 GHz; vuelve a subir al enfriarse
$PASO      = 100
$SEG_BAJAR = 2      # segundos seguidos en $CALIENTE para bajar (una sola lectura)
$SEG_SUBIR = 15     # segundos seguidos en $FRESCO o menos para subir
$PROMEDIO  = 1      # lecturas que se promedian (1 = sin promedio, cada lectura cuenta; 3 = promedio de 6 s)
$ESPERA    = 10     # segundos minimos entre un cambio y el siguiente
$INTERVALO = 2      # segundos entre lecturas
$MIN_INACTIVO = 20  # minutos sin usar la PC (y sin juego abierto) para volver a Normal fresco
$JUEGOS    = 'PioneerGame'   # procesos de juego: mientras alguno este abierto, nunca vuelve solo
$MODOS_JUEGO = 'gaming', 'gamingfresco', 'cpuloose', 'dinamico', 'altorend'   # los que vuelven solos a Normal fresco

# Ventilador de salida (conector FANIN2 = "Fan #3" en el chip ITE IT8628E de la Lenovo 3102)
#   Modos de juego ("juego"): va a $VENT_JUEGO % y sube a $VENT_ALTO % si el CPU llega a $VENT_TEMP_ALTA
#   Normal / ahorro ("auto"): lo controla la placa (50%); solo si el CPU llega a $VENT_TEMP_ALTA sube a
#   $VENT_ALTO %, y cuando baja de $VENT_TEMP_ALTA - 6 C se lo devuelve a la placa.
$VENT_PLACA    = 'Lenovo 3102'   # solo en esta placa (en otra PC "Fan #3" puede ser otro ventilador)
$VENT_SALIDA   = 'Fan #3'
$VENT_JUEGO    = 80     # % al jugar (la placa lo deja en 50%: ~1750 RPM; 80% = ~2750 RPM)
$VENT_ALTO     = 90     # % cuando el CPU llega a $VENT_TEMP_ALTA
$VENT_TEMP_ALTA = 82    # C

# Ventilador del CPU (conector CPU_FAN = "Fan #1"), solo en "Gaming eficiente dinamico":
#   lo controla la placa; si el CPU llega a $VENT_CPU_SUBE se pone al 100% y bajo $VENT_CPU_SUELTA
#   se le devuelve a la placa. Nunca se pone por debajo de lo que pone la placa.
$VENT_CPU        = 'Fan #1'
$VENT_CPU_SUBE   = 80   # C
$VENT_CPU_SUELTA = 75   # C

$SUB_CPU     = '54533251-82be-4824-96c1-47b60b740d00'
$CPU_MHZ     = '75b0ae3f-bce0-45a7-8c89-c9611c25e100'
$CPU_MAX     = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
$CPU_BOOST   = 'be337238-0d82-4146-a960-4f3749d470c7'   # modo Turbo: 0 = apagado, 2 = agresivo

$dir       = Join-Path $env:LOCALAPPDATA 'ModoGaming'
$stateFile = Join-Path $dir 'modo_actual.txt'
$cfgFile   = Join-Path $dir 'gobernador.cfg'       # lo escribe el motor: max, ventilador y plan del modo
$logFile   = Join-Path $dir 'gobernador.log'
$pararFile = Join-Path $dir 'detener_gobernador'   # el motor lo crea al cambiar de modo: apagarse ordenadamente
New-Item -ItemType Directory -Force $dir | Out-Null

function Log($m) { Add-Content $logFile ("{0:HH:mm:ss}  {1}" -f (Get-Date), $m) -Encoding ASCII }
function Modo-Actual { if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() } else { '' } }

# El modo al que sirve este regulador (si cambia, se apaga). En "Windows original" no corre.
$MODO = Modo-Actual
if (-not $MODO -or $MODO -eq 'original') { exit 0 }

# Configuracion del modo (la escribe el motor justo antes de arrancar el regulador)
$cfg = @{ max = '3300'; ventilador = 'auto'; plan = '381b4222-f694-41f0-9685-ff5bb260df2e' }
if (Test-Path $cfgFile) {
    Get-Content $cfgFile | ForEach-Object { if ($_ -match '^\s*(\w+)\s*=\s*(.+?)\s*$') { $cfg[$Matches[1]] = $Matches[2] } }
}
$MAX_MHZ  = [math]::Max($MIN_MHZ, [int]$cfg.max)
$VENT_MODO = $cfg.ventilador      # 'juego' o 'auto'
$PLAN     = $cfg.plan
$TURBO    = [int]$cfg.turbo           # 0 = sin Turbo, 2 = agresivo (Gaming dinamico), 3 = eficiente (Gaming eficiente)
if ($TURBO -eq 1) { $TURBO = 2 }   # configuracion vieja
$CON_VENT_CPU = ($cfg.ventcpu -eq '1')

# Minutos desde la ultima vez que se toco el teclado o el raton
Add-Type -Namespace ModoGaming -Name Inactividad -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
public static double Minutos() {
    LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i);
    if (!GetLastInputInfo(ref i)) return 0;
    return unchecked((uint)Environment.TickCount - i.dwTime) / 60000.0;
}
'@

# Una sola copia corriendo
$mutex = New-Object Threading.Mutex($false, 'Global\ModoGamingGobernador')
try { if (-not $mutex.WaitOne(0)) { exit 0 } } catch [Threading.AbandonedMutexException] { }   # la copia anterior fue cerrada a la fuerza

# Empezar el registro de cero en cada sesion (que no crezca para siempre)
Set-Content $logFile ("{0:yyyy-MM-dd HH:mm:ss}  Regulador iniciado en modo '{1}': {2}-{3} MHz, baja en {4} C, sube bajo {5} C, ventilador {6}, turbo {7}" -f (Get-Date), $MODO, $MIN_MHZ, $MAX_MHZ, $CALIENTE, $FRESCO, $VENT_MODO, $(switch ($TURBO) { 2 { 'agresivo' } 3 { 'eficiente' } default { 'no' } })) -Encoding ASCII

$dll = Join-Path $PSScriptRoot 'lhm\LibreHardwareMonitorLib.dll'
if (-not (Test-Path $dll)) { Log "ERROR: falta $dll (reinstala Modo Gaming)"; exit 1 }
try {
    [void][Reflection.Assembly]::LoadFrom($dll)
    $pc = New-Object LibreHardwareMonitor.Hardware.Computer
    $pc.IsCpuEnabled = $true
    $pc.IsMotherboardEnabled = $true
    $pc.Open()
    $cpu = $pc.Hardware | Where-Object { $_.HardwareType -eq 'Cpu' } | Select-Object -First 1
    if (-not $cpu) { throw "no se encontro el CPU" }
} catch { Log "ERROR al leer sensores: $($_.Exception.Message)"; exit 1 }

# Control del ventilador de salida (si no se encuentra, el regulador sigue igual sin tocarlo)
$vent = $null; $ventActual = -1   # -1 = lo controla la placa
try {
    $mb = $pc.Hardware | Where-Object { $_.HardwareType -eq 'Motherboard' -and $_.Name -eq $VENT_PLACA } | Select-Object -First 1
    $sio = if ($mb) { $mb.SubHardware | Where-Object { $_.HardwareType -eq 'SuperIO' } | Select-Object -First 1 }
    if ($sio) { $vent = ($sio.Sensors | Where-Object { $_.SensorType -eq 'Control' -and $_.Name -eq $VENT_SALIDA } | Select-Object -First 1).Control }
} catch { $vent = $null }
# Valor que tenia al arrancar: si ya estaba alto (quedo asi de un cierre forzado), "original" seria ese valor alto
$ventInicial = try { [double]($sio.Sensors | Where-Object { $_.SensorType -eq 'Control' -and $_.Name -eq $VENT_SALIDA } | Select-Object -First 1).Value } catch { 0 }
# Ventilador del CPU (solo si el modo lo pide; al soltarlo vuelve a la curva de la placa)
$ventCpu = $null; $ventCpuAlto = $false
if ($CON_VENT_CPU -and $sio) { try { $ventCpu = ($sio.Sensors | Where-Object { $_.SensorType -eq 'Control' -and $_.Name -eq $VENT_CPU } | Select-Object -First 1).Control } catch { $ventCpu = $null } }
function Subir-VentCpu {
    if (-not $ventCpu -or $script:ventCpuAlto) { return }
    try { $ventCpu.SetSoftware(100); $script:ventCpuAlto = $true; Log "Ventilador del CPU al 100%" } catch { Log "No se pudo controlar el ventilador del CPU: $($_.Exception.Message)"; $script:ventCpu = $null }
}
function Soltar-VentCpu {
    if (-not $ventCpu -or -not $script:ventCpuAlto) { return }
    try { $ventCpu.SetDefault(); Log "Ventilador del CPU devuelto a la placa" } catch {}
    $script:ventCpuAlto = $false
}
function Poner-Ventilador([int]$pct) {
    if (-not $vent -or $pct -eq $script:ventActual) { return }
    try { $vent.SetSoftware($pct); $script:ventActual = $pct; Log "Ventilador de salida al $pct%" } catch { Log "No se pudo controlar el ventilador: $($_.Exception.Message)"; $script:vent = $null }
}
function Soltar-Ventilador {
    if (-not $vent -or $script:ventActual -lt 0) { return }
    try { if ($ventInicial -ge $VENT_JUEGO) { $vent.SetSoftware(50) } else { $vent.SetDefault() } } catch {}
    $script:ventActual = -1
}
# Cerrar la libreria. Ojo: Close() devuelve los ventiladores al valor que vio al abrir;
# si ese valor era alto (cierre forzado anterior), no cerrar para que quede en 50%.
function Cerrar-Sensores { if (-not ($vent -and $ventInicial -ge $VENT_JUEGO)) { $pc.Close() } }

function Leer-Temp {
    $cpu.Update()
    $s = $cpu.Sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -eq 'CPU Package' } | Select-Object -First 1
    if (-not $s) { $s = $cpu.Sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -eq 'Core Max' } | Select-Object -First 1 }
    if ($s -and $s.Value) { [double]$s.Value } else { $null }
}

$base = (Get-CimInstance Win32_Processor | Select-Object -First 1).MaxClockSpeed
function Poner-Limite([int]$mhz) {
    $pct = if ($base -gt 0) { [math]::Min(100, [math]::Floor($mhz * 100 / $base)) } else { 100 }
    # Turbo encendido solo si el modo lo permite y el limite pasa de la velocidad base (3.6 GHz);
    # el limite en MHz tambien frena el Turbo (por ejemplo 3.9 GHz = Turbo hasta 3.9)
    $boost = if ($TURBO -gt 0 -and $base -gt 0 -and $mhz -gt $base) { $TURBO } else { 0 }
    powercfg /setacvalueindex $PLAN $SUB_CPU $CPU_MHZ $mhz | Out-Null
    powercfg /setacvalueindex $PLAN $SUB_CPU $CPU_MAX $pct | Out-Null
    powercfg /setacvalueindex $PLAN $SUB_CPU $CPU_BOOST $boost | Out-Null
    powercfg /setactive $PLAN | Out-Null
}

$actual = $MAX_MHZ
Poner-Limite $actual
Log ("Velocidad inicial: {0:N1} GHz (techo del modo)" -f ($actual / 1000))
if ($VENT_MODO -eq 'juego') { Poner-Ventilador $VENT_JUEGO }
elseif ($vent -and $ventInicial -ge $VENT_JUEGO) {
    # Quedo alto de un cierre forzado anterior: dejarlo como lo tiene la placa (50%)
    try { $vent.SetSoftware(50); Log "Ventilador de salida estaba en $ventInicial%: vuelto a 50% (placa)" } catch {}
}

$segCaliente = 0; $segFresco = 0; $ultimoCambio = [datetime]::MinValue
$hist = New-Object 'System.Collections.Generic.Queue[double]'
$resumen = Get-Date; $tMin = 999; $tMax = 0; $cambios = 0

while ((Modo-Actual) -eq $MODO -and -not (Test-Path $pararFile)) {
    $real = Leer-Temp
    if ($null -ne $real) {
        if ($real -lt $tMin) { $tMin = $real }; if ($real -gt $tMax) { $tMax = $real }
        # Promedio de las ultimas lecturas para decidir (ignora saltos de pocos segundos)
        $hist.Enqueue($real); while ($hist.Count -gt $PROMEDIO) { [void]$hist.Dequeue() }
        $t = [math]::Round(($hist | Measure-Object -Average).Average, 1)
        # Ventilador de salida
        if ($t -ge $VENT_TEMP_ALTA) { Poner-Ventilador $VENT_ALTO }
        elseif ($VENT_MODO -eq 'juego' -and $t -le $VENT_TEMP_ALTA - 4) { Poner-Ventilador $VENT_JUEGO }
        elseif ($VENT_MODO -ne 'juego' -and $t -le $VENT_TEMP_ALTA - 6 -and $ventActual -ge 0) { Soltar-Ventilador; Log "Ventilador de salida devuelto a la placa" }
        # Ventilador del CPU
        if ($t -ge $VENT_CPU_SUBE) { Subir-VentCpu } elseif ($t -le $VENT_CPU_SUELTA) { Soltar-VentCpu }
        # Velocidad del CPU
        if ($t -ge $CALIENTE) { $segCaliente += $INTERVALO; $segFresco = 0 }
        elseif ($t -le $FRESCO) { $segFresco += $INTERVALO; $segCaliente = 0 }
        else { $segCaliente = 0; $segFresco = 0 }   # zona de margen: se queda donde esta

        $puede = ((Get-Date) - $ultimoCambio).TotalSeconds -ge $ESPERA
        if ($real -ge $LIMITE -and $actual -gt $MIN_MHZ -and ((Get-Date) - $ultimoCambio).TotalSeconds -ge $INTERVALO * 2) {
            # Freno de emergencia (temperatura real, sin promediar): baja el doble y sin esperar los 10 s
            $actual = [math]::Max($MIN_MHZ, $actual - $PASO_URGENTE); Poner-Limite $actual; $ultimoCambio = Get-Date; $segCaliente = 0; $segFresco = 0; $cambios++
            Log ("{0} C (freno) -> baja a {1:N1} GHz" -f $real, ($actual / 1000))
        } elseif ($puede -and $segCaliente -ge $SEG_BAJAR -and $actual -gt $MIN_MHZ) {
            $actual -= $PASO; Poner-Limite $actual; $ultimoCambio = Get-Date; $segCaliente = 0; $cambios++
            Log ("{0} C -> baja a {1:N1} GHz" -f $t, ($actual / 1000))
        } elseif ($puede -and $segFresco -ge $SEG_SUBIR -and $actual -lt $MAX_MHZ) {
            $actual += $PASO; Poner-Limite $actual; $ultimoCambio = Get-Date; $segFresco = 0; $cambios++
            Log ("{0} C -> sube a {1:N1} GHz" -f $t, ($actual / 1000))
        }
    }
    # Modos de juego, PC sola (sin teclado/raton y sin juego abierto): volver a Normal fresco
    if ($MODO -in $MODOS_JUEGO) {
        $inactivo = [ModoGaming.Inactividad]::Minutos()
        if ($inactivo -ge $MIN_INACTIVO -and -not (Get-Process -Name $JUEGOS -ErrorAction SilentlyContinue)) {
            Log ("{0:N0} min sin usar la PC y sin juego abierto -> vuelve a Normal fresco" -f $inactivo)
            Soltar-Ventilador
            Soltar-VentCpu
            Cerrar-Sensores
            try { Start-ScheduledTask -TaskPath '\ModoGaming\' -TaskName 'normal' -ErrorAction Stop }
            catch { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'motor.ps1')`" -Modo normal" }
            $mutex.ReleaseMutex()
            exit 0   # el motor arranca el regulador de Normal fresco
        }
    }
    # Resumen cada 5 minutos
    if (((Get-Date) - $resumen).TotalMinutes -ge 5) {
        Log ("Resumen 5 min: temp {0}-{1} C, velocidad actual {2:N1} GHz, cambios {3}" -f $tMin, $tMax, ($actual / 1000), $cambios)
        $resumen = Get-Date; $tMin = 999; $tMax = 0; $cambios = 0
    }
    Start-Sleep -Seconds $INTERVALO
}

Log "Modo cambiado: regulador detenido."
Soltar-Ventilador
Soltar-VentCpu
Cerrar-Sensores
$mutex.ReleaseMutex()

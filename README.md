# Lenovo M710t Regulator (Modo Gaming)

Regulador térmico y modos de energía para la **Lenovo ThinkCentre M710t** (placa Lenovo 3102, chip ITE IT8628E)
con **Intel Core i7-7700**, pensado para jugar (por ejemplo ARC Raiders) sin que el CPU pase de **85 °C**.

> Proyecto personal, **no oficial y sin relación con Lenovo**. Úsalo bajo tu propio riesgo.

## Qué hace

- **Icono en la bandeja** para cambiar de modo con un clic (sin pedir administrador cada vez).
- **Regulador térmico en todos los modos** (menos "Windows original"):
  - sube el CPU hasta el techo del modo y lo baja de a 100 MHz al llegar a **84 °C**,
  - **freno a 85 °C**: baja 200 MHz de golpe,
  - vuelve a subir cuando baja de **80 °C**,
  - nunca baja de **2.9 GHz**.
- **Dos modos de juego con Turbo** (de 2.9 a **4.2 GHz**; el regulador enciende el Turbo solo cuando la temperatura lo permite):
  - **Gaming eficiente dinámico**: Turbo *eficiente*, sube cuando el juego lo pide y baja en menús y pausas (gasta menos con el mismo rendimiento jugando).
  - **Gaming dinámico**: Turbo *agresivo*, siempre a tope.
- **Ventilador de salida** (FANIN2) más fuerte al jugar: 80 %, y 90 % si el CPU llega a 82 °C. Al salir del modo vuelve al control de la placa.
- **Ventilador del CPU** (solo en Gaming eficiente dinámico): lo controla la placa; al llegar a 80 °C se pone al 100 % y bajo 75 °C se le devuelve a la placa. Nunca lo pone por debajo de lo que pone la placa.
- Al encender la PC arranca en **Normal fresco**. Si dejas la PC sola 20 minutos en un modo de juego (sin el juego abierto), vuelve sola a Normal fresco.
- **Windows original** deshace todo y deja Windows como estaba.

| Modo | Techo del CPU |
|---|---|
| Gaming eficiente dinámico | 4.2 GHz (Turbo eficiente) |
| Gaming dinámico | 4.2 GHz (Turbo agresivo) |
| Normal fresco / Alto rendimiento / Ahorro | 3.3 GHz |
| Gaming fresco / CPU suelto | 3.2 GHz |
| Windows original | sin regulador |

## Instalar

1. Descarga **`ModoGaming-Setup.exe`** de [Releases](../../releases).
2. Ábrelo y acepta el permiso de administrador.
   Windows puede mostrar "Windows protegió tu PC" porque no está firmado: **Más información → Ejecutar de todas formas**.
3. Busca el icono junto al reloj.

Para desinstalar: **Configuración → Aplicaciones → Modo Gaming**.

## Estructura

| Archivo | Para qué |
|---|---|
| `motor.ps1` | Aplica cada modo (planes de energía, servicios, programas) y arranca el regulador. |
| `gobernador.ps1` | Regulador térmico y control del ventilador de salida. |
| `*.bat` | Activan cada modo sin la app de la bandeja. |
| `Programa/ModoGaming.cs` | App de la bandeja. |
| `Programa/instalar.ps1`, `desinstalar.ps1` | Instalador (tareas programadas, Program Files). |
| `Programa/Setup.cs`, `compilar-setup.ps1` | Generan `ModoGaming-Setup.exe` (un solo archivo para compartir). |

Para compilar el Setup se necesita [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)
(`winget install LibreHardwareMonitor.LibreHardwareMonitor`) y luego ejecutar `Programa/compilar-setup.ps1`.

## En otras PCs

Los valores están ajustados para un i7-7700 con el Turbo controlado por el regulador.
En otro procesador funciona, pero los techos (3.2 / 3.3 / 4.2 GHz) pueden no ser los adecuados:
se cambian en `motor.ps1` (`$CPU_MHZ_LIMITE`, `$CPU_MHZ_FRESCO`, `$CPU_MHZ_LOOSE`, `$CPU_TURBO_MHZ`).
El control de los ventiladores **solo se activa en la placa Lenovo 3102**; en otras placas no se toca ningún ventilador.
En CPUs AMD el regulador puede no encontrar el sensor de temperatura.

## Créditos

Lectura de sensores y control de ventiladores con **LibreHardwareMonitorLib** (Mozilla Public License 2.0),
incluida sin modificar dentro de `ModoGaming-Setup.exe`.

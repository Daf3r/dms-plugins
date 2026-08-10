# Spike — camino HTTP para `claude-usage` en DMS

Fecha: 2026-08-10 · Tarea 1 del plan `2026-08-10-claude-usage-dms.md`

## Veredicto

**Gana `XMLHttpRequest` de QtQml.** Las cabeceras de respuesta son legibles desde dentro
de un plugin de DMS. `Daemon.qml` no necesita `Process` ni `curl`.

Consecuencia directa: **`parseRetryAfter` se usa**, y la §8 de la spec de Noctalia —la
única regla heredada que aquel port no podía cumplir— queda saldada.

## Qué se probó

Plugin desechable `SpikeHttp` (`type: widget`) con un `GET` sin token a
`https://api.anthropic.com/api/oauth/usage`, pintando `status` y si
`getResponseHeader("date")` devolvía algo.

Resultado observado en la barra: **`status=429 date=SI`**.

## Lo que se aprendió, aparte del veredicto

### 1. `Quickshell.Networking` no sirve, confirmado antes del spike

La doc de plugins de DMS (`advanced-patterns.md`) documenta un tipo `NetworkRequest` con
`url`, `method` y `onResponseReceived`. **No existe en Quickshell 0.3.0**: ese módulo es
NetworkManager — `address`, `autoconnect`, `connectWithPsk`, `connectivity`. Verificado
sobre `/nix/store/w3s69yqqgy1c4s82czlv3ygrc2j1jwwh-quickshell-0.3.0`.

Seguir esa doc al pie de la letra cuesta una tarde. Va en las restricciones globales del
plan.

### 2. El 429 fue autoinfligido, y valida la arquitectura

El spike lanzaba la petición desde `Component.onCompleted` de la **píldora**. Las píldoras
se instancian **una por pantalla**, y esta máquina tiene dos monitores: cada recarga
disparaba dos peticiones, y hubo varias recargas.

No es un defecto del endpoint: es la razón por la que §4 de la spec pone el E/S en un
daemon headless y no en el widget. Un `Daemon.qml` corre una vez; un `Widget.qml`
corre tantas veces como pantallas haya. **Ninguna petición debe salir nunca de
`Widget.qml`.**

### 3. `dms ipc plugins rescan` no existe

El target `plugins` expone `disable`, `enable`, `list`, `reload`, `status` y `toggle`. El
rescaneo vive en otro target: `dms ipc plugin-scan scan`.

Además `plugin-scan list` va con **debounce**: justo después de un `scan` devuelve
`count=0`, y solo lista el plugin unos segundos más tarde. Sin esa espera parece que el
descubrimiento ha fallado cuando no ha fallado.

Corregido en el plan y en los briefs de las tareas 1 y 3.

## Limpieza

`SpikeHttp` desactivado y su directorio borrado. Si la píldora sigue apareciendo en la
barra, quítala desde Ajustes → Dank Bar → Widgets: la colocación se guarda en
`settings.json`, que es mutable y no lo gestiona Nix.

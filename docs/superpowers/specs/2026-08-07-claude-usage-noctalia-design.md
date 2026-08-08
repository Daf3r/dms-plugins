# Diseño — plugin `claude-usage` para Noctalia

Fecha: 2026-08-07 · Estado: aprobado, pendiente de plan de implementación

Muestra en la barra de Noctalia el consumo de la suscripción de Claude, y desglosa las
ventanas de límite en un panel.

## 1. Problema

Claude Code solo expone el uso de la suscripción dentro de la sesión interactiva
(`/usage`). No hay subcomando de CLI — reverificado el 2026-08-07 en la 2.1.x: `claude
--help` no lista nada de uso, límites ni coste. La consecuencia práctica es llegar al
límite semanal sin verlo venir.

## 2. Origen: qué se hereda y qué se rehace

Este plugin **no se diseña desde cero**. Existe un trabajo previo al 85% en
`~/Projects/caelestia-plugins`, rama `feat/claude-usage` (`c47b2f1`, también en
`origin`), con su propia spec aprobada el 2026-08-03. Aquel plugin quedó bloqueado por
una razón ajena a su calidad: el sistema de plugins de Caelestia
([PR #1703](https://github.com/caelestia-dots/shell/pull/1703)) sigue sin mergear, y
daf3r migró a niri + Noctalia.

**Se hereda entero el diseño**, que es la parte cara: fuente de datos, modelo
normalizado, orden de criticidad, cadencia adaptativa, estados de error, ajustes,
antirrebote de notificaciones y la batería de casos de prueba.

**Se rehace el código.** Los plugins de Noctalia se escriben en Luau; el original era
QML + JavaScript. `logic.js` (506 líneas, 69 tests verdes, revisado a fondo tarea por
tarea) se traduce **función por función, conservando los nombres**, a `logic.luau`, y
sus 69 casos se portan como suite Luau. Es una transcripción vigilada por tests, no un
rediseño.

Lo que queda archivado en `caelestia-plugins`, sin borrar: `UsageService.qml`,
`Settings.qml`, `components/UsageRing.qml` y los `BarEntry`/`BarPopout` que nunca se
llegaron a escribir.

## 3. Fuente de datos

### 3.1 Primaria — API

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <claudeAiOauth.accessToken>
anthropic-beta: oauth-2025-04-20
```

El token sale de `~/.claude/.credentials.json` (modo `0600`). **Reverificado el
2026-08-07: HTTP 200**, con las claves `five_hour`, `seven_day`, `seven_day_opus`,
`seven_day_sonnet`, `seven_day_cowork`, `limits`, `extra_usage`, `spend` y varias más.

Es un endpoint **no documentado**. Puede cambiar sin aviso; por eso existe el respaldo
de §3.2 y los estados de error de §9.

### 3.2 Respaldo — caché local

`~/.claude.json` → clave `cachedUsageUtilization`, mismo esquema más `fetchedAtMs`.
Claude Code lo refresca solo en ciertos eventos, no periódicamente: medido el
2026-08-03, llevaba **4 días** sin actualizarse y marcaba 21 % semanal cuando el valor
real era 88 %.

Por eso es respaldo y nunca fuente primaria, y por eso todo dato procedente del caché se
pinta atenuado y con su antigüedad visible. **Solo se lee y parsea cuando la API falla.**

### 3.3 Descartado — contar tokens desde los transcripts

El enfoque de `ccusage` (sumar `usage` de `~/.claude/projects/**/*.jsonl`) da coste
estimado, no porcentaje de la ventana de suscripción. Verificado el 2026-08-07: los
transcripts traen tokens de entrada/salida/caché por mensaje, pero **ningún campo de
límite ni de reset** — esos solo existen en el servidor. Responde a la pregunta
equivocada: queremos "¿me lanzo a esta tarea o me quedo sin cuota?", no "¿cuánto habría
costado por API?".

## 4. Arquitectura

Tres entradas del manifiesto, con un único dueño del estado:

```
service.luau  ── http · readFile · temporizador · notify · writeFile(antirrebote)
     │            publica UN objeto ya calculado en noctalia.state
     ├──→ widget.luau   state.watch → barWidget.render()
     └──→ panel.luau    state.watch → panel.render()
```

El servicio es headless y arranca con el shell. Esa es la propiedad que importa:
**quitar el widget de la barra no apaga el sondeo ni las notificaciones.** El plugin
`lowcache/claude-companion` de la comunidad llegó de forma independiente a la misma
conclusión y la documenta en su README, lo que da confianza en que es el patrón
esperado y no una interpretación forzada.

La UI no evalúa severidad, no ordena y no formatea fechas. Lee campos. Si cambia la
regla de "estar en aviso", cambia en un sitio.

### 4.1 Ficheros

| Fichero | Responsabilidad |
| --- | --- |
| `plugin.toml` | Metadatos, tres entradas, ajustes de §10 |
| `logic.luau` | Lógica pura, **cero API host**: normalizar, ordenar, formatear, cadencia, notificaciones |
| `service.luau` | E/S, temporizador, estado, notificación |
| `widget.luau` | Entrada `[[widget]]` |
| `panel.luau` | Entrada `[[panel]]` |
| `translations/en.json`, `es.json` | Textos |
| `tests/` | Los 69 casos portados + fixtures anonimizados reutilizados |

`logic.luau` no importa nada del host. Es lo que permite correr la suite con el
intérprete `luau` sin levantar el shell.

### 4.2 Contrato de estado

Una sola clave, con todo precalculado y preformateado:

```lua
noctalia.state.set("usage", {
  status  = "ok",       -- ok | stale | expired | missing | loading
  source  = "api",      -- api | cache
  primary = { key = "weekly_all", label = "Semana", percent = 88,
              warning = true, glyph = "calendar",
              resetsRel = "en 10 h 34 min", resetsAbs = "mañana a las 07:00" },
  others  = { ... },    -- ya ordenados por criticidad
  hiddenWarning = true,
  extraUsage = { ... },
  fetchedAtLabel = "hace 12 s",
})
```

**Orden de criticidad:** por rango de severidad y, a igualdad, por porcentaje
descendente. Rango: `normal` = 0, `warning` = 1, `critical` = 2. **Una severidad
desconocida se trata como 2**, para que un estado nuevo de la API nunca se ignore en
silencio.

Desempate: el ledger de la tarea 4 dejó anotado que `byCriticality` devuelve 0 en empate
total y depende de que el `sort` sea estable. **En Luau `table.sort` NO es estable**, así
que el port debe añadir el tercer criterio explícito por índice en `PRIMARY_KINDS` que
aquel informe ya proponía. Sin él, el glifo de la barra alternaría entre sesión y semana
entre refrescos con el mismo dato.

## 5. Widget de barra

La spec original codificaba la ventana en **la forma del anillo** — arco abierto de 270°
para la sesión, anillo cerrado para la semana — precisamente para que ambas siguieran
distinguiéndose cuando el color se pusiera rojo en las dos. Eso era un `Shape`/`Canvas`
de QML.

**El vocabulario `ui.*` de los plugins de Noctalia no tiene arco ni canvas**
(`column`, `row`, `box`, `label`, `markdown`, `glyph`, `image`, `separator`, `spacer`,
`progress`, `button`, `graph`, `input`, `select`, `slider`, `toggle`, `scroll`,
`dragSource`, `dropZone`). El anillo no es portable.

Se conserva la intención con los canales que existen:

```lua
ui.row({ fill = "error/0.25", radius = 8, paddingH = 6, align = "center" }, {
  ui.glyph({ name = "hourglass", size = 14, color = "error" }),
  ui.label({ text = "88", color = "error", fontWeight = "bold" }),
})
```

- **Qué ventana es** → el glifo: `hourglass` para la sesión de 5 h, `calendar` para la
  semana. Los sublímites por modelo nunca ocupan el widget.
- **Estado de aviso** → el rol de color del tema y la píldora tintada.
- **Porcentaje** → la etiqueta, sin símbolo, según `show_remaining` (§10).
- **Hay algo peor escondido** → un segundo glifo pequeño, equivalente al punto de 4 px
  del original. Es la única forma de que un sublímite por modelo al 95 % no pase
  desapercibido.

Identidad de ventana y severidad siguen viajando por canales distintos, que era la
propiedad que el anillo protegía.

El árbol debe quedarse en **un control de alto**: la cápsula recorta al grosor de la
barra. Los controles de teclado (`input`, `select`, `scroll`) no están disponibles ahí.

**Interacción:** un clic **alterna el panel** (`noctalia.togglePanel`), y **además**
dispara un refresco inmediato cuando la acción es de apertura. Cerrar no refresca. No
hay acción distinta para "solo refrescar" desde el widget: para eso está el botón del
pie del panel (§6).

Se abandona el "abrir al pasar el ratón" del original. Aquello seguía la convención de
Caelestia; la de Noctalia es el clic, y un panel que se abre solo al cruzar la barra es
ruidoso en un widget que la mayor parte del tiempo no necesitas mirar.

**Visibilidad:** el widget se oculta por completo si no hay credenciales (§9).

## 6. Panel

Layout P2 heredado — la ventana crítica manda, el resto en lista fina. Dimensiones
declaradas en el manifiesto (`width = 340`, `placement = "floating"`), que en Noctalia
son propiedad del host, así que la superficie nace bien dimensionada.

```
┌────────────────────────────────┐
│  📅 Semana              88 %   │  tarjeta destacada
│  ▰▰▰▰▰▰▰▰▰▱                    │  ui.progress
│  mañana a las 07:00 · en 10 h  │
├────────────────────────────────┤  ui.separator
│  Sesión 5 h              42 %  │  ui.row + ui.label
│  Opus · semanal          12 %  │
├────────────────────────────────┤
│  Créditos extra   $2.40/$30.00 │  solo si aplica
├────────────────────────────────┤
│  hace 12 s          ⟳ Refrescar│  ui.button
└────────────────────────────────┘
```

1. **Tarjeta destacada** del límite más crítico entre los `primary`. `ui.progress`,
   porcentaje, etiqueta y reinicio en absoluto y relativo.
2. **Filas de una línea** para el resto, incluidos los sublímites por modelo.
3. **Créditos extra**, solo si `extra_usage.is_enabled` o `credits_ever_enabled`.
   Formatea `spend.used` / `spend.limit` con `amount_minor` y `exponent`; si está
   desactivado, muestra el motivo traducido.
4. **Pie**: antigüedad del dato y botón de refrescar.

Los bloques 2 y 3 se ocultan desde ajustes (§10). Las horas siempre en local; la API las
da en UTC con offset.

**Formato relativo:** < 60 min → "en 34 min"; < 24 h → "en 10 h 34 min"; resto →
"en 2 d 4 h". Ya vencido → "reiniciando…". `formatAbsolute` devuelve cadena vacía para
un reset vencido, así que la UI se apoya en ese "reiniciando…" para el hueco.

## 7. Cadencia

Adaptativa por severidad, con `noctalia.setUpdateInterval`. **Cuidado con la unidad: el
host trabaja en milisegundos y `logic.luau` en segundos.** La conversión vive en un solo
sitio, comentada.

- **Reposo:** 300 s (~288 peticiones/día).
- **Alerta:** 60 s, cuando algún límite supera el umbral o tiene `severity != normal`.

Refresco inmediato al abrir el panel (venga del widget o de `noctalia msg`) y con el
botón del pie. Cerrar el panel no refresca.

El ledger de la tarea 10 dejó avisado que dos refrescos seguidos a 300 ms colapsaban en
una sola carga. El refresco bajo demanda **no puede tragarse en silencio**: si hay una
petición en vuelo, el botón debe reflejarlo en vez de no hacer nada.

**Backoff:** ante fallo de red o 5xx, el intervalo se duplica hasta un techo de 1800 s, y
vuelve al valor normal en cuanto una petición tiene éxito. `MAX_INTERVAL` techa **solo**
el backoff, nunca la base elegida por el usuario — corrección que costó la tarea 9b y no
debe reintroducirse.

`noctalia.http` respeta el `offline_mode` del shell, así que el sondeo se corta solo
cuando el usuario pone el shell sin red.

## 8. Fidelidad: lo único que el port no puede cumplir

```lua
export type HttpResponse = { ok: boolean, status: number, body: string }
```

**No hay cabeceras de respuesta.** `Retry-After` es ilegible desde un plugin de
Noctalia. La spec original (§6) exigía respetarlo ante un 429.

En el port, `parseRetryAfter` **se elimina** y un 429 cae al backoff por duplicación.
Es exactamente el mínimo que el ledger de la tarea 6 prescribía como aceptable
(*"soportar ambos formatos o, como mínimo, caer a un backoff propio"*), y de paso
cierra el carry-forward pendiente sobre el formato HTTP-date, que deja de aplicar.

**Va documentado en `service.luau` junto al manejo del 429**, no enterrado aquí. Es la
única regla de la spec heredada que no se cumple al pie de la letra.

## 9. Estados y errores

| Condición | Widget | Panel |
| --- | --- | --- |
| Dato fresco de la API | Píldora normal | "Actualizado hace 12 s" |
| API caída, hay último valor bueno | Píldora atenuada | "Sin conexión · dato de hace 8 min" |
| API caída, sin valor, hay caché | Píldora atenuada | "Caché local · hace 4 días" |
| 401 / 403, o `expiresAt` vencido | Glifo de llave, sin número | "Sesión caducada. Abre Claude Code para renovarla." |
| `.credentials.json` ausente o ilegible | Widget oculto | — |
| Arranque, sin intento completado | Píldora atenuada vacía | "Cargando…" |
| JSON corrupto en cualquier fuente | Como fuente no disponible | Mismo mensaje que "sin conexión" |

`status = "stale"` con `primary` nulo significa **sin conexión y sin dato**: se pinta
"Sin conexión", no una píldora al 0 %. Era un carry-forward explícito de las tareas
11-13.

El token se considera vencido si `now > expiresAt - 60 s` (`TOKEN_MARGIN_MS`); en ese
caso ni se intenta la petición. `loading` significa solo "arranque sin intento
completado" y nunca es terminal.

Ningún error deja el widget mostrando un número sin marcar su procedencia y su
antigüedad.

## 10. Ajustes

Declarados en `plugin.toml`. Los tipos del manifiesto cubren los seis originales sin
ceder nada:

| Ajuste | Tipo | Rango | Por defecto |
| --- | --- | --- | --- |
| `warn_threshold` | `int` | 50–99 | `90` |
| `idle_interval` | `int` (s) | 60–3600 | `300` |
| `alert_interval` | `int` (s) | 15–600 | `60` |
| `show_scoped_limits` | `bool` | — | `true` |
| `show_extra_usage` | `bool` | — | `true` |
| `show_remaining` | `bool` | — | `false` (muestra consumido) |

El **estado de aviso** es una sola noción, evaluada en `logic.luau`:
`severity != normal or percent >= warn_threshold`. Gobierna a la vez el color del widget,
el glifo indicador, el salto a cadencia de alerta y la notificación, para que no existan
tres definiciones distintas de "estar cerca del límite".

Los valores por defecto viven en `logic.luau` (`DEFAULT_WARN_THRESHOLD`,
`DEFAULT_IDLE_INTERVAL`, `DEFAULT_ALERT_INTERVAL`) y el manifiesto los repite. Es una
duplicación conocida y aceptada: el parser del manifiesto no puede leer Luau. Cualquier
cambio toca los dos sitios, y hay un test que compara ambos.

## 11. Notificaciones

`noctalia.notify` con resumen `Claude` y cuerpo
`90 % de la ventana semanal consumido · se reinicia mañana a las 07:00`.

Cubre **todos** los límites, incluidos los de modelo (nombrándolo), no solo el que cabe
en el widget.

**Antirrebote:** se persiste en `noctalia.pluginDataDir()/state.json` (creado con
`mkdirAll`, escrito con `writeFile`) un registro por límite: `{key, resetsAt, notified}`.
Se notifica una sola vez por ventana; reiniciar el shell no vuelve a notificar, y cuando
`resetsAt` cambia el aviso se rearma solo. El fichero no guarda ningún dato de cuenta.

Las notificaciones **no se emiten a partir de datos de caché**: el ledger de la tarea 10
observó un aviso disparado por un dato de una hora antes. Solo `source == "api"` notifica.

## 12. Seguridad

- Lectura estricta de `.credentials.json`. El plugin **nunca escribe** en él.
- **El plugin nunca renueva el token.** Los refresh tokens de este flujo rotan;
  renovarlo desde aquí invalidaría el de Claude Code y rompería la sesión del usuario.
- El token viaja solo en la cabecera `Authorization`, vía `headers` de `HttpRequest`.
  Nunca a argv, ni a `noctalia.log`, ni a la UI, ni a mensajes de error.
- Única petición saliente: `GET api.anthropic.com/api/oauth/usage`.
- `allow_insecure_tls` se deja en su valor por defecto (false). Nunca se activa.
- Los fixtures heredados ya están anonimizados: sin `accountUuid`, sin correo, sin
  identificadores de organización. Se reutilizan tal cual.

## 13. Pruebas y entorno

`logic.luau` se prueba con el intérprete `luau` contra los fixtures heredados. Los 69
casos se portan uno a uno; la suite es el criterio de que la traducción es fiel.

Casos que la suite cubre y que no deben perderse: payload normal; con `severity:
"warning"`; con `extra_usage` activo; con `limits: []` cayendo a `five_hour`/`seven_day`;
con campos nulos y una severidad desconocida rankeada como crítica; JSON corrupto;
credenciales vencidas; antirrebote con mismo y con distinto `resetsAt`; los cuatro tramos
del formato relativo incluido el vencido; precedencia y suelo de intervalos.

**Casos nuevos que el port necesita** y el original no tenía:
- Empate total en `byCriticality` — `table.sort` de Luau no es estable (§4.2).
- Conversión segundos ↔ milisegundos de la cadencia.
- Coherencia entre los valores por defecto de `logic.luau` y los de `plugin.toml`.

`luau` está en nixpkgs (**0.703**, verificado el 2026-08-07). Se añade un devshell
`noctalia-plugins` a `~/nixos-config/devshells/default.nix`, siguiendo el patrón de los
de RemesaFam y gymnova, con su `.envrc` de una línea en el repo.

La capa de UI se valida a mano contra el shell instalado: los siete estados de §9
forzados con fixtures inyectados.

## 14. Fuera de alcance en la v1

- **Proyección de ritmo** ("a este ritmo agotas la semana el martes"). Requiere
  histórico local y arranque en frío. Con `ui.graph` disponible es más atractivo que
  antes, pero sigue siendo v2.
- Histórico y gráficas de consumo.
- Coste por tokens a partir de los transcripts (§3.3).
- Renovación del token OAuth.
- Múltiples cuentas de Claude.
- Publicación en el catálogo `community-plugins`. El plugin respeta el formato estándar
  (`plugin.toml`, `translations/`) para que publicarlo después sea añadir ficheros
  —thumbnail, README, más idiomas— y no reescribir.

## 15. Compatibilidad

Noctalia **5.0.0** (verificado). El manifiesto declara `plugin_api = 3`, el nivel más
antiguo que cubre `[[widget]]`, `[[panel]]`, controles `ui.*` y `barWidget.render`. La
entrada `[[service]]` necesita además una build que incluya ese tipo de entrada
(Noctalia 5 beta, rev `da014f72` o posterior) — la instalada lo trae, y el plugin
`claude-companion` lo confirma en producción.

No colisiona con `lowcache/claude-companion`: aquel es un lanzador con pulso de atención
que lee `.credentials.json` solo para comprobar caducidad, y no consulta
`/api/oauth/usage` ni los límites. Son complementarios.

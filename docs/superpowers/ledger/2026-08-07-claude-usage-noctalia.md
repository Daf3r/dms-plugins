# Ledger — `claude-usage` para Noctalia

Desviaciones respecto al plan (`../plans/2026-08-07-claude-usage-noctalia.md`) y
al spec (`../specs/2026-08-07-claude-usage-noctalia-design.md`), con el motivo.
El plan es la autoridad: lo que se aparta de él se anota aquí, no se decide en
silencio.

---

## Task 1 — Devshell, andamiaje y arnés de pruebas

### 1. El `sudo nixos-rebuild switch` del Step 2 no se ejecuta

**Plan:** aplicar la configuración con `sudo nixos-rebuild switch --flake ~/nixos-config`
antes de poder usar `luau`.

**Realidad:** `devShells.x86_64-linux` es una salida del flake independiente de
`nixosConfigurations` (`~/nixos-config/flake.nix:54` frente a `:58`). Un devshell
no forma parte del sistema y no requiere activarlo: `nix develop
~/nixos-config#noctalia-plugins` lo evalúa directamente.

**Por qué importa además:** en el momento de ejecutar la tarea, `~/nixos-config`
tenía trabajo en vuelo sin commitear en `apps.nix`, `gaming.nix`, `home.nix` y
dos ficheros nuevos en `pkgs/`. Un `switch` habría aplicado todo eso al sistema
vivo como efecto colateral de añadir un intérprete de Luau.

**Decisión:** verificar con `nix develop`. El `switch` queda a cargo del usuario
cuando cierre ese trabajo.

### 2. `luau` no acepta `--version`

**Plan:** `luau --version` debía imprimir `0.703`.

**Realidad:** el binario REPL de Luau no tiene esa opción; responde
`Error: Unrecognized option '--version'` y el uso. La versión se confirma por la
ruta del store (`/nix/store/…-luau-0.703/bin/luau`).

**Decisión:** el `shellHook` del devshell interpola `${pkgs.luau.version}`, que
Nix resuelve en tiempo de evaluación, en vez de preguntárselo al binario.

### 3. `os.exit` no existe: los ficheros de test cierran con `h.finish()`

**Plan:** cada fichero de test termina con `os.exit(if h.report() then 0 else 1)`.

**Realidad:** la tabla `os` del CLI de `luau` expone únicamente `clock`, `date`,
`difftime` y `time`. `os.exit` es `nil`, así que esa línea lanzaría «attempt to
call a nil value» en las doce tareas del plan.

**Decisión:** el arnés gana `M.finish()`, que imprime el informe y, si hubo
fallos, lanza un `error(msg, 0)`. Un error no capturado hace salir al intérprete
con código 1, que es lo que `run.fish` necesita. `M.report()` conserva su firma
`-> boolean` tal como prometía el contrato de la Task 1.

**Consecuencia para las tareas 2–12:** donde el plan escriba
`os.exit(if h.report() then 0 else 1)`, va `h.finish()`.

### 4. Comentarios del devshell en inglés

`~/nixos-config/devshells/default.nix` tiene todos sus comentarios en inglés; el
fragmento del plan venía en español. Se sigue la convención del fichero.

---

## Task 2 — Normalización del payload

### 5. El epoch esperado de `parseIsoMs` estaba mal

**Plan:** `h.eq(Logic.parseIsoMs("2026-08-07T05:00:00Z"), 1786251600000)`.

**Realidad:** `1786251600000` corresponde a **2026-08-09**T05:00:00Z, dos días
más tarde. El epoch de `2026-08-07T05:00:00Z` es `1786078800000`, verificado
tanto por aritmética como por `os.time` del propio intérprete.

**Decisión:** el test usa `1786078800000`. La misma constante equivocada aparece
en la Task 6 como valor de `NOW`; allí es un instante arbitrario y solo el
comentario queda desfasado, pero conviene corregirlo al llegar.

### 6. `os.time` de Luau es UTC, no hora local

**Plan:** el comentario de `localUtcOffsetSeconds()` dice que hace falta «restar
el offset porque `os.time` interpreta en hora local».

**Realidad:** `os.time` de Luau usa `timegm`, no `mktime`. Devuelve el mismo
valor bajo `TZ=Europe/Madrid` y `TZ=UTC`, y coincide con el epoch UTC real.
`os.date("*t", …)` **sí** es local (05:00Z se lee como 07:00 en Madrid en
agosto), así que las dos funciones no comparten semántica.

**Decisión:** `localUtcOffsetSeconds()` se conserva tal cual. Devuelve 0 aquí,
pero la fórmula `t - utc` da el desfase correcto en cualquiera de las dos
semánticas, así que el parseo no depende de cuál esté vigente. Solo se corrige
el comentario.

**Consecuencia para la Task 4:** su helper de test `ms(...)` construye el ancla
con `os.time`, es decir en **UTC**, mientras que `formatAbsolute` lee la fecha
con `os.date("*t")`, es decir en **local**. En `TZ=Europe/Madrid` eso son dos
horas de desfase y los tests fallarían. El helper tendrá que convertir de hora
local a epoch explícitamente.

### 7. Tests añadidos para `parseIsoMs`

El plan avisa de que es la función más frágil del port, y solo cubría el caso
`Z` y la basura. Se añaden los casos de offset explícito (`+00:00`, `+02:00`,
`-05:00`), fracción de segundo y offset sin dos puntos (`+0200`). No cambian la
implementación: ejercitan ramas que el plan ya escribía.

### 8. `run.fish` pasa `luau-analyze` antes de los tests

**Plan:** el lanzador solo ejecuta los `*.test.luau`.

**Motivo del añadido:** `logic.luau` lleva `--!strict`, pero el intérprete no
comprueba tipos — solo `luau-analyze`. Sin ese paso las anotaciones del plan son
decorativas. Al ejecutarlo por primera vez apareció un error real: inicializar
`extraUsage = nil` en el constructor de `normalizeUsage` hacía que Luau
infiriese el campo como `nil` y rechazase la asignación del final. Se corrige
anotando la tabla como `{[string]: any}` y omitiendo el campo del constructor;
el comportamiento en ejecución no cambia.

---

## Task 4 — Formateadores

### 9. El helper `ms()` de los tests convierte de hora local a epoch

**Plan:**

```lua
local function ms(y, mo, d, hh, mm)
  return os.time({ year = y, month = mo, day = d, hour = hh, min = mm, sec = 0 }) * 1000
end
```

**Realidad:** eso construye el epoch **en UTC** (ver desviación 6), mientras que
`formatAbsolute` lee la fecha con `os.date("*t")`, que es **local**. En
`TZ=Europe/Madrid` y en agosto son dos horas: `ms(2026, 8, 7, 19, 30)` se
formatearía como «a las 21:30» y los seis tests del bloque fallarían.

**Decisión:** el helper descuenta el desfase de la zona en ese instante, de modo
que las anclas del plan siguen leyéndose como hora local de Madrid, que es lo
que su comentario ya decía. La implementación de `formatAbsolute` no cambia: su
mezcla de `os.date` local y `os.time` UTC es correcta, porque solo usa la
*diferencia* entre dos medianoches y ambas sufren la misma transformación.

**Añadido:** un test de entorno que comprueba que el ancla se lee como las 09:00
del día 7. Si el fichero se ejecuta fuera de `run.fish`, sin `TZ` fija, falla
ahí en vez de en seis sitios con mensajes de hora incomprensibles.

---

## Task 5 — Cadencia y backoff

### 10. Un `nil` dentro de un constructor de tabla no se itera

**Plan:** `for _, bad in { nil, 0, -5, 0/0, "300" } :: any do`.

**Realidad:** ese constructor deja el índice 1 vacío. La iteración generalizada
de Luau recorre la tabla con `next`, que **salta los huecos**, así que el caso
`nil` —el ajuste sencillamente ausente, que es el más probable de todos— nunca
se ejercitaría. `#t` sobre una tabla con hueco tampoco está definido.

**Decisión:** el ajuste ausente va en su propio test, omitiendo la clave del
constructor de `state`, que es exactamente lo que el host entregaría. La lista
de basura conserva el resto y se amplía con `math.huge`, `{}` y `true`. El
mismo patrón aparece en la Task 6 y se corrige igual.

---

## Task 7 — Notificaciones y antirrebote

### 11. `NOW` y `RESET` son horas locales, y el helper sube al arnés

**Plan:** `local NOW = os.time({...}) * 1000`, igual que en la Task 4.

**Realidad:** el cuerpo esperado de la notificación dice literalmente «se
reinicia mañana a las 07:00», lo que solo se cumple si el ancla es hora local.
Misma causa que la desviación 9.

**Decisión:** el helper pasa a ser `h.localMs` en `harness.luau`, y tanto
`format.test.luau` como `notifications.test.luau` lo usan. Vive ahí porque
codifica un detalle de Luau —`os.time` es UTC, `os.date("*t")` es local— que
no debe volver a deducirse en cada fichero.

### 12. El test de «entrada nil en la lista» no ejercitaba nada

**Plan:** `Logic.notificationsFor({ nil, limit(...) })`, para comprobar la
guarda `if type(limit) ~= "table" then continue end`.

**Realidad:** misma causa que la desviación 10 — el `nil` deja un hueco que la
iteración se salta, así que la guarda nunca llegaba a ejecutarse.

**Decisión:** la lista lleva valores no-tabla reales (`false`, `"basura"`, `42`)
delante del límite bueno. Se añaden además dos casos que el plan no cubría: un
`prevState` que no es tabla, y un `nowMs` inválido (que debe omitir la cláusula
«se reinicia …» igual que un `resetsAt` ausente).

---

## Task 8 — Manifiesto y traducciones

### 13. El intérprete de Luau no tiene `io`: el test no podía abrir el TOML

**Plan:** el test lee el manifiesto con `io.open("claude-usage/plugin.toml")`.

**Realidad:** el CLI de `luau` está sandboxeado. `io` es `nil` por completo, y
`os.getenv` tampoco existe, así que un test no puede leer ningún fichero ni
averiguar dónde está. El test, tal como estaba escrito, no habría llegado ni a
fallar por la razón prevista: habría reventado en `io.open`.

**Decisión:** `run.fish` empaqueta `plugin.toml` como módulo Luau
(`tests/manifest.fixture.luau`, un `return { toml = [==[ … ]==] }`) antes de
lanzar la suite, y el test lo consume con `require`. Las aserciones son las
mismas que las del plan: el fichero solo cambia de dónde saca el texto. El
módulo generado está en `.gitignore`.

**Consecuencia:** cualquier test futuro que necesite leer un fichero tendrá que
pasar por el mismo mecanismo.

### 14. Test añadido: los rangos del manifiesto respetan `MIN_INTERVAL`

El plan comprobaba que los *defaults* del TOML y de `logic.luau` no divergen,
pero no los *rangos*. Si el `min` de `alert_interval` bajase del
`MIN_INTERVAL = 15` de la lógica, el usuario podría fijar un valor que
`nextInterval` recorta en silencio. Un test lo fija.

---

## Task 9 — El servicio

### 15. `plugin_api` sube de 3 a 12

**Plan:** el manifiesto declara `plugin_api = 3`, razonando que es «el nivel más
antiguo que cubre `[[widget]]`, `[[panel]]`, los controles `ui.*` y
`barWidget.render`». El servicio, sin embargo, llama a `noctalia.nowMs()`.

**Realidad:** `noctalia.d.luau` marca `nowMs` como **Plugin API 12**. Declarar 3
y llamarla es una contradicción del propio plan: o el host la niega y el
servicio revienta, o el manifiesto miente sobre lo que el plugin necesita.

Se comprobó también lo otro que el plan daba por supuesto: `[[service]]` sí
existe en el nivel 3 (`timer` y `screen_recorder` lo declaran así), y
`ui.progress`, `ui.separator` y `ui.spacer` están todos en `noctalia.d.luau`
—los dos primeros riesgos de la auto-revisión del plan quedan descartados—.

**Decisión:** `plugin_api = 12`. La alternativa era sustituir `nowMs` por
`os.time() * 1000`, que basta en precisión (todo son minutos y márgenes de
60 s), pero el modelo entero trabaja en milisegundos y `nowMs` es la API hecha
para eso. El test del manifiesto pasa a exigir `>= 12`.

### 16. Las entradas del host sí se pueden verificar sin levantar el shell

**Plan:** «`service.luau` es pegamento contra APIs del host que no se pueden
simular sin el shell. Se verifica ejecutando el shell.»

**Realidad:** parcialmente cierto —no se puede *ejecutar*— pero sí se puede
*comprobar*. Noctalia instala su fichero de definiciones en
`~/.local/state/noctalia/plugins/sources/official/repo/noctalia.d.luau`, y con
él las 226 líneas del servicio tipan contra la API real. El `luau-analyze` del
paquete `luau` no sirve: no tiene `--definitions`, eso es de `luau-lsp`, que se
añade al devshell.

**Decisión:** `run.fish` comprueba `service.luau`, `widget.luau` y `panel.luau`
con `luau-lsp analyze --definitions=…`. Si el fichero de definiciones no está
(otra máquina, Noctalia sin instalar), avisa por stderr y cae a una
comprobación de sintaxis con `luau-compile`, en vez de dar por buenas
seiscientas líneas sin mirar.

Los ficheros de entrada llevan `--!nolint FunctionUnused`: `update` y `onIpc`
son globals que llama el host, y `noctalia.d.luau` no las declara a propósito,
así que el linter las lee como código muerto.

### 17. `saveNotifyState` no comprobaba el fallo de `encode`

`noctalia.json.encode` devuelve `(string?, string?)`. El plan asignaba solo el
primer valor y lo pasaba directo a `writeFile`, que con `nil` reventaría. Se
añade la guarda.

---

## Task 10 — El widget de barra

### 18. Ocultarse es `setVisible(false)`, no `render(nil)`

**Plan:** `barWidget.render(nil) -- se oculta por completo (spec §9)`.

**Realidad:** `noctalia.d.luau` declara `render: (tree: UiNode) -> ()`. `nil` no
es un `UiNode`; `luau-lsp` lo rechaza con «Type 'nil' could not be converted
into 'UiNode'». La API para esto es `setVisible: (visible: boolean) -> ()`.

**Decisión:** el estado `missing` llama a `barWidget.setVisible(false)`. Como
la visibilidad es pegajosa, todos los demás caminos de `render()` tienen que
volver a llamar a `setVisible(true)` — si no, el widget desaparecería para
siempre en cuanto las credenciales faltasen una vez.

---

## Task 11 — El panel

### 19. `runAsync` recibe una cadena, no un array de argumentos

**Plan:**

```lua
noctalia.runAsync({ "noctalia", "msg", "plugin",
                    "daf3r/claude-usage:poller", "refresh" }, function() end)
```

**Realidad:** la firma es `runAsync: (cmd: string, onResult: ((result:
CommandResult) -> ())?, timeoutMs: number?) -> boolean`. El primer parámetro es
la línea de comando completa como una sola cadena; `luau-lsp` lo rechaza con
«Type '{any}' could not be converted into 'string'». La callback vacía también
sobra: sin ella, `runAsync` es un lanzamiento desatendido, que es justo lo que
se quiere.

**Decisión:**
`noctalia.runAsync("noctalia msg plugin daf3r/claude-usage:poller refresh")`.

Se confirmó además que no hay API de plugin a plugin en `noctalia.d.luau`, así
que pasar por el binario de Noctalia es efectivamente el camino, no un atajo.

### 20. `noctalia msg plugin` lleva un target obligatorio

**Plan:** `noctalia msg plugin daf3r/claude-usage:poller refresh`, tanto en el
panel como en el paso de verificación de la Task 9.

**Realidad:** la firma es
`plugin <author/plugin:entry> <target[:bar-name]> <event> [payload]`. Faltaba
el target: tal cual, `refresh` se lee como target y el evento se queda sin
poner. Los servicios oficiales usan `all` (README de bitwarden).

**Decisión:** `noctalia msg plugin daf3r/claude-usage:poller all refresh`, en el
panel y en `tests/MANUAL.md`.

### 21. `run.fish` pasa además el linter de autor de Noctalia

`noctalia plugins lint` es offline y no necesita el shell corriendo. Cruza los
ajustes declarados en `plugin.toml` contra las llamadas a `getConfig()` de las
entradas —un ajuste leído pero no declarado es un fallo ruidoso en ejecución— y
comprueba que cada `entry` apunta a un fichero que existe. Nada de eso lo ve
`luau-lsp`. Se ejecuta si `noctalia` está en el PATH. Resultado actual: 0
errores, 0 avisos.

---

## Task 12 — Validación de los siete estados

### 22. La validación queda escrita pero SIN ejecutar

`tests/MANUAL.md` recoge los siete casos con su procedimiento exacto y las
comprobaciones transversales, pero las columnas «Observado» y «Fecha» están
vacías: **nadie los ha pasado todavía**.

El motivo es que los casos 2 y 3 apagan la red de la máquina (`nmcli networking
off`) y los casos 4, 5 y 7 manipulan `~/.claude/.credentials.json`, que es el
fichero con el que se autentica la sesión de Claude Code desde la que se está
implementando esto. Son acciones sobre un escritorio en uso, no sobre un banco
de pruebas.

El symlink de desarrollo sí está puesto
(`~/.local/state/noctalia/plugins/materialized/daf3r-claude-usage`), que es
reversible con un `rm`. Habilitar el plugin, añadir el widget a la barra y
recargar el shell quedan pendientes del usuario.

---

## Cierre de cabos sueltos

El plan copiaba cuatro fixtures en la Task 1 y no volvía a mencionarlos, y
dejaba las traducciones sin ninguna comprobación. Ambos huecos se cierran aquí.

### 23. Los fixtures heredados ya se usan: `tests/fixtures.test.luau`

**Problema:** las Tasks 1 a 12 no cargan `tests/fixtures/*.json` en ningún
sitio, y con `io` ausente y sin parser de JSON tampoco podrían. Cuatro ficheros
de payload real de la API estaban en el repo como peso muerto.

**Decisión:** `tests/json2luau.py` los convierte a un módulo Luau y `run.fish`
lo genera antes de la suite. `fixtures.test.luau` los hace pasar por
`normalizeUsage` → `pickPrimary` → `sortForPanel` → `notificationsFor` → los
formateadores, y afirma sobre lo que el widget y el panel acabarían pintando.
Es lo más cerca de una prueba extremo a extremo que se puede llegar sin shell.

Lo que aporta y no cubrían los tests sintéticos: `parseIsoMs` contra el formato
**exacto** de la API (`2026-08-03T17:10:00.330605+00:00`, con microsegundos y
offset), que era el punto que la auto-revisión del plan marcaba como el más
frágil del port.

Detalles del conversor: un `null` de JSON se **omite** en vez de traducirse,
porque las tablas de Lua no guardan nil y la ausencia es justo lo que esperan
las guardas de `logic.luau`. El módulo no puede llamarse `fixtures.luau`:
`require("./fixtures")` sería ambiguo con el directorio `tests/fixtures/` y el
intérprete se niega.

`python3` se añade al devshell en vez de heredarlo del perfil de usuario, para
que la suite no dependa del PATH.

### 24. Traducciones comprobadas en los dos sentidos: `tests/translations.test.luau`

**Problema:** nada garantizaba que `es.json` y `en.json` tuvieran las mismas
claves, ni que las claves que usan el manifiesto y las entradas existieran. Una
clave ausente no revienta: el host cae al literal, y el usuario ve
`panel.refresh` escrito en la interfaz. Fallo silencioso.

**Decisión:** tres comprobaciones — paridad `es` ↔ `en` con valores no vacíos,
cada `label_key`/`description_key` del manifiesto traducido, y cada
`noctalia.tr("…")` de las entradas traducido.

### 25. La clave huérfana era el síntoma de un bug real

Al escribir lo anterior, `panel.updatedAgo` («hace {age}») resultó no usarla
nadie. La causa no era una traducción sobrante, sino esto en `service.luau`:

```lua
fetchedAtLabel = Logic.formatRelative(fetchedAt, nowMs)
```

`fetchedAt` está **siempre** en el pasado, y `formatRelative` mira hacia
adelante: con un delta `<= 0` devuelve `"reiniciando…"`. El pie del panel
habría dicho «reiniciando…» el 100 % de las veces, tanto con dato fresco como
con caché — nunca «hace 3 min», que es lo que la propia `MANUAL.md` del plan
daba como esperado.

**Decisión:** `logic.luau` gana `M.formatAge(pastMs, nowMs)`, pura y probada
(«3 s», «12 min», «2 h 5 min», «2 d 4 h»), que además satura a cero si el reloj
va hacia atrás. El servicio la envuelve con `noctalia.tr("panel.updatedAgo",
{ age = … })`, así que el texto vuelve a ser traducible. Un test deja fijado que
ninguna clave `panel.*` puede volver a quedarse huérfana sin que alguien mire
por qué.

### 26b. Hallazgos del primer arranque en el shell real

Al instalar el plugin en la Noctalia que corre en la máquina aparecieron tres
cosas que ningún análisis estático podía dar.

**El `require` del host y el del CLI son incompatibles.** El log soltó:

```
[ERR] plugin daf3r/claude-usage:poller: call to 'chunk' failed:
      require path must be relative and end in .luau
```

Noctalia **exige** la extensión; el intérprete `luau` suelto la **rechaza**
(«could not resolve child component»). No hay una forma que valga para los dos.
Como los ficheros de entrada solo los carga el host y los de `tests/` solo el
CLI, cada grupo usa la suya: `service.luau` y `panel.luau` requieren
`"./logic.luau"`, y los tests siguen con `"../logic"`. Queda comentado en los
dos sitios porque parece un descuido y no lo es.

**Un symlink en `plugins/materialized/` no registra nada.** Es lo que decía el
Step 2 de la Task 9 del plan, y el plugin no llegaba ni a aparecer en
`noctalia msg plugins list`. El registro se construye desde las *fuentes*, y
los plugins se materializan en `materialized/<fuente>/<plugin>`, no en plano.
Lo correcto es una fuente de tipo `path`:

```
noctalia msg plugins source add daf3r path ~/Projects/noctalia-plugins
```

Efecto secundario a tener en cuenta: al añadir una fuente, Noctalia escribe las
**tres** en `settings.toml`, incluidas las dos de fábrica. Declarar
`plugins.source` en nix sin repetir `official` y `community` las borraría, y con
ellas `noctalia/wallhaven`.

**El id de un widget de plugin en la barra es `author/plugin:entry`.** No está
documentado en el README del SDK y `noctalia config validate` no valida nombres
de widget (acepta hasta `meter` a secas), así que se determinó por el log:
Noctalia registra `widget.daf3r/claude-usage:meter`. La forma correcta aquí es
`daf3r/claude-usage:meter`.

### 26c. Verificado en vivo

Con el plugin cargado en la Noctalia real: las 3 entradas cargan, el servicio
arranca, un `refresh` por IPC trae dato de la API de Anthropic y el widget pinta
glifo + porcentaje en la barra (se observó subir de 45 a 47 entre dos sondeos).
`grep -ciE 'sk-ant|Bearer [A-Za-z0-9]'` sobre `~/.cache/noctalia/noctalia.log`
devuelve **0**: el token no se filtra.

Eso cubre por observación directa los casos 1 y 6 de `MANUAL.md`. Los otros
cinco siguen sin pasar, por lo dicho en la desviación 22.

### 26. Los tests nuevos se verificaron por mutación

No basta con que un test pase. Se comprobó que **falla cuando debe**: quitando
una clave de `en.json`, rompiendo `formatAge`, y cambiando la severidad de
`usage-warning.json`. Las tres mutaciones se detectan.

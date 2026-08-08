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

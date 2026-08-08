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

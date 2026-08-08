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

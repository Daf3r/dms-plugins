#!/usr/bin/env fish
# Lanzador de las pruebas de logic.luau.
# TZ fija: sin ella los formatos de hora no son deterministas (igual que en
# el run.fish original de Caelestia).
#
# `luau` viene del devshell noctalia-plugins de ~/nixos-config, que direnv
# activa al entrar en el proyecto. Fuera de direnv:
#   nix develop ~/nixos-config#noctalia-plugins -c fish claude-usage/tests/run.fish

set -l here (dirname (status --current-filename))
set -l plugin $here/..
set -lx TZ Europe/Madrid

if not command -q luau
  echo "luau no está en el PATH: entra al devshell noctalia-plugins" >&2
  exit 127
end

set -l status_total 0

# ── Comprobación estática ────────────────────────────────────────────────────

# logic.luau lleva --!strict, y el intérprete no comprueba tipos: solo
# luau-analyze lo hace. Sin este paso las anotaciones son decorativas.
luau-analyze $plugin/logic.luau; or set status_total 1

# service/widget/panel hablan con globals que inyecta el host, así que para
# luau-analyze son todo "unknown global". luau-lsp sí acepta el fichero de
# definiciones del SDK, y con él se comprueban sin levantar el shell. Ese
# fichero vive fuera del repo (lo instala Noctalia); si no está, se avisa y se
# comprueba solo la sintaxis, en vez de dar por buenas 600 líneas.
set -l defs ~/.local/state/noctalia/plugins/sources/official/repo/noctalia.d.luau
set -l entries
for name in service widget panel
  test -f $plugin/$name.luau; and set -a entries $plugin/$name.luau
end

if test (count $entries) -gt 0
  if test -f $defs
    luau-lsp analyze --definitions=$defs $entries; or set status_total 1
  else
    echo "# aviso: sin $defs, solo se comprueba la sintaxis de las entradas del host" >&2
    luau-compile --binary $entries > /dev/null; or set status_total 1
  end
end

# Noctalia trae su propio linter de autor, y es offline: cruza los ajustes que
# declara plugin.toml contra las llamadas a getConfig() de las entradas, y
# comprueba que cada `entry` apunta a un fichero que existe. Nada de eso lo ve
# luau-lsp. Solo está si Noctalia está instalado.
if command -q noctalia
  noctalia plugins lint $plugin; or set status_total 1
end

# ── Módulos generados ────────────────────────────────────────────────────────
#
# El intérprete de Luau está sandboxeado: no expone `io` ni `os.getenv`, así que
# un test no puede abrir un fichero por su cuenta. Todo lo que la suite necesita
# leer del disco se empaqueta antes como módulo Luau.

# 1. Texto del manifiesto y de las entradas, para hacerles string matching.
#    [===[ y no [==[ por si algún fuente contuviera ]==].
#
#    Siempre `printf '%s\n'`: el printf de fish NO trata `--` como fin de
#    opciones, así que un formato que empiece por guion se emite literal y
#    corrompe el módulo en silencio.
begin
  printf '%s\n' '-- GENERADO por tests/run.fish. No editar.'
  printf '%s\n' 'return {'
  printf '%s\n' '  toml = [===['
  test -f $plugin/plugin.toml; and cat $plugin/plugin.toml
  printf '%s\n' ']===],'
  printf '%s\n' '  entries = {'
  for name in service widget panel
    printf '    %s = [===[\n' $name
    test -f $plugin/$name.luau; and cat $plugin/$name.luau
    printf '%s\n' ']===],'
  end
  printf '%s\n' '  },'
  printf '%s\n' '}'
end > $here/manifest.fixture.luau

# 2. Payloads y traducciones: YA NO SE GENERAN. tests/json2luau.py se borró en
#    la tarea 6 del port. Existía solo porque el intérprete de Luau no parsea
#    JSON; node lee los .json directamente (ver tests/run-js.fish), así que el
#    conversor se quedó sin motivo.
#
#    Los dos módulos que producía (payloads.fixture.luau y
#    translations.fixture.luau) están en .gitignore, o sea que en un árbol
#    recién clonado no existen. Los .test.luau que los requieren se saltan en
#    ese caso, con aviso, en vez de reventar con MODULE_NOT_FOUND: el resto de
#    la suite Luau —la que sigue sirviendo de contraste mientras se traducen
#    service, widget y panel— no los necesita. Todo esto desaparece con el Luau
#    en la tarea 13. La suite equivalente en JS, que no se salta nada, es
#    tests/run-js.fish.

# ── Suite ────────────────────────────────────────────────────────────────────

for f in $here/*.test.luau
  # Qué módulo generado le falta a ESTE fichero. Se mira su `require`, no una
  # lista escrita a mano: la lista se queda vieja y el fallo sale como un
  # MODULE_NOT_FOUND que no explica nada.
  set -l base (basename $f)
  set -l missing
  for m in payloads translations
    if not test -f $here/$m.fixture.luau; and grep -q "$m.fixture" $f
      set -a missing $m.fixture.luau
    end
  end
  if test (count $missing) -gt 0
    echo "# saltado $base: falta $missing, que generaba tests/json2luau.py (borrado en la tarea 6). El sucesor en JS es tests/run-js.fish" >&2
    continue
  end
  luau $f; or set status_total 1
end
exit $status_total

#!/usr/bin/env fish
# Lanzador de las pruebas de logic.luau.
# TZ fija: sin ella los formatos de hora no son deterministas (igual que en
# el run.fish original de Caelestia).
#
# `luau` viene del devshell noctalia-plugins de ~/nixos-config, que direnv
# activa al entrar en el proyecto. Fuera de direnv:
#   nix develop ~/nixos-config#noctalia-plugins -c fish claude-usage/tests/run.fish

set -l here (dirname (status --current-filename))
set -lx TZ Europe/Madrid

if not command -q luau
  echo "luau no está en el PATH: entra al devshell noctalia-plugins" >&2
  exit 127
end

set -l status_total 0

# logic.luau lleva --!strict, y el intérprete no comprueba tipos: solo
# luau-analyze lo hace. Sin este paso las anotaciones son decorativas.
luau-analyze $here/../logic.luau; or set status_total 1

# service/widget/panel hablan con globals que inyecta el host, así que para
# luau-analyze son todo "unknown global". luau-lsp sí acepta el fichero de
# definiciones del SDK, y con él se comprueban sin levantar el shell. Ese
# fichero vive fuera del repo (lo instala Noctalia); si no está, se avisa y se
# siguen comprobando solo la sintaxis, en vez de dar por buenos 600 líneas.
set -l defs ~/.local/state/noctalia/plugins/sources/official/repo/noctalia.d.luau
set -l hostFiles
for name in service widget panel
  test -f $here/../$name.luau; and set -a hostFiles $here/../$name.luau
end

if test (count $hostFiles) -gt 0
  if test -f $defs
    luau-lsp analyze --definitions=$defs $hostFiles; or set status_total 1
  else
    echo "# aviso: sin $defs, solo se comprueba la sintaxis de las entradas del host" >&2
    luau-compile --binary $hostFiles > /dev/null; or set status_total 1
  end
end

# El intérprete de Luau está sandboxeado: no expone `io` ni `os.getenv`, así
# que un test no puede abrir plugin.toml por su cuenta. Se empaqueta como
# módulo para que manifest.test.luau pueda hacerle string matching.
set -l manifest $here/../plugin.toml
begin
  printf 'return { toml = [==[\n'
  if test -f $manifest
    cat $manifest
  end
  printf '\n]==] }\n'
end > $here/manifest.fixture.luau

# Noctalia trae su propio linter de autor, y es offline: cruza los ajustes que
# declara plugin.toml contra las llamadas a getConfig() de las entradas, y
# comprueba que cada `entry` apunta a un fichero que existe. Nada de eso lo ve
# luau-lsp. Solo está si Noctalia está instalado.
if command -q noctalia
  noctalia plugins lint $here/..; or set status_total 1
end

for f in $here/*.test.luau
  luau $f; or set status_total 1
end
exit $status_total

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

for f in $here/*.test.luau
  luau $f; or set status_total 1
end
exit $status_total

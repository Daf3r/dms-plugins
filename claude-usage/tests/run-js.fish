#!/usr/bin/env fish
# Lanzador de las pruebas en JavaScript (node --test) de i18n.js y logic.js.
# TZ fija: sin ella los formatos de hora no son deterministas (igual que en
# tests/run.fish, el runner de Luau).
#
# `node` viene del devshell dms-plugins de ~/nixos-config, que direnv activa
# al entrar en el proyecto. Fuera de direnv:
#   nix develop ~/nixos-config#dms-plugins -c fish claude-usage/tests/run-js.fish

set -l here (dirname (status --current-filename))
set -lx TZ Europe/Madrid

if not command -q node
  echo "node no está en el PATH: entra al devshell dms-plugins" >&2
  exit 127
end

# Se pasa el GLOB de ficheros, no el directorio: `node --test $here` falla con
# MODULE_NOT_FOUND en node v26.4.0 (el intérprete intenta cargar el
# directorio como si fuera un módulo en vez de listarlo).
node --test $here/*.test.js
exit $status

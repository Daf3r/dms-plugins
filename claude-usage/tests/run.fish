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

# 2. Payloads reales de la API, heredados de Caelestia. Luau no parsea JSON.
#    El módulo NO puede llamarse fixtures.luau: `require("./fixtures")` sería
#    ambiguo con el directorio tests/fixtures/ y el intérprete se niega.
if command -q python3
  python3 $here/json2luau.py $here/fixtures/*.json > $here/payloads.fixture.luau
  or set status_total 1
  python3 $here/json2luau.py $plugin/translations/*.json > $here/translations.fixture.luau
  or set status_total 1
else
  echo "# error: hace falta python3 para convertir los fixtures JSON a Luau" >&2
  set status_total 1
end

# ── Suite ────────────────────────────────────────────────────────────────────

for f in $here/*.test.luau
  luau $f; or set status_total 1
end
exit $status_total

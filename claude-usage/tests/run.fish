#!/usr/bin/env fish
# Lanzador de las pruebas de logic.js.
# TZ fija: sin ella los formatos de hora no son deterministas.

set -l here (dirname (status --current-filename))
set -lx TZ Europe/Madrid

# node --test $here (pasando el directorio) falla con MODULE_NOT_FOUND en
# node v26.4.0: intenta hacer require() del directorio en vez de recorrerlo.
# Reproducido tambien fuera de este repo, no es cosa del proyecto. Se pasa
# el glob de ficheros de test en su lugar, que node si soporta.
node --test $here/*.test.js

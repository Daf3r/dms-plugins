#!/usr/bin/env python3
"""Convierte ficheros JSON en un módulo Luau, para que la suite pueda usarlos.

Luau no parsea JSON y el intérprete está sandboxeado (no hay `io`), así que un
test no puede abrir un fixture por su cuenta. En producción eso lo resuelve
`noctalia.json.decode`, que aquí no existe. Este conversor lo suple: lo lanza
tests/run.fish antes de la suite y el resultado se consume con `require`.

    python3 json2luau.py a.json b.json > fixtures.luau

Produce `return { ["a"] = …, ["b"] = … }`, con la clave = nombre del fichero
sin extensión.

Un `null` de JSON se OMITE en vez de traducirse: las tablas de Lua no pueden
guardar nil, y omitir la clave es exactamente lo que `logic.luau` espera de un
campo ausente (sus guardas son todas `type(x) ~= "…"`). Un array vacío y un
objeto vacío colapsan ambos en `{}`, igual que ocurriría con cualquier decoder
de JSON a Lua; `normalizeUsage` distingue el caso mirando `#raw > 0`.
"""

import json
import os
import sys

ESCAPES = {
    "\\": "\\\\",
    '"': '\\"',
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
}


def lua_string(s):
    out = ['"']
    for ch in s:
        if ch in ESCAPES:
            out.append(ESCAPES[ch])
        elif ord(ch) < 0x20:
            out.append("\\%d" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def emit(value, indent=0):
    pad = "  " * indent
    inner = "  " * (indent + 1)

    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        # repr mantiene el 42.0 como 42.0; Luau lo lee igual (todo son doubles).
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)

    if isinstance(value, list):
        items = [v for v in value if v is not None]
        if not items:
            return "{}"
        body = ",\n".join(inner + emit(v, indent + 1) for v in items)
        return "{\n%s,\n%s}" % (body, pad)

    if isinstance(value, dict):
        items = [(k, v) for k, v in value.items() if v is not None]
        if not items:
            return "{}"
        body = ",\n".join(
            "%s[%s] = %s" % (inner, lua_string(k), emit(v, indent + 1))
            for k, v in items
        )
        return "{\n%s,\n%s}" % (body, pad)

    raise TypeError(f"tipo JSON no contemplado: {type(value)!r}")


def main(paths):
    print("-- GENERADO por tests/json2luau.py. No editar: se reescribe en cada")
    print("-- ejecución de tests/run.fish a partir de los .json de origen.")
    print("return {")
    for path in paths:
        name = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        print("  [%s] = %s," % (lua_string(name), emit(data, 1)))
    print("}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("uso: json2luau.py <fichero.json> [...]")
    main(sys.argv[1:])

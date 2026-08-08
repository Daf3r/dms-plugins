# Validación manual de los siete estados

`logic.luau` está cubierto por la suite automática. Los estados de error, no:
solo existen cuando algo del entorno falla, y forzarlos requiere el shell real
(spec §9). Esta es la lista, con el procedimiento exacto y hueco para anotar lo
observado.

> **Mientras corre esto, el widget enseña números inventados.** Los casos se
> fuerzan apuntando `service.luau` a un servidor local, así que durante la
> validación la barra NO muestra el uso real. Avisar antes de empezar y
> restaurar el endpoint al terminar.

**Pasada del 2026-08-08 sobre el build con i18n.** Las capturas viven fuera del
repo (directorio de sesión). El shell corría con `LANG=en_US` y sin idioma
fijado en `settings.toml`, así que lo observado está en inglés: es la prueba de
que el texto sale del catálogo y no del código.

## Antes de empezar

**Ya está declarado en `~/nixos-config/noctalia.nix`** y llega con el próximo
`sudo nixos-rebuild switch --flake ~/nixos-config`: la fuente local `daf3r`
(`kind = "path"`), el id en `plugins.enabled`, y el widget dentro del grupo
`status` de la barra.

> Un symlink a mano en `plugins/materialized/` **no** registra el plugin: el
> registro se construye a partir de las fuentes, así que sin la entrada
> `[[plugins.source]]` el plugin no aparece siquiera en
> `noctalia msg plugins list`. Los plugins se materializan además en
> `materialized/<fuente>/<plugin>`, no en plano.

Para probar sin rebuild (todo reversible, y escribe en `settings.toml`):

```bash
noctalia msg plugins source add daf3r path ~/Projects/noctalia-plugins
noctalia msg plugins enable daf3r/claude-usage
# …y para deshacerlo:
noctalia msg plugins disable daf3r/claude-usage
noctalia msg plugins source remove daf3r
```

Una fuente `path` vigila el directorio en vivo: tocar `service.luau` o
`logic.luau` recarga el servicio en caliente, sin rebuild ni reinicio del
shell.

**Trabajar sobre una copia de `.credentials.json`, nunca sobre el original.**

```bash
cp ~/.claude/.credentials.json ~/.claude/.credentials.json.bak
# …y restaurar tras CADA caso:
cp ~/.claude/.credentials.json.bak ~/.claude/.credentials.json
```

> Los casos 2 y 3 apagan la red, y el 4, 5 y 7 tocan el fichero de credenciales
> con el que esta misma sesión de Claude Code se autentica. Conviene hacerlos
> con calma y restaurar entre uno y otro.

## Los siete casos

| # | Estado | Cómo forzarlo | Esperado | Observado | Fecha |
|---|---|---|---|---|---|
| 1 | Dato fresco | Normal, tras un sondeo bueno | Píldora con glifo + número; pie «hace N s» | ✅ `⏳ 62` a brillo pleno, pico `#D0D0D0` | 2026-08-08 |
| 2 | Sin conexión, con dato | Servidor de laboratorio en 503 tras un sondeo bueno | Píldora atenuada; «Sin conexión · dato de hace N min» | ✅ Píldora a `#9B9B9B`; pie «Offline · 23 s ago», con el último valor bueno **de memoria** | 2026-08-08 |
| 3 | Sin conexión, sin dato | Igual, pero recargando el servicio antes para vaciar `lastModel` | «Caché local · hace N» | ✅ Pie «Local cache · 8 h 11 min ago» con los datos del disco (23/11/8) | 2026-08-08 |
| 4 | Token vencido | En la copia, poner `claudeAiOauth.expiresAt` en el pasado | Glifo `key-off`, sin número | ✅ **tras arreglar el choque `render()`/`setGlyph`** (ver abajo) | 2026-08-08 |
| 5 | Sin credenciales | Renombrar `.credentials.json` temporalmente | **Widget oculto por completo** | ✅ Desaparece del grupo entero | 2026-08-08 |
| 6 | Arranque | Endpoint apuntando a un socket que acepta y no responde | Glifo de indicador, sin número | ✅ Solo el glifo `gauge` | 2026-08-08 |
| 7 | Credenciales ilegibles | Fichero de credenciales con `{{{` | **Widget oculto**, igual que el caso 5, y **sin traza en el log** | ✅ Oculto; cero líneas nuevas en `noctalia.log` | 2026-08-08 |
| 7b | Respuesta corrupta de la API | Credenciales válidas y cuerpo HTTP 200 que no es JSON | Widget **visible**, atenuado, con el dato de caché | ✅ `⏳ 11` atenuado | 2026-08-08 |

> **La fila 7 estaba mal escrita.** Decía «igual que sin conexión», y lo que
> ocurre es lo contrario: unas credenciales ilegibles dan `status = "missing"` y
> el widget se **oculta**, como en el caso 5. Quien cae a «sin conexión» es la
> fila 7b, que es un caso distinto — credenciales buenas y respuesta rota.

### El defecto que encontró esta pasada

El caso 4 no pasaba: en vez del candado seguía viéndose la píldora anterior. La
causa está en el log del host, no en la lógica de credenciales:

```
plugin widget 'daf3r/claude-usage:meter': setText/setGlyph/setImage/setFont/
setColor have no visible effect while a render() tree is active
```

Las dos APIs del widget de barra son excluyentes: en cuanto se ha pintado un
`render()`, los `setGlyph`/`setText` se ignoran. Como la píldora normal usa
`render()`, los tres estados sin número —cargando, vencido y sin conexión sin
dato— se quedaban mudos y dejaban en pantalla el árbol anterior. Es decir: un
dato viejo presentándose como bueno, justo lo que el spec §9 prohíbe. Arreglado
pasando esos tres estados por `render()` (helper `glyphOnly` en `widget.luau`).

Vale la pena insistir en que **solo se ve corriendo el shell**: no hay test que
lo pille, porque el conflicto vive en el host.

## Comprobaciones transversales

**El servicio publica.**

```bash
noctalia msg plugin daf3r/claude-usage:poller all refresh
journalctl --user -n 40 --no-pager | grep -i claude-usage
```

Ojo con la firma: es `plugin <author/plugin:entry> <target> <event>`. El `all`
de en medio es obligatorio — sin él, `refresh` se lee como target y el evento se
queda sin poner.

**El panel abre y refresca.**

```bash
noctalia msg panel-toggle daf3r/claude-usage:detail
```

Comprobar la barra de progreso, las filas de sublímites, el bloque de créditos
extra y que el botón de refrescar mueve la etiqueta de antigüedad del pie.

**El umbral tiñe.** Bajar `warn_threshold` a 1 desde los ajustes del plugin: la
píldora debe teñirse y el número pasar a rol `error`.

**El token no se filtra. Si esto falla, es un defecto de seguridad y bloquea la
entrega.**

```bash
journalctl --user -n 500 --no-pager | grep -ciE 'sk-ant|Bearer [A-Za-z0-9]' || echo "sin fugas"
```

Esperado: `sin fugas`.

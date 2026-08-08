# Validación manual de los siete estados

`logic.luau` está cubierto por la suite automática. Los estados de error, no:
solo existen cuando algo del entorno falla, y forzarlos requiere el shell real
(spec §9). Esta es la lista, con el procedimiento exacto y hueco para anotar lo
observado.

**Nada de esto está ejecutado todavía.** Las columnas «Observado» y «Fecha» se
rellenan al pasarlo.

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
| 1 | Dato fresco | Normal, tras un sondeo bueno | Píldora con glifo + número; pie «hace N s» | | |
| 2 | Sin conexión, con dato | `nmcli networking off` tras un sondeo bueno | Píldora atenuada; «Sin conexión · dato de hace N min» | | |
| 3 | Sin conexión, sin dato | Red apagada + reiniciar shell, con `~/.claude.json` presente | «Caché local · hace N» | | |
| 4 | Token vencido | En la copia, poner `claudeAiOauth.expiresAt` en el pasado | Glifo `key-off`; «Sesión caducada» | | |
| 5 | Sin credenciales | Renombrar `.credentials.json` temporalmente | **Widget oculto por completo** | | |
| 6 | Arranque | Reiniciar el shell y mirar el primer segundo | «Cargando…» | | |
| 7 | JSON corrupto | Fichero de credenciales con `{{{` | Igual que «sin conexión», y **sin traza en el log** | | |

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

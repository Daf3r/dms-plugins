# Validación manual de los siete estados

`logic.js` está cubierto por la suite automática (`tests/run-js.fish`). Los
estados de error, no: solo existen cuando algo del entorno falla, y forzarlos
requiere el shell real (spec §9). Esta es la lista, con el procedimiento exacto
y hueco para anotar lo observado.

> **Estado: pasada NO ejecutada sobre el build de DMS.** daf3r la dio por
> innecesaria el 2026-08-10, tras verificar el plugin en vivo (píldora de dos
> ranuras, popout completo, anillo, panel de ajustes, respaldo por caché) y con
> la suite en 189/189. La columna «Observado» de la tabla es de la pasada del
> 2026-08-08 **sobre el build de Luau**, no sobre este: no la leas como
> evidencia de DMS. El procedimiento queda aquí para cuando haga falta.

> **Mientras corre esto, el widget enseña números inventados.** Los casos se
> fuerzan apuntando `Daemon.qml` a un servidor local, así que durante la
> validación la barra NO muestra el uso real. Avisar antes de empezar y
> restaurar el endpoint al terminar.

> **La cuota de la API está tocada.** El endpoint no es público y ya devolvió un
> 429 durante el spike de la tarea 1 (dos píldoras sondeando, una por pantalla).
> Los casos de aquí se fuerzan contra un servidor **local**; ninguno necesita
> pegarle a `api.anthropic.com`.

## Antes de empezar

**El plugin ya no vive en un symlink de desarrollo.** Desde el 2026-08-10 está
declarado en `~/nixos-config/dms.nix` y esa ruta es un enlace de **solo lectura
al store**:

```bash
ls -l ~/.config/DankMaterialShell/plugins/claude-usage
# -> /nix/store/…-home-manager-files/.config/DankMaterialShell/plugins/claude-usage
```

Editar el repo ya **no** cambia lo que corre: el `src` sale de un input del flake
apuntado a `github:Daf3r/dms-plugins`, así que hace falta commit, push,
`nix flake update dms-plugins` y un `nh os switch`.

Esta pasada fuerza fallos apuntando `Daemon.qml` a un servidor local, lo que
significa editar el plugin **muchas veces seguidas**. Con el enlace al store eso
es un ciclo de rebuild por caso. Antes de empezar, volver al symlink de
desarrollo:

```bash
rm ~/.config/DankMaterialShell/plugins/claude-usage   # es un symlink, no el store
ln -s /home/daf3r/Projects/dms-plugins/claude-usage \
      ~/.config/DankMaterialShell/plugins/claude-usage
```

Al terminar, un `nh os switch` restituye el enlace declarado.

Recarga y log:

```bash
systemctl --user restart dms.service
journalctl --user -u dms.service -f | grep -i claudeusage
```

> `dms restart` reinicia el shell entero. Si daf3r está trabajando, preguntar
> antes.

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

La columna «Observado» es la pasada del **2026-08-08 sobre el build de Noctalia
en Luau**, que es de donde este plugin viene. Se conserva porque describe el
comportamiento esperado con precisión y porque el caso 4 documenta un defecto
real que encontró. **La versión de DMS (QML) no tiene todavía una pasada
completa registrada aquí**: lo verificado en vivo durante las tareas 1-12 está
en los informes de `.superpowers/sdd/2026-08-10-claude-usage-dms/`.

| # | Estado | Cómo forzarlo | Esperado | Observado (Noctalia, 2026-08-08) |
|---|---|---|---|---|
| 1 | Dato fresco | Normal, tras un sondeo bueno | Píldora con glifo + número; pie «hace N s» | ✅ `⏳ 62` a brillo pleno, pico `#D0D0D0` |
| 2 | Sin conexión, con dato | Servidor de laboratorio en 503 tras un sondeo bueno | Píldora atenuada; «Sin conexión · dato de hace N min» | ✅ Píldora a `#9B9B9B`; pie «Offline · 23 s ago», con el último valor bueno **de memoria** |
| 3 | Sin conexión, sin dato | Igual, pero recargando el daemon antes para vaciar `lastModel` | «Caché local · hace N» | ✅ Pie «Local cache · 8 h 11 min ago» con los datos del disco (23/11/8) |
| 4 | Token vencido | En la copia, poner `claudeAiOauth.expiresAt` en el pasado | Glifo `key_off`, sin número | ✅ tras arreglar el choque `render()`/`setGlyph` (ver abajo) |
| 5 | Sin credenciales | Renombrar `.credentials.json` temporalmente | **Widget oculto por completo** | ✅ Desaparece del grupo entero |
| 6 | Arranque | Endpoint apuntando a un socket que acepta y no responde | Glifo `monitoring`, sin número | ✅ Solo el glifo |
| 7 | Credenciales ilegibles | Fichero de credenciales con `{{{` | **Widget oculto**, igual que el caso 5, y **sin traza en el log** | ✅ Oculto; cero líneas nuevas en el log |
| 7b | Respuesta corrupta de la API | Credenciales válidas y cuerpo HTTP 200 que no es JSON | Widget **visible**, atenuado, con el dato de caché | ✅ `⏳ 11` atenuado |

> **La fila 7 estaba mal escrita** en la primera versión de este documento.
> Decía «igual que sin conexión», y lo que ocurre es lo contrario: unas
> credenciales ilegibles dan `status = "missing"` y el widget se **oculta**,
> como en el caso 5. Quien cae a «sin conexión» es la fila 7b, que es un caso
> distinto — credenciales buenas y respuesta rota.

### El defecto que encontró la pasada de Noctalia

Vale la pena conservarlo aunque la causa ya no exista, porque la propiedad que
protege sí: **un dato viejo no puede presentarse como bueno** (spec §9).

El caso 4 no pasaba: en vez del candado seguía viéndose la píldora anterior. Las
dos APIs del widget de barra de Noctalia eran excluyentes — en cuanto se había
pintado un `render()`, los `setGlyph`/`setText` se ignoraban en silencio — así
que los tres estados sin número (cargando, vencido y sin conexión sin dato) se
quedaban mudos y dejaban en pantalla el árbol anterior.

**En DMS el mecanismo no puede repetirse**: `Widget.qml` no repinta a mano, son
bindings sobre `usageState.value`, y los estados sin número se distinguen por
`root.usageStatus` dentro del mismo árbol declarativo. Lo que sigue mereciendo
una mirada en cada pasada es el resultado, no la causa: que la píldora **cambie**
de verdad al entrar en un estado sin número, en lugar de dejar el número viejo.

## Comprobaciones transversales

**El daemon publica.** El botón de refrescar está en el popout: clic en la
píldora y luego en el icono de recargar. Escribe `refreshRequest` (variable
global del plugin), que el daemon observa.

```bash
journalctl --user -u dms.service -n 40 --no-pager | grep -i claudeusage
```

**El popout abre y refresca.** Clic en la píldora. Comprobar la barra de
progreso, las filas de sublímites, el bloque de créditos extra y que el botón de
refrescar mueve la etiqueta de antigüedad del pie. El pie y el botón están en
**todos** los estados, también con la sesión caducada.

**Las dos ranuras.** La píldora enseña la sesión de 5 h y, fija en segunda
posición y atenuada, la semanal. El circulito de aviso salta cuando **cualquier
límite que no sea el primario** cruza el umbral (`Logic.hasHiddenWarning`
compara contra `primaryKey` y nada más), así que con la semanal en aviso
aparece aunque la semanal sí se vea. Su razón de ser son los sublímites por
modelo, que no caben en la barra.

**El umbral tiñe.** Bajar «Umbral de aviso» a 50 desde los ajustes del plugin: la
píldora debe teñirse y el número pasar a rol `error`.

**El panel de ajustes guarda.** Mover un deslizador y reabrir el modal: el valor
tiene que seguir ahí. Si `plugin_settings.json` fuese un symlink al store —lo
que pasa si algún plugin declara `settings` en Nix— no guardaría. Ver el aviso
del README del plugin.

**El token no se filtra. Si esto falla, es un defecto de seguridad y bloquea la
entrega.**

```bash
journalctl --user -u dms.service -n 500 --no-pager | grep -ciE 'sk-ant|Bearer [A-Za-z0-9]' || echo "sin fugas"
```

Esperado: `sin fugas`.

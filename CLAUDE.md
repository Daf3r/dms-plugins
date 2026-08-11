# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Plugins para [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (QML +
JavaScript sobre Quickshell). Hoy hay uno: `claude-usage/`.

## Comandos

```bash
fish claude-usage/tests/run-js.fish        # la suite entera (189 casos)
```

`node` viene del devshell `dms-plugins` de `~/nixos-config`, que direnv activa al entrar
en el proyecto. Fuera de direnv:
`nix develop ~/nixos-config#dms-plugins -c fish claude-usage/tests/run-js.fish`.

Un solo fichero, o un solo caso:

```bash
TZ=Europe/Madrid node --test claude-usage/tests/cadence.test.js
TZ=Europe/Madrid node --test --test-name-pattern "reposo y alerta" claude-usage/tests/*.test.js
```

- **`TZ` es obligatorio.** La máquina está en `America/El_Salvador` y sin
  `TZ=Europe/Madrid` la suite cae con 2 fallos (187/189). El runner la fija.
- El comentario de `run-js.fish` que dice que `node --test <dir>` falla con
  `MODULE_NOT_FOUND` **está desfasado**: era cierto con node v26.4.0 y el devshell hoy
  da v22.23.2, donde la forma con directorio funciona. Pasar el glob sigue siendo lo
  seguro, pero no es la trampa que el comentario describe.

### Ver el plugin en vivo

**El plugin ya NO se edita en caliente.** Desde el 2026-08-10 está declarado en
`~/nixos-config/dms.nix` y `~/.config/DankMaterialShell/plugins/claude-usage` es un
enlace de solo lectura al store. El `src` sale de un input del flake apuntado a
`github:Daf3r/dms-plugins`, así que un cambio local no llega al shell **hasta que se
publica**:

```
commit → push → cd ~/nixos-config && nix flake update dms-plugins → nh os switch
```

El `switch` lo corre daf3r (necesita root). Para comprobar qué revisión corre de verdad:
`grep -A5 '"dms-plugins"' ~/nixos-config/flake.lock`. Si hay que iterar rápido sobre el
QML, la alternativa es volver temporalmente al symlink de desarrollo apuntando al repo.

```bash
systemctl --user restart dms.service
journalctl --user -u dms.service -f | grep -i claudeusage
```

`dms restart` reinicia el shell entero: preguntar antes si daf3r está trabajando.

## Arquitectura

`claude-usage` es un plugin `composite` con dos superficies, y esa elección es funcional,
no ceremonia:

```
Daemon.qml    HTTPS · ficheros · temporizador · toasts.  Corre UNA vez con el shell.
   │          Publica la global `usage`, ya calculada y ya traducida.
   ├──→ Widget.qml    píldora + popout. Se instancia una vez POR PANTALLA.
   └──→ Settings.qml  los siete ajustes. Una vez, dentro del modal.

logic.js      lógica pura: normalizar, ordenar, formatear, cadencia, notificaciones
i18n.js       resuelve descriptores contra translations/{en,es}.json
```

- DMS destruye un `widget` al quitarlo de la barra; un plugin `widget` puro dejaría de
  sondear y se llevaría las notificaciones con él. Por eso hay daemon.
- **Ninguna petición sale de `Widget.qml` ni de `Settings.qml`.** La píldora corre una vez
  por pantalla y dos píldoras sondeando se ganaron un `429` real durante el spike inicial.
  Toda la E/S vive en el daemon.
- Ficheros locales **siempre con `FileView`** (Quickshell.Io), nunca con `XMLHttpRequest`:
  Qt veta el `GET` sobre `file://` y falla **en silencio** (`open()` no lanza y el callback
  nunca llega a DONE). `XMLHttpRequest` se conserva solo para HTTPS, porque
  `getResponseHeader()` es lo que hace posible `parseRetryAfter`.
- El daemon lee en asíncrono y tiene dos vigilantes de atasco (`catalogGuard`,
  `stallGuard`): una continuación que no llega deja el plugin mudo y sin error. Ningún
  camino nuevo puede quedarse callado para siempre.

### Reglas de `logic.js` e `i18n.js`

Estos dos ficheros los cargan **dos motores**: el JavaScript de QML (`import "logic.js" as
Logic`) y node (las pruebas). De ahí todo lo demás:

- **Cero API del host.** Ni QML, ni Quickshell, ni DMS, ni `Qt.*`. Lo que haga falta del
  entorno entra por parámetro. Es lo que permite correr la suite sin levantar el shell.
- **ES5 estricto**: sin `?.`, sin `??`, sin arrow functions, sin template literals.
- Todo lo público se declara como `var`/`function` **de nivel superior**, nunca colgado de
  un objeto contenedor interno: `import ... as Logic` expone las declaraciones del script,
  no `module.exports`, y un `var Logic = {}` interno obligaría a escribir `Logic.Logic.foo()`.
- **Fechas: epoch en milisegundos.** `toMilliseconds` es la única conversión s→ms del
  proyecto; si aparece otra, es un bug.
- **Ausencia = `null`**, nunca `undefined`. `undefined` queda reservado a "esta propiedad
  no existe".
- **Fallar cerrado** ante ficheros corruptos (`validMs`, `safeParse`): nada se interpreta
  como válido solo porque una coerción implícita no lance.

### Texto y traducciones

**Ninguna cadena de cara al usuario se escribe en el código.** `logic.js` devuelve
descriptores `{ key, params }` (más `text` y `weekday`, que son parte del contrato de
`render`), e `i18n.js` los resuelve contra `translations/{en,es}.json`. Añadir un idioma
es un fichero. `translations.test.js` exige que los catálogos tengan exactamente las mismas
claves y que toda clave que la lógica pueda producir exista en ambos.

El daemon baja el texto ya resuelto dentro del estado; `Widget.qml` no carga catálogo (lo
releería una vez por pantalla). `Settings.qml` sí lo carga, con `blockLoading: true`,
porque se instancia una sola vez y pintar claves crudas en el primer frame sería peor.

### Seguridad

El token OAuth de `~/.claude/.credentials.json` viaja **solo** en la cabecera
`Authorization` de `requestUsage()`. Nunca a un log, ni a la UI, ni a un mensaje de error,
ni al objeto de estado publicado. Es una propiedad de diseño con puerta de entrega en
`tests/MANUAL.md`:

```bash
journalctl --user -u dms.service -n 500 --no-pager | grep -ciE 'sk-ant|Bearer [A-Za-z0-9]' || echo "sin fugas"
```

Los dos ficheros que se leen (`~/.claude/.credentials.json` y `~/.claude.json`) son de
**solo lectura**; nunca se escriben ni se copian.

## Convenciones de trabajo

- **Los tests son traducción caso por caso de los `.test.luau` originales**: mismos casos,
  mismos valores, mismos nombres. No se añade, no se quita, no se "mejora". Cuando un caso
  se descarta o se adapta, la cabecera del fichero dice cuál y por qué (ver
  `manifest.test.js`).
- Los defaults del panel de ajustes **se atan a las constantes de `logic.js`**, no se
  repiten los números; `settings.test.js` lo comprueba leyendo `Settings.qml`.
- Los estados de error solo existen cuando el entorno rompe y no los cubre la suite: van
  en [`claude-usage/tests/MANUAL.md`](claude-usage/tests/MANUAL.md), con su procedimiento.
  Ojo: ese documento aún no tiene una pasada completa registrada sobre el build de DMS.
- **Comentarios, documentación y mensajes de commit en español.** Los READMEs y
  `description` en `plugin.json` van en **inglés a propósito** — es lo que lee el resto
  del ecosistema DMS y esa `description` no pasa por el catálogo.
- Commits en conventional commits, sujeto en español y en minúscula
  (`fix(claude-usage): la sesion caducada colapsa al glifo, como el original`).
- Los comentarios nombran su fichero de origen Luau (`service.luau`, `panel.luau`, …) como
  procedencia. Esos ficheros se retiraron y viven en el historial:
  `git log --diff-filter=D --name-only` encuentra el commit.

## Documentación del proceso

`docs/superpowers/` guarda spec, plan, ledger y notas de cada tanda de trabajo, fechados.
El **ledger** es donde va lo que el historial de git no cuenta: decisiones de daf3r,
hipótesis refutadas con medidas, trampas del host y deuda triada a propósito. Mantenerlo
al día mientras se trabaja, no al final.

`.superpowers/sdd/` está ignorado por git — no dejar ahí nada que deba sobrevivir.

## NixOS

**Ya está declarado** en `~/nixos-config/dms.nix:109`
(`programs.dank-material-shell.plugins.claude-usage`), sin `settings` — la trampa de abajo
está esquivada. Eso reemplazó el symlink de desarrollo por el enlace de solo lectura al
store, con el ciclo de publicación que describe la sección de comandos.

Dos trampas ya pagadas, documentadas en los READMEs:

- Una ruta absoluta en `src` **no evalúa** (los flakes evalúan en modo puro). Hay que traer
  el repo como input con `flake = false`.
- **No pongas `settings` en el submódulo.** Un `settings` no vacío en *cualquier* plugin
  declarado hace que DMS escriba `plugin_settings.json` como enlace al store, y entonces
  ningún panel de ajustes puede guardar.

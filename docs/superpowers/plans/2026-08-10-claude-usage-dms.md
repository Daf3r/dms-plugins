# claude-usage para DMS — Plan de implementación (v2)

> **Para agentes:** SUB-SKILL OBLIGATORIA: usa `superpowers:subagent-driven-development`.
> Los pasos usan casillas (`- [ ]`).

> **v2 del 2026-08-10.** La v1 daba por hecho que de Noctalia solo existía la spec y que
> bastaba copiar el `logic.js` de Caelestia. Falso: la implementación en Luau está
> terminada y es **posterior y mejor** — devuelve descriptores en vez de cadenas y tiene
> catálogo i18n. Se parte de ella. Ver la corrección en §1 de la spec.

**Objetivo:** portar `claude-usage` a DankMaterialShell como plugin `composite`,
partiendo de la implementación en Luau y conservando el i18n.

**Arquitectura:** `Daemon.qml` headless posee el E/S y publica **un objeto ya calculado**
en un `PluginGlobalVar`; `Widget.qml` lo lee y solo pinta. `logic.js` devuelve
**descriptores** (`{key, params}`) que `i18n.js` resuelve contra el catálogo.

**Stack:** QML (Quickshell 0.3.0) + JavaScript · `node --test` · fish · Nix

## Restricciones globales

- **HTTP con `XMLHttpRequest` de QtQml.** Decidido por el spike de la tarea 1: la píldora
  de prueba devolvió `status=429 date=SI`, o sea que `getResponseHeader()` funciona. **No
  uses `Quickshell.Networking`**: en Quickshell 0.3.0 ese módulo es NetworkManager y el
  `NetworkRequest` que documenta DMS no existe.
- **Ninguna petición sale de `Widget.qml`.** Las píldoras se instancian **una por
  pantalla** — esta máquina tiene dos. El spike se autoinfligió un 429 así. Todo el E/S
  vive en `Daemon.qml`, que corre una sola vez.
- **`logic.js` no importa nada del host**: ni QML, ni Quickshell, ni DMS. Es lo que
  mantiene la suite ejecutable sin levantar el shell.
- **`logic.js` no formatea texto de cara al usuario.** Devuelve descriptores. Si te ves
  concatenando una cadena traducible dentro de `logic.js`, va en el catálogo.
- **Los catálogos `translations/en.json` y `es.json` se reutilizan sin tocar.** Añadir una
  clave nueva obliga a añadirla en **los dos**; `translations.test` lo verifica.
- **Los ficheros `.luau` son la fuente a traducir, no código a borrar.** Se retiran en la
  última tarea, cuando todo esté en verde, y no antes.
- **El token OAuth nunca se registra** en logs, errores ni en el estado publicado.
- **Ejecuta los tests con el runner que corresponda.** `tests/run.fish` es el de Luau y
  sigue siendo válido para comparar contra el original. El nuevo es `tests/run-js.fish`,
  que fija `TZ=Europe/Madrid` y pasa el glob de ficheros, porque `node --test <dir>` falla
  con `MODULE_NOT_FOUND` en node v26.4.0.
- **El runner de Luau necesita un rodeo.** `tests/run.fish` invoca el devshell
  `noctalia-plugins`, que se renombró a `dms-plugins` y perdió `luau` el 2026-08-10.
  Mientras los `.luau` sigan siendo la referencia (hasta la tarea 13), córrelos con
  `nix shell nixpkgs#luau --command fish claude-usage/tests/run.fish`. Sirve para
  contrastar el port contra el original.
- **Los pasos marcados 🖐️ los verifica daf3r**, no el subagente: requieren GUI o juicio
  visual. Al llegar a uno, commitea, ponlo en el informe y **para**.
- **Entra al devshell:** `nix develop ~/nixos-config#dms-plugins`.
- **`id` del plugin: `claudeUsage`** (el esquema exige camelCase). El directorio sigue
  siendo `claude-usage`.
- **Commits sin `Co-Authored-By`.**

## Estructura de ficheros

```
claude-usage/
  plugin.json              manifiesto composite
  Daemon.qml               <- service.luau (281 líneas, 34 ataduras al host)
  Widget.qml               <- widget.luau + panel.luau (292 líneas, 60 ataduras)
  Settings.qml             <- los seis ajustes de §10
  components/UsageRing.qml <- recuperado de Caelestia
  logic.js                 <- logic.luau (548 líneas, 4 ataduras)
  i18n.js                  NUEVO: resuelve descriptores contra el catálogo
  translations/            en.json + es.json, SIN TOCAR
  tests/                   los 123 casos traducidos de Luau a node --test
```

## Mapa de traducción de la lógica

`logic.luau` exporta 30 funciones; el `logic.js` de Caelestia tenía 28. Estas **solo
existen en Luau** y son el refactor que se conserva:

`describeRelative` · `describeAbsolute` · `describeMoney` · `labelDescriptor` ·
`durationText` · `formatAge` · `sortForPanel` · `isPrimaryKind` · `parseIsoMs` ·
`localUtcOffsetSeconds` · `toMilliseconds` · `startOfDaySec` · `validMs` · `num`

Y **`parseRetryAfter` viaja al revés**: no está en `logic.luau`, se recupera con
`git show feat/claude-usage:claude-usage/logic.js` en `~/Projects/caelestia-plugins`.

---

### Tarea 1: Spike HTTP ✅ COMPLETADA

Veredicto: `XMLHttpRequest`. Ver `docs/superpowers/notes/2026-08-10-spike-http.md`.

---

### Tarea 2: `i18n.js` y el catálogo

**Ficheros:** crear `claude-usage/i18n.js`, `claude-usage/tests/i18n.test.js`,
`claude-usage/tests/run-js.fish`

**Produce:** `render(descriptor, catalog, fallbackCatalog)` -> string.

- [ ] **Paso 1: Escribir `run-js.fish`**, calcado de `tests/run.fish` pero llamando a
  `node --test $here/*.test.js` en vez de a `luau`. Conserva `set -lx TZ Europe/Madrid` y
  el comentario que explica por qué se pasa el glob y no el directorio.
- [ ] **Paso 2: Escribir el test primero.** Casos mínimos: clave presente en `es`; clave
  ausente en `es` pero presente en `en`; clave ausente en ambos -> devuelve la clave
  literal; interpolación de un `{param}`; interpolación con un parámetro que falta;
  descriptor `null` -> cadena vacía.
- [ ] **Paso 3: Correr y ver fallar.** `./tests/run-js.fish`
- [ ] **Paso 4: Implementar `i18n.js`.** Sin dependencias. Interpola `{nombre}` por
  `params[nombre]`.
- [ ] **Paso 5: Correr, ver pasar, commit.**

---

### Tarea 3: `logic.js` — helpers puros y formato

**Fuente:** los helpers de `logic.luau` + `tests/format.test.luau`

**Produce:** `num`, `validMs`, `toMilliseconds`, `parseIsoMs`, `localUtcOffsetSeconds`,
`startOfDaySec`, `durationText`, `formatAge`, `describeRelative`, `describeAbsolute`,
`describeMoney`.

- [ ] **Paso 1: Traducir `tests/format.test.luau` a `tests/format.test.js`.** Los casos
  son la especificación: no inventes, no quites, no añadas. Si alguno no se puede
  expresar en node, ponlo en el informe en vez de adaptarlo por tu cuenta.
- [ ] **Paso 2: Correr y ver fallar.**
- [ ] **Paso 3: Traducir las funciones, conservando los nombres.** Cuidado con: los
  índices desde 1 de Luau, `nil` frente a `undefined`, y que `os.time()` va en segundos
  mientras `Date.now()` va en milisegundos.
- [ ] **Paso 4: Correr, ver pasar, commit.**

---

### Tarea 4: `logic.js` — normalización y orden

**Fuente:** `tests/normalize.test.luau`, `tests/ordering.test.luau`

**Produce:** `severityRank`, `limitLabel`, `labelDescriptor`, `isPrimaryKind`,
`scopeNameOf`, `limitKey`, `normalizeExtraUsage`, `normalizeUsage`, `isWarning`,
`byCriticality`, `pickPrimary`, `sortForPanel`, `hasHiddenWarning`.

- [ ] **Paso 1: Traducir los dos ficheros de test.**
- [ ] **Paso 2: Correr y ver fallar.**
- [ ] **Paso 3: Traducir las funciones. Conserva el desempate por `key`** en
  `byCriticality` aunque el `sort` de JavaScript sea estable desde ES2019: da orden total
  y evita el comparador irreflexivo que su propio comentario documenta.
- [ ] **Paso 4: Correr, ver pasar, commit.**

---

### Tarea 5: `logic.js` — cadencia, credenciales y notificaciones

**Fuente:** `tests/cadence.test.luau`, `tests/credentials.test.luau`,
`tests/notifications.test.luau`

**Produce:** `clampInterval`, `usableInterval`, `nextInterval`, `parseCredentials`,
`extractCache`, `safeParse`, `notificationsFor`, `parseRetryAfter`, y las constantes
`DEFAULT_WARN_THRESHOLD` (90), `DEFAULT_IDLE_INTERVAL` (300), `DEFAULT_ALERT_INTERVAL` (60).

- [ ] **Paso 1: Traducir los tres ficheros de test.**
- [ ] **Paso 2: Recuperar `parseRetryAfter` de Caelestia** con sus casos:
  `cd ~/Projects/caelestia-plugins && git show feat/claude-usage:claude-usage/logic.js`.
  Es la única pieza que no viene de Luau, porque aquel port la eliminó por no poder leer
  cabeceras. Sus tests están en `tests/logic.test.js` del mismo árbol.
- [ ] **Paso 3: Correr, ver fallar, traducir, ver pasar, commit.**

---

### Tarea 6: Fixtures, humo y suite completa en verde

**Fuente:** `tests/fixtures.test.luau`, `tests/smoke.test.luau`,
`tests/translations.test.luau`, `tests/fixtures/`

- [ ] **Paso 1: Portar los fixtures.** Los `.json` se reutilizan tal cual; `json2luau.py`
  **se borra**: existía solo porque Luau no parsea JSON, y node sí.
- [ ] **Paso 2: Traducir los tres ficheros de test restantes.**
- [ ] **Paso 3: La suite entera en verde.** Esperado: los **123 casos** heredados más los
  de `i18n` y `parseRetryAfter`. Anota el número exacto en el informe.
- [ ] **Paso 4: Commit.**

---

### Tarea 7: Manifiesto y daemon que carga

- [ ] **Paso 1: Escribir `plugin.json`** con `type: "composite"`, `components.daemon` y
  `components.widget`, `settings`, y `permissions` incluyendo `settings_write` — sin él la
  UI de ajustes muestra un error en vez del panel.
- [ ] **Paso 2: Escribir el daemon mínimo** con el `PluginGlobalVar` llamado `usage` y un
  log que confirme que `logic.js` e `i18n.js` cargan.
- [ ] **Paso 3: 🖐️ Cargar y verificar.** `dms ipc plugin-scan scan`, esperar unos segundos
  por el debounce, `dms ipc plugins list`. **Verifica daf3r.**
- [ ] **Paso 4: Commit.**

---

### Tarea 8: `service.luau` -> `Daemon.qml`

34 ataduras al host. `noctalia.http` -> `XMLHttpRequest`; `noctalia.readFile` ->
`XMLHttpRequest` con `file://`; `noctalia.state.set` -> `usageState.set`;
`noctalia.notify` -> `dms ipc toast`; el temporizador -> `Timer`.

- [ ] **Paso 1: Traducir, conservando la estructura y los comentarios que explican por qué.**
- [ ] **Paso 2: Verificar por log** que el estado se publica con las claves de §4.2 de la
  spec heredada.
- [ ] **Paso 3: Commit.**

---

### Tarea 9: `widget.luau` -> píldoras

- [ ] **Paso 1: Traducir a `horizontalBarPill` y `verticalBarPill`.**
- [ ] **Paso 2: 🖐️ Añadir a la barra y contrastar el número con `/usage`.** **Verifica daf3r.**
- [ ] **Paso 3: Commit.**

---

### Tarea 10: `panel.luau` -> `popoutContent`

47 ataduras, el fichero más acoplado. Es el que pinta el progreso a mano (commit
`f6fcfcc`) y explica por qué el dato es viejo.

- [ ] **Paso 1: Traducir.**
- [ ] **Paso 2: 🖐️ Pasada manual de los siete estados**, siguiendo `tests/MANUAL.md`.
  **Verifica daf3r.**
- [ ] **Paso 3: Commit.**

---

### Tarea 11: `UsageRing`

- [ ] **Paso 1: Traer `components/UsageRing.qml` de `caelestia-plugins`.**
- [ ] **Paso 2: Retematizar a los tokens de DMS.** No toques la geometría del arco ni la
  codificación por forma: eso es diseño, no tema.
- [ ] **Paso 3: 🖐️ Verificar el anillo.** **Verifica daf3r.**
- [ ] **Paso 4: Commit.**

---

### Tarea 12: `Settings.qml`

Los seis ajustes de §10 con `PluginSettings`: `warn_threshold` (slider 50-99, 90),
`idle_interval` (60-3600, 300), `alert_interval` (15-600, 60), y los toggles
`show_scoped_limits` (true), `show_extra_usage` (true), `show_remaining` (false).

Las etiquetas **salen del catálogo**, no se escriben a mano: las claves
`settings.*.label` y `settings.*.description` ya existen en `en.json` y `es.json`.

- [ ] **Paso 1: Escribir el panel.**
- [ ] **Paso 2: Test que ata los defaults a las constantes de `logic.js`**, como exige §10.
- [ ] **Paso 3: 🖐️ Bajar el umbral y ver reaccionar la píldora.** **Verifica daf3r.**
- [ ] **Paso 4: Commit.**

---

### Tarea 13: Retirar el Luau, declarar en Nix, documentar

- [ ] **Paso 1: Borrar los `.luau`**, `plugin.toml`, `tests/*.luau`, `tests/run.fish`,
  `tests/harness.luau`, `tests/render.luau`. **Solo ahora**, con todo en verde. Quedan en
  el historial.
- [ ] **Paso 2: Quitar el symlink de desarrollo y declarar en `~/nixos-config/dms.nix`:**
  `plugins.claude-usage = { enable = true; src = /home/daf3r/Projects/dms-plugins/claude-usage; }`
- [ ] **Paso 3: `nh os build`, `nh os switch`, verificar con `dms ipc plugins list`.**
- [ ] **Paso 4: README del plugin y del repo.** Que el endpoint **no está documentado** y
  puede desaparecer sin aviso; que se lee `~/.claude/.credentials.json` sin escribirlo ni
  registrarlo. Commit.

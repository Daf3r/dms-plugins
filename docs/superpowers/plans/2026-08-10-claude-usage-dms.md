# claude-usage para DMS — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usa `superpowers:subagent-driven-development`
> (recomendado) o `superpowers:executing-plans` para ejecutar este plan tarea por tarea.
> Los pasos usan casillas (`- [ ]`) para seguimiento.

**Objetivo:** portar el plugin `claude-usage` a DankMaterialShell como plugin
`composite`, reutilizando `logic.js` y sus 69 tests sin tocarlos.

**Arquitectura:** un `Daemon.qml` headless posee todo el E/S y publica **un solo objeto
ya calculado** en un `PluginGlobalVar`; `Widget.qml` lo lee de forma reactiva y solo
pinta. La lógica pura vive en `logic.js`, que no importa nada del host y por eso se
prueba con `node --test` sin levantar el shell.

**Stack:** QML (Quickshell 0.3.0) + JavaScript · `node --test` · fish · Nix

## Restricciones globales

- **Nunca usar `Quickshell.Networking`.** La doc de plugins de DMS muestra un tipo
  `NetworkRequest`; en Quickshell 0.3.0 ese módulo es **NetworkManager** y no existe tal
  tipo. Verificado el 2026-08-10.
- **`logic.js` no importa nada del host.** Ninguna tarea puede añadirle un `import` de
  QML, Quickshell ni DMS. Es la propiedad que mantiene la suite ejecutable sin shell.
- **`logic.js` se copia sin modificar** en la tarea 2 y **ninguna tarea lo edita**. Si una
  tarea cree necesitarlo, para y consulta: es señal de que el port se está desviando del
  diseño heredado. `tests/logic.test.js` tiene **una sola** excepción autorizada, el test
  de la tarea 8 paso 1b que ata los defaults del panel a las constantes de `logic.js`.
- **Los pasos marcados 🖐️ los verifica daf3r, no el subagente.** Requieren hacer clic en
  la GUI o juzgar si algo se ve bien. Al llegar a uno, deja el trabajo commiteado, ponlo
  en el informe y **para** — no lo des por bueno ni lo marques hecho.
- **El token OAuth nunca se registra en logs, ni en errores, ni en el estado publicado.**
  Ver §12 de la spec heredada.
- **Ejecutar los tests siempre con `tests/run.fish`**, nunca `node --test` a pelo: el
  runner fija `TZ=Europe/Madrid` (sin ella los formatos de hora no son deterministas) y
  pasa el glob de ficheros, porque `node --test <directorio>` falla con
  `MODULE_NOT_FOUND` en node v26.4.0.
- **Entrar al devshell antes de trabajar:** `cd ~/Projects/dms-plugins` con direnv, o
  `nix develop ~/nixos-config#dms-plugins`.
- **`id` del plugin: `claudeUsage`** — el esquema exige camelCase con patrón
  `^[a-zA-Z][a-zA-Z0-9]*$`, así que `claude-usage` es inválido como `id`. El directorio
  sí se llama `claude-usage`.
- **Autoría de commits:** sin `Co-Authored-By`. Ver las convenciones del repo.

## Estructura de ficheros

```
claude-usage/
  plugin.json              manifiesto composite: components.daemon + components.widget
  Daemon.qml               headless: credenciales, HTTP, temporizador, estado, notify
  Widget.qml               píldora de barra + popout; solo pinta
  Settings.qml             UI de ajustes (§10 de la spec heredada)
  components/UsageRing.qml anillo con la ventana codificada por forma
  logic.js                 COPIA INTACTA de caelestia-plugins
  tests/                   COPIA INTACTA: logic.test.js, 4 fixtures, run.fish
```

**Responsabilidades.** `Daemon.qml` es el único dueño del estado: nadie más escribe el
global var. `Widget.qml` no evalúa severidad, no ordena y no formatea fechas — lee campos
ya calculados. `logic.js` no sabe que existe un shell.

---

### Tarea 1: Spike — decidir el camino HTTP

Desechable. Decide la forma de `Daemon.qml`, y por eso va primero.

**Ficheros:**
- Crear: `/tmp/dms-spike/plugin.json`, `/tmp/dms-spike/Widget.qml`

**Produce:** una decisión escrita — `XMLHttpRequest` o `Process`+`curl` — y la respuesta a
si `getResponseHeader()` funciona dentro de un plugin de DMS.

- [ ] **Paso 1: Crear el manifiesto del spike**

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/SpikeHttp
```

`~/.config/DankMaterialShell/plugins/SpikeHttp/plugin.json`:

```json
{
    "id": "spikeHttp",
    "name": "HTTP Spike",
    "description": "Throwaway: decide the HTTP path for claude-usage",
    "version": "0.0.1",
    "author": "daf3r",
    "type": "widget",
    "capabilities": ["dankbar-widget"],
    "component": "./Widget.qml",
    "permissions": ["network", "process"]
}
```

- [ ] **Paso 2: Escribir el widget del spike**

`~/.config/DankMaterialShell/plugins/SpikeHttp/Widget.qml`:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string result: "sin probar"

    function probe() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE)
                return
            var hdr = x.getResponseHeader("date")
            root.result = "status=" + x.status + " date=" + (hdr ? "SI" : "NO")
            console.log("SPIKE:", root.result)
        }
        x.open("GET", "https://api.anthropic.com/api/oauth/usage")
        x.send()
    }

    Component.onCompleted: probe()

    horizontalBarPill: Component {
        StyledRect {
            width: label.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: root.result
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }
}
```

- [ ] **Paso 3: 🖐️ Cargar el plugin y observar** (verifica daf3r)

```bash
dms ipc plugins rescan
dms ipc plugins enable spikeHttp
```

Añade el widget a una sección de la barra desde Ajustes → Dank Bar → Widgets.

Esperado: la píldora muestra `status=401 date=SI`. El 401 es correcto y esperado — no
se manda token. **Lo que se mide es `date=SI`**: significa que `getResponseHeader()`
funciona y por tanto `Retry-After` será legible.

- [ ] **Paso 4: Si `date=NO` o el plugin no carga, probar el camino alternativo**

Sustituye `probe()` por:

```qml
    property var proc: Process {
        command: ["curl", "-s", "-D", "-", "-o", "/dev/null",
                  "https://api.anthropic.com/api/oauth/usage"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.result = text.indexOf("date:") >= 0 ? "curl date=SI" : "curl date=NO"
                console.log("SPIKE:", root.result)
            }
        }
    }

    function probe() { proc.running = true }
```

Añade `import Quickshell.Io` arriba.

- [ ] **Paso 5: Anotar la decisión y limpiar**

```bash
dms ipc plugins disable spikeHttp
rm -rf ~/.config/DankMaterialShell/plugins/SpikeHttp
```

Escribe el resultado en `docs/superpowers/notes/2026-08-10-spike-http.md` con: qué camino
gana, si las cabeceras son legibles, y el mensaje de error exacto si alguno falló. Commit:

```bash
git add docs/superpowers/notes/2026-08-10-spike-http.md
git commit -m "docs(spike): decidido el camino HTTP para claude-usage"
```

---

### Tarea 2: Traer `logic.js` y los 69 tests, en verde

**Ficheros:**
- Crear: `claude-usage/logic.js`, `claude-usage/tests/logic.test.js`,
  `claude-usage/tests/run.fish`, `claude-usage/tests/fixtures/*.json` (4)

**Consume:** nada.
**Produce:** `logic.js` con las 29 funciones que el resto del plan usa por nombre —
`normalizeUsage(payload, source, fetchedAt)`, `pickPrimary(limits)`,
`sortForPopout(limits, primaryKey)`, `hasHiddenWarning(limits, primaryKey, threshold)`,
`nextInterval(state)`, `parseRetryAfter(header, now)`, `parseCredentials(text, now)`,
`extractCache(text)`, `notificationsFor(limits, threshold, prevState, now)`,
`formatRelative(resetsAt, now)`, `formatAbsolute(resetsAt, now)`,
`formatMoney(amountMinor, exponent, currency)`, `safeParse(text)`.

- [ ] **Paso 1: Copiar los ficheros desde la rama de Caelestia**

```bash
cd ~/Projects/dms-plugins
mkdir -p claude-usage/tests/fixtures
cd ~/Projects/caelestia-plugins
for f in logic.js tests/logic.test.js tests/run.fish \
         tests/fixtures/usage-normal.json tests/fixtures/usage-warning.json \
         tests/fixtures/usage-no-limits.json tests/fixtures/usage-credits-on.json; do
  git show feat/claude-usage:claude-usage/$f > ~/Projects/dms-plugins/claude-usage/$f
done
chmod +x ~/Projects/dms-plugins/claude-usage/tests/run.fish
```

- [ ] **Paso 2: Correr la suite y verificar que pasa**

```bash
cd ~/Projects/dms-plugins/claude-usage
./tests/run.fish
```

Esperado: **69 tests en verde, 0 fallos.** Si falla algo, NO edites `logic.js` — el fallo
es del entorno (versión de node o TZ) y hay que arreglar el entorno.

- [ ] **Paso 3: Commit**

```bash
cd ~/Projects/dms-plugins
git add claude-usage/logic.js claude-usage/tests
git commit -m "feat(claude-usage): traer logic.js y los 69 tests desde Caelestia

Copia literal de la rama feat/claude-usage de caelestia-plugins. DMS usa
QML + JavaScript, los mismos lenguajes, asi que no hay traduccion: los
mismos 69 casos que estaban en verde alli siguen en verde aqui."
```

---

### Tarea 3: Manifiesto composite y daemon que carga

**Ficheros:**
- Crear: `claude-usage/plugin.json`, `claude-usage/Daemon.qml`
- Crear: symlink `~/.config/DankMaterialShell/plugins/claude-usage`

**Consume:** `logic.js` de la tarea 2.
**Produce:** el plugin aparece en `dms ipc plugins list` y el daemon arranca con el shell.

- [ ] **Paso 1: Escribir el manifiesto**

`claude-usage/plugin.json`:

```json
{
    "id": "claudeUsage",
    "name": "Claude Usage",
    "description": "Consumo de la suscripcion de Claude, con desglose de ventanas de limite",
    "version": "0.1.0",
    "author": "daf3r",
    "type": "composite",
    "icon": "monitoring",
    "capabilities": ["dankbar-widget", "monitoring"],
    "components": {
        "daemon": "./Daemon.qml",
        "widget": "./Widget.qml"
    },
    "settings": "./Settings.qml",
    "permissions": ["settings_read", "settings_write", "network"],
    "requires_dms": ">=1.5.0"
}
```

El `id` es `claudeUsage` y no `claude-usage` porque el esquema exige
`^[a-zA-Z][a-zA-Z0-9]*$`. `settings_write` es obligatorio: sin él, la UI de ajustes
muestra un error en vez del panel.

- [ ] **Paso 2: Escribir el daemon mínimo**

`claude-usage/Daemon.qml`:

```qml
import QtQuick
import qs.Modules.Plugins
import "logic.js" as Logic

PluginComponent {
    id: root

    // El contrato de estado: UNA clave con todo precalculado. El daemon es el
    // unico que escribe aqui; Widget.qml solo lee .value.
    PluginGlobalVar {
        id: usageState
        varName: "usage"
        defaultValue: ({ status: "loading" })
    }

    Component.onCompleted: {
        console.log("claudeUsage: daemon arrancado, logic cargada:",
                    typeof Logic.normalizeUsage === "function")
    }
}
```

- [ ] **Paso 3: Enlazar y cargar**

```bash
ln -sfn ~/Projects/dms-plugins/claude-usage ~/.config/DankMaterialShell/plugins/claude-usage
dms ipc plugins rescan
dms ipc plugins list
```

Esperado: `claudeUsage` aparece en la lista.

- [ ] **Paso 4: Activar y verificar el log**

```bash
dms ipc plugins enable claudeUsage
journalctl --user -u dms -n 30 --no-pager | grep claudeUsage
```

Esperado: `claudeUsage: daemon arrancado, logic cargada: true`.

Si dice `false`, el `import "logic.js" as Logic` no resolvió. Comprueba que el fichero
está junto a `Daemon.qml` y que `logic.js` expone sus funciones donde QML las ve.

- [ ] **Paso 5: Commit**

```bash
git add claude-usage/plugin.json claude-usage/Daemon.qml
git commit -m "feat(claude-usage): manifiesto composite y daemon que carga logic.js

El tipo es composite y no widget porque un widget puro se apaga al
quitarlo de la barra, y eso apagaria tambien las notificaciones de
limite. El id es claudeUsage porque el esquema exige camelCase."
```

---

### Tarea 4: Daemon — credenciales, sondeo y estado

**Ficheros:**
- Modificar: `claude-usage/Daemon.qml`

**Consume:** `Logic.parseCredentials`, `Logic.normalizeUsage`, `Logic.pickPrimary`,
`Logic.sortForPopout`, `Logic.hasHiddenWarning`, `Logic.nextInterval`,
`Logic.parseRetryAfter`, `Logic.extractCache`, `Logic.safeParse`.
**Produce:** el global var `usage` poblado con la forma de §4.2 de la spec heredada:
`{ status, source, primary, others, hiddenWarning, extraUsage, fetchedAtLabel }`.

- [ ] **Paso 0: Declarar los umbrales con los valores de `logic.js`**

`publish()` y `notify()` necesitan estos tres antes de que exista `Settings.qml`. Se
declaran ya, leyendo las constantes de `logic.js` para no inventar números:

```qml
    readonly property int threshold: Logic.DEFAULT_WARN_THRESHOLD
    readonly property int idleInterval: Logic.DEFAULT_IDLE_INTERVAL
    readonly property int alertInterval: Logic.DEFAULT_ALERT_INTERVAL
```

La tarea 8 los sustituye por versiones que leen `pluginData`, conservando estos como
respaldo. **No escribas literales aquí**: 90, 300 y 60 viven en `logic.js` y ese es el
único sitio donde se cambian.

- [ ] **Paso 1: Leer las credenciales**

Añade a `Daemon.qml`, usando el camino que ganó en la tarea 1. Con `XMLHttpRequest`:

```qml
    property string token: ""

    function readCredentials() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var parsed = Logic.parseCredentials(x.responseText, Date.now())
            if (!parsed || !parsed.token) {
                usageState.set({ status: "missing" })
                return
            }
            root.token = parsed.token
            fetchUsage()
        }
        x.open("GET", "file://" + Quickshell.env("HOME") + "/.claude/.credentials.json")
        x.send()
    }
```

**El token no se registra nunca.** No añadas un `console.log` con `parsed` dentro.

- [ ] **Paso 2: Verificar sin token**

Renombra temporalmente el fichero de credenciales y recarga:

```bash
mv ~/.claude/.credentials.json ~/.claude/.credentials.json.off
dms ipc plugins reload
journalctl --user -u dms -n 20 --no-pager | grep claudeUsage
mv ~/.claude/.credentials.json.off ~/.claude/.credentials.json
```

Esperado: el estado queda en `missing`, sin excepciones en el log.

- [ ] **Paso 3: Sondear la API y publicar el estado**

```qml
    function fetchUsage() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return

            if (x.status === 429) {
                var wait = Logic.parseRetryAfter(x.getResponseHeader("retry-after"), Date.now())
                schedule(wait)
                return
            }
            if (x.status !== 200) {
                fallbackToCache()
                return
            }

            var payload = Logic.safeParse(x.responseText)
            publish(Logic.normalizeUsage(payload, "api", Date.now()))
        }
        x.open("GET", "https://api.anthropic.com/api/oauth/usage")
        x.setRequestHeader("Authorization", "Bearer " + root.token)
        x.setRequestHeader("anthropic-beta", "oauth-2025-04-20")
        x.send()
    }

    function publish(model) {
        var primary = Logic.pickPrimary(model.limits)
        usageState.set({
            status: model.status,
            source: model.source,
            primary: primary,
            others: Logic.sortForPopout(model.limits, primary ? primary.key : ""),
            hiddenWarning: Logic.hasHiddenWarning(model.limits,
                                                  primary ? primary.key : "",
                                                  root.threshold),
            extraUsage: model.extraUsage,
            fetchedAtLabel: model.fetchedAtLabel
        })
        schedule(Logic.nextInterval(model))
    }
```

`parseRetryAfter` **se usa aquí** — es una de las tres cosas que este port recupera
frente al de Noctalia, donde la función se eliminaba por no haber cabeceras.

- [ ] **Paso 4: Respaldo por caché y temporizador**

```qml
    Timer {
        id: poll
        repeat: false
        onTriggered: root.token ? fetchUsage() : readCredentials()
    }

    function schedule(seconds) {
        poll.interval = Math.max(1, seconds) * 1000
        poll.restart()
    }

    function fallbackToCache() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var cached = Logic.extractCache(x.responseText)
            if (!cached) { usageState.set({ status: "expired" }); return }
            publish(Logic.normalizeUsage(cached, "cache", cached.fetchedAtMs))
        }
        x.open("GET", "file://" + Quickshell.env("HOME") + "/.claude.json")
        x.send()
    }
```

- [ ] **Paso 5: Verificar el estado publicado**

```bash
dms ipc plugins reload
journalctl --user -u dms -n 40 --no-pager | grep -i claudeusage
```

Añade temporalmente `console.log("estado:", JSON.stringify(usageState.value))` tras
`publish()`, comprueba que `status`, `primary.percent` y `primary.resetsRel` tienen
valores sensatos, y **quita el log antes de commitear** — el estado no lleva token, pero
llenar el journal cada sondeo es ruido.

- [ ] **Paso 6: Commit**

```bash
git add claude-usage/Daemon.qml
git commit -m "feat(claude-usage): sondeo, respaldo por cache y contrato de estado

parseRetryAfter vuelve a usarse: en QML las cabeceras son legibles, asi
que el 429 respeta Retry-After en vez de caer al backoff por duplicacion
como obligaba el port a Noctalia."
```

---

### Tarea 5: Píldora en la barra

**Ficheros:**
- Crear: `claude-usage/Widget.qml`

**Consume:** el global var `usage` de la tarea 4.
**Produce:** `Widget.qml` con `horizontalBarPill` y `verticalBarPill`.

- [ ] **Paso 1: Escribir el widget**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    PluginGlobalVar {
        id: usageState
        varName: "usage"
        defaultValue: ({ status: "loading" })
    }

    readonly property var st: usageState.value || ({ status: "loading" })
    readonly property var primary: st.primary || null
    readonly property bool warn: primary ? primary.warning === true : false

    popoutWidth: 420
    popoutHeight: 360

    horizontalBarPill: Component {
        StyledRect {
            width: content.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: content
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: root.primary ? root.primary.glyph : "hourglass_empty"
                    color: root.warn ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.primary ? root.primary.percent + "%" : "—"
                    color: root.warn ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: col.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: col
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankIcon {
                    name: root.primary ? root.primary.glyph : "hourglass_empty"
                    color: root.warn ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.primary ? root.primary.percent : "—"
                    color: root.warn ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
```

El widget **no** llama a `Logic`: lee `percent`, `glyph` y `warning` ya calculados. Si te
encuentras importando `logic.js` aquí, el estado no trae algo que debería.

- [ ] **Paso 2: 🖐️ Añadir a la barra y verificar** (verifica daf3r)

Ajustes → Dank Bar → Widgets → añadir "Claude Usage" a una sección.

Esperado: la píldora muestra un porcentaje y un glifo. Contrasta el número con `/usage`
dentro de Claude Code — deben coincidir.

- [ ] **Paso 3: Commit**

```bash
git add claude-usage/Widget.qml
git commit -m "feat(claude-usage): pildora de barra horizontal y vertical"
```

---

### Tarea 6: Popout con el desglose

**Ficheros:**
- Modificar: `claude-usage/Widget.qml`

**Consume:** `st.others`, `st.hiddenWarning`, `st.extraUsage`, `st.fetchedAtLabel`.

- [ ] **Paso 1: Añadir `popoutContent` a `Widget.qml`**

```qml
    popoutContent: Component {
        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                text: root.primary ? root.primary.label + " · " + root.primary.percent + "%"
                                   : "Sin datos"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
            }

            StyledText {
                visible: !!root.primary
                text: root.primary ? "Se reinicia " + root.primary.resetsRel
                                     + " (" + root.primary.resetsAbs + ")" : ""
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.st.others || []
                delegate: Row {
                    spacing: Theme.spacingS
                    StyledText {
                        text: modelData.label
                        color: modelData.warning ? Theme.error : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    StyledText {
                        text: modelData.percent + "%"
                        color: modelData.warning ? Theme.error : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }
            }

            StyledText {
                text: root.st.fetchedAtLabel || ""
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
```

- [ ] **Paso 2: 🖐️ Verificar los siete estados** (verifica daf3r)

Haz la misma pasada manual que `docs/superpowers/notes/` registra para Caelestia: `ok`,
`stale`, `expired`, `missing`, `loading`, un 429 y un aviso. Fuerza `missing` renombrando
las credenciales; fuerza `expired` renombrando también `~/.claude.json`.

Anota el resultado en `docs/superpowers/notes/2026-08-10-pasada-manual-dms.md`.

- [ ] **Paso 3: Commit**

```bash
git add claude-usage/Widget.qml docs/superpowers/notes/2026-08-10-pasada-manual-dms.md
git commit -m "feat(claude-usage): popout con el desglose de ventanas"
```

---

### Tarea 7: Portar el `UsageRing`

**Ficheros:**
- Crear: `claude-usage/components/UsageRing.qml`
- Modificar: `claude-usage/Widget.qml`

Este componente **no existía en el port a Noctalia**: su vocabulario `ui.*` no tiene arco
ni canvas. `Canvas` es QtQuick de base, así que se recupera del árbol de Caelestia.

- [ ] **Paso 1: Traer el componente original**

```bash
mkdir -p ~/Projects/dms-plugins/claude-usage/components
cd ~/Projects/caelestia-plugins
git show feat/claude-usage:claude-usage/components/UsageRing.qml \
  > ~/Projects/dms-plugins/claude-usage/components/UsageRing.qml
```

- [ ] **Paso 2: Retematizar a los tokens de DMS**

Sustituye los colores literales o de Caelestia por `Theme.primary`, `Theme.error`,
`Theme.surfaceVariant` y `Theme.surfaceText`. No cambies la geometría del arco ni la
codificación por forma: eso es el diseño, no el tema.

- [ ] **Paso 3: Usarlo en el popout**

En `popoutContent`, sustituye el primer `StyledText` por:

```qml
            UsageRing {
                anchors.horizontalCenter: parent.horizontalCenter
                percent: root.primary ? root.primary.percent : 0
                warning: root.warn
                kind: root.primary ? root.primary.key : ""
            }
```

Añade `import "components"` arriba del fichero.

- [ ] **Paso 4: 🖐️ Verificar el anillo y commitear** (verifica daf3r)

Abre el popout: el anillo debe pintar el porcentaje y cambiar de forma según la ventana.

```bash
git add claude-usage/components/UsageRing.qml claude-usage/Widget.qml
git commit -m "feat(claude-usage): recuperar el UsageRing que Noctalia no podia dibujar"
```

---

### Tarea 8: Panel de ajustes

**Ficheros:**
- Crear: `claude-usage/Settings.qml`
- Modificar: `claude-usage/Daemon.qml`

**Consume:** `pluginData` reactivo.
**Produce:** los seis ajustes de §10, leídos por el daemon con estos nombres exactos:
`warn_threshold`, `idle_interval`, `alert_interval`, `show_scoped_limits`,
`show_extra_usage`, `show_remaining`.

Los defaults **deben coincidir con las constantes exportadas por `logic.js`**:
`DEFAULT_WARN_THRESHOLD = 90`, `DEFAULT_IDLE_INTERVAL = 300`,
`DEFAULT_ALERT_INTERVAL = 60`. §10 de la spec heredada llama a esa duplicación conocida y
aceptada, y exige un test que compare ambos lados — en DMS la copia vive en `Settings.qml`
en lugar del manifiesto, porque aquí los ajustes no se declaran en `plugin.json`.

**No hay ajuste de "activar notificaciones".** §10 lista seis y ninguno lo es; el control
de repetición es el antirrebote de `notificationsFor`, no un interruptor.

- [ ] **Paso 1: Escribir el panel**

`claude-usage/Settings.qml`:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "claudeUsage"

    SliderSetting {
        settingKey: "warn_threshold"
        label: "Umbral de aviso"
        description: "Porcentaje a partir del cual una ventana se considera en aviso"
        minimum: 50
        maximum: 99
        defaultValue: 90
    }

    SliderSetting {
        settingKey: "idle_interval"
        label: "Intervalo en reposo (s)"
        description: "Cada cuanto se consulta el uso cuando nada esta en aviso"
        minimum: 60
        maximum: 3600
        defaultValue: 300
    }

    SliderSetting {
        settingKey: "alert_interval"
        label: "Intervalo en alerta (s)"
        description: "Cada cuanto se consulta cuando alguna ventana esta en aviso"
        minimum: 15
        maximum: 600
        defaultValue: 60
    }

    ToggleSetting {
        settingKey: "show_scoped_limits"
        label: "Mostrar limites por modelo"
        description: "Incluye las ventanas de Opus y Sonnet en el desglose"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "show_extra_usage"
        label: "Mostrar consumo extra"
        description: "Muestra el gasto fuera de la suscripcion"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "show_remaining"
        label: "Mostrar restante en vez de consumido"
        description: "Invierte el porcentaje: 20%% restante en lugar de 80%% consumido"
        defaultValue: false
    }
}
```

- [ ] **Paso 1b: Test que ata los defaults a `logic.js`**

Añade a `claude-usage/tests/logic.test.js` — es la **única** edición de ese fichero que
este plan autoriza, y §10 la exige explícitamente:

```js
test("los defaults de Settings.qml coinciden con las constantes de logic.js", () => {
    const qml = readFileSync(join(__dirname, "..", "Settings.qml"), "utf8");
    const defaultOf = (key) => {
        const block = qml.split(`settingKey: "${key}"`)[1];
        return Number(block.match(/defaultValue:\s*(\d+)/)[1]);
    };
    assert.equal(defaultOf("warn_threshold"), logic.DEFAULT_WARN_THRESHOLD);
    assert.equal(defaultOf("idle_interval"), logic.DEFAULT_IDLE_INTERVAL);
    assert.equal(defaultOf("alert_interval"), logic.DEFAULT_ALERT_INTERVAL);
});
```

Córrelo con `./tests/run.fish`. Esperado: **70 tests en verde**.

- [ ] **Paso 2: Leerlos en el daemon**

```qml
    readonly property int threshold: pluginData?.warn_threshold !== undefined
                                     ? pluginData.warn_threshold
                                     : Logic.DEFAULT_WARN_THRESHOLD
    readonly property int idleInterval: pluginData?.idle_interval !== undefined
                                        ? pluginData.idle_interval
                                        : Logic.DEFAULT_IDLE_INTERVAL
    readonly property int alertInterval: pluginData?.alert_interval !== undefined
                                         ? pluginData.alert_interval
                                         : Logic.DEFAULT_ALERT_INTERVAL
    readonly property bool showScoped: pluginData?.show_scoped_limits !== false
    readonly property bool showExtra: pluginData?.show_extra_usage !== false
    readonly property bool showRemaining: pluginData?.show_remaining === true

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId !== pluginId) return
            publish(Logic.normalizeUsage(root.lastPayload, root.lastSource, Date.now()))
        }
    }
```

Cambiar el umbral **recalcula el estado sin volver a sondear**: `isWarning` es lógica
pura y no necesita red.

- [ ] **Paso 3: 🖐️ Verificar y commitear** (verifica daf3r)

Baja el umbral por debajo del porcentaje actual: la píldora debe ponerse en aviso al
instante, sin esperar al siguiente sondeo.

```bash
git add claude-usage/Settings.qml claude-usage/Daemon.qml
git commit -m "feat(claude-usage): panel de ajustes con umbral y notificaciones"
```

---

### Tarea 9: Notificaciones

**Ficheros:**
- Modificar: `claude-usage/Daemon.qml`

**Consume:** `Logic.notificationsFor(limits, threshold, prevState, now)`.

- [ ] **Paso 1: Emitir las notificaciones que decida la lógica**

```qml
    property var prevState: null

    function notify(model) {
        var pending = Logic.notificationsFor(model.limits, root.threshold,
                                             root.prevState, Date.now())
        for (var i = 0; i < pending.length; i++)
            Quickshell.execDetached(["dms", "ipc", "toast", "warn", pending[i].text])
        root.prevState = model
    }
```

Llama a `notify(model)` dentro de `publish()`, después del `usageState.set(...)`.

El antirrebote **ya está en `notificationsFor`**, que es lógica pura y probada. No añadas
otro aquí.

- [ ] **Paso 2: Verificar sin esperar a un límite real**

Baja el umbral a 1 y recarga: debe salir una notificación por ventana en aviso, y **no**
repetirse en el siguiente sondeo con el mismo dato.

- [ ] **Paso 3: Commit**

```bash
git add claude-usage/Daemon.qml
git commit -m "feat(claude-usage): notificaciones con el antirrebote de logic.js"
```

---

### Tarea 10: Declararlo en Nix y documentar

**Ficheros:**
- Modificar: `~/nixos-config/dms.nix`
- Crear: `claude-usage/README.md`
- Modificar: `README.md` (raíz del repo)

- [ ] **Paso 1: Quitar el symlink de desarrollo**

```bash
rm ~/.config/DankMaterialShell/plugins/claude-usage
```

- [ ] **Paso 2: Declararlo**

En `~/nixos-config/dms.nix`, dentro de `programs.dank-material-shell`:

```nix
    plugins.claude-usage = {
      enable = true;
      src = /home/daf3r/Projects/dms-plugins/claude-usage;
    };
```

- [ ] **Paso 3: Construir, aplicar y verificar**

```bash
cd ~/nixos-config
nh os build
nh os switch
dms ipc plugins list | grep claudeUsage
```

- [ ] **Paso 4: README y commits**

`claude-usage/README.md`: qué hace, que el endpoint **no está documentado** y puede
desaparecer sin aviso, y que el plugin lee `~/.claude/.credentials.json` en modo `0600`
sin escribirlo ni registrarlo. Actualiza el README de la raíz, que sigue hablando de
Noctalia.

```bash
cd ~/Projects/dms-plugins
git add README.md claude-usage/README.md
git commit -m "docs: README de claude-usage y del repo tras el cambio a DMS"

cd ~/nixos-config
git add dms.nix
git commit -m "dms: declarar el plugin claude-usage con src local"
```

---

## Autorrevisión

**Cobertura de la spec.** §2 (port barato) → tareas 2 y 7. §3.1 `parseRetryAfter` →
tarea 4 paso 3. §3.2 `UsageRing` → tarea 7. §3.3 desempate estable → implícito en la
tarea 2, que copia `logic.js` sin el parche de Luau. §4 arquitectura composite → tarea 3.
§5 camino HTTP → tarea 1. §6 empaquetado → tarea 10. §7 pruebas → tarea 2 paso 2 y tarea
6 paso 2.

**Sin marcadores.** No hay TBD ni "implementar después". El único punto que el plan no
fija es el camino HTTP, y es deliberado: lo decide la tarea 1 antes de que la tarea 4
escriba nada.

**Consistencia de tipos.** El global var se llama `usage` en las tareas 3, 4 y 5. Las
claves del estado —`status`, `source`, `primary`, `others`, `hiddenWarning`,
`extraUsage`, `fetchedAtLabel`— son las de §4.2 de la spec heredada y se usan igual en
daemon y widget. `threshold` y `notifications` se definen en la tarea 8 y se consumen en
la 9 con esos mismos nombres.

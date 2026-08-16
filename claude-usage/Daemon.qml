// Traducción de service.luau. Superficie `daemon` del plugin composite.
//
// Headless a propósito: es el único que toca red, ficheros, temporizador y
// notificaciones, y publica un objeto YA CALCULADO en la variable global
// `usage`; la píldora y el panel solo pintan (spec heredada §4.2). Quitar el
// widget de la barra no debe apagar los avisos, y por eso el plugin es
// `composite` y no `widget`: DMS instancia un `widget` al colocarlo en una
// sección de la barra y lo destruye al quitarlo, mientras que el daemon
// arranca con el shell y corre UNA sola vez — la píldora, en cambio, se
// instancia una vez POR PANTALLA.
//
// ── Las ataduras al host, y en qué quedó cada una ────────────────────────────
//
//   noctalia.http            -> XMLHttpRequest (QtQml). El spike de la tarea 1
//                               confirmó que getResponseHeader() funciona
//                               dentro de un plugin de DMS. NO se usa
//                               Quickshell.Networking: en Quickshell 0.3.0 ese
//                               módulo es NetworkManager y el `NetworkRequest`
//                               que documenta DMS no existe.
//   noctalia.readFile        -> FileView de Quickshell.Io
//   noctalia.state.set       -> usageState.set(...) (PluginGlobalVar)
//   noctalia.notify          -> Quickshell.execDetached(["dms","ipc","toast",…])
//   noctalia.setUpdateInterval -> Timer de QtQuick
//   noctalia.tr              -> I18n.render(...) contra translations/*.json
//   noctalia.getConfig       -> pluginData (PluginComponent lo carga de
//                               SettingsData)
//   noctalia.pluginDataDir /
//     mkdirAll / writeFile   -> pluginService.savePluginState/loadPluginState
//   noctalia.json.decode     -> Logic.safeParse
//   noctalia.nowMs           -> Date.now()
//   onIpc("refresh")         -> la variable global `refreshRequest` + toggle()
//
// ── Dos mecanismos distintos, y no es un descuido ────────────────────────────
//
// HTTPS va por XMLHttpRequest y los ficheros locales por FileView. La razón es
// que **Qt veta la lectura de ficheros locales por XHR**: `GET` sobre una URL
// `file://` responde «Using GET on a local file is disabled by default. Set
// QML_XHR_ALLOW_FILE_READ to 1» y —lo peor— falla EN SILENCIO: `open()` no
// lanza y el callback no llega nunca a DONE. La ronda de arreglo 1 lo midió:
// el daemon se quedaba con la carga de catálogos a medias, sin publicar nada y
// sin un solo error visible.
//
// La variable de entorno se descartó: levantaría el veto para el shell entero
// del usuario, no solo para este plugin, y eso lo haría no distribuible.
//
// XMLHttpRequest se conserva para HTTPS y no se toca: el veto es solo para
// `file://`, y `getResponseHeader()` es lo que hace posible parseRetryAfter.
//
// ── Lo que la traducción cambia de forma, y por qué ──────────────────────────
//
// `noctalia.readFile` era SÍNCRONO. FileView (en su forma no bloqueante) no lo
// es, así que poll() pasa de ser una función lineal a una cadena de
// continuaciones. Eso mueve la guarda `inFlight`: en el original solo protegía
// el GET, y aquí tiene que cubrir la cadena entera desde la lectura de
// credenciales, que ya es E/S.
//
// Y de ahí sale la otra lección de la ronda 1, que es la que de verdad
// importa: **una continuación que no llega deja el daemon mudo y sin error**.
// Por eso hay dos vigilantes de atasco (catalogGuard y stallGuard) más abajo:
// ningún camino puede dejar el plugin callado para siempre.
//
// SEGURIDAD (spec heredada §12): el token OAuth viaja SOLO en la cabecera
// Authorization de requestUsage(). Nunca a un log, ni a la UI, ni a un mensaje
// de error, ni al objeto de estado publicado.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import "logic.js" as Logic
import "i18n.js" as I18n

PluginComponent {
    id: root

    // ── Constantes ───────────────────────────────────────────────────────────
    readonly property string endpoint: "https://api.anthropic.com/api/oauth/usage"
    readonly property string credentialsPath: "~/.claude/.credentials.json"
    readonly property string cachePath: "~/.claude.json"
    // Endpoint privado que usa Codex CLI cuando la sesión es ChatGPT. No es una
    // API pública: si cambia, el estado Codex se degrada sin afectar a Claude.
    readonly property string codexEndpoint: "https://chatgpt.com/backend-api/wham/usage"
    readonly property string codexAuthPath: "~/.codex/auth.json"

    // ── Estado interno (los `local` del original) ─────────────────────────────
    property int failures: 0
    property int codexFailures: 0
    property bool inFlight: false
    property bool codexStarted: false
    property bool currentWarning: false
    property string codexStatus: "loading"
    property var notifyState: ({})
    property var lastModel: null
    property var lastCodexModel: null

    // ¿Se pudo cargar el antirrebote? Mientras sea false NO se notifica: sin él
    // cada arranque repetiría los mismos avisos. `notifyStateDegraded` es el
    // permiso para arrancar igualmente cuando no hay forma de cargarlo —
    // callado, pero vivo (ver notifyStateRetry).
    property bool notifyStateLoaded: false
    property bool notifyStateDegraded: false

    // Lo último que este daemon entregó a savePluginState. Empieza vacío a
    // propósito: es lo que garantiza una escritura por generación. Ver
    // saveNotifyState.
    property string notifyStatePersisted: ""

    property bool started: false

    // Copia local de lo último publicado. No se relee `usageState.value` para
    // republicar: esa propiedad es un binding sobre el mapa de variables
    // globales de PluginService, y republicar a partir de una lectura que
    // pudiera estar sin reevaluar reintroduciría un estado viejo. La fuente de
    // verdad de lo que hay publicado es esta.
    property var published: null

    // Los argumentos de la última llamada a publish(). Ver publish() y
    // republishFromState().
    property var lastPublishArgs: null

    // El intervalo lo decide SIEMPRE Logic.nextInterval; esto es solo el valor
    // con el que arranca el Timer antes del primer applyCadence().
    property int pollIntervalMs: Logic.toMilliseconds(Logic.DEFAULT_IDLE_INTERVAL)

    // ── Catálogo de traducciones ─────────────────────────────────────────────
    // Noctalia resolvía las claves con noctalia.tr(). DMS no tiene i18n para
    // plugins, así que el catálogo lo carga el daemon y lo resuelve i18n.js.
    // Como el daemon es el ÚNICO que tiene el catálogo delante, todo el texto
    // de cara al usuario se preformatea aquí y viaja dentro del estado.
    property var catalog: null
    property var fallbackCatalog: null
    property bool catalogsReady: false
    property int catalogsPending: 0

    // La lengua con la que se cargó `catalog`. Es lo que permite distinguir un
    // cambio del ajuste `language` de cualquier otro cambio de ajuste.
    property string activeLanguage: ""

    // ── Estado publicado ─────────────────────────────────────────────────────
    // UNA sola clave con todo precalculado y preformateado (spec heredada
    // §4.2). La UI no evalúa severidad, no ordena y no formatea fechas.
    PluginGlobalVar {
        id: usageState
        varName: "usage"
        defaultValue: ({
                status: "loading"
            })
    }

    // Refresco bajo demanda. En Noctalia era `onIpc("refresh")`, un gancho del
    // host. En DMS el widget vive en otro objeto —y en una instancia por
    // pantalla—, así que el canal es la variable global del plugin: la píldora
    // o el botón del panel escriben una marca de tiempo aquí y el daemon, que
    // es uno solo, la ve en el Connections de abajo. No se lee el valor: lo que
    // importa es que cambió.
    PluginGlobalVar {
        id: refreshRequest
        varName: "refreshRequest"
        defaultValue: 0
    }

    Connections {
        target: root.pluginService

        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pluginId && varName === "refreshRequest")
                root.poll();
        }
    }

    // El sondeo. `noctalia.setUpdateInterval` fijaba el intervalo y el host
    // llamaba a `update()`; aquí el temporizador es nuestro.
    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    // ── Vigilantes de atasco ─────────────────────────────────────────────────
    // La lección de la ronda de arreglo 1 no es "file:// está vetado": es que
    // una continuación que NO LLEGA deja el daemon mudo y sin un solo error.
    // Pasó con XMLHttpRequest sobre file://, cuyo callback no alcanzaba nunca
    // DONE, y puede volver a pasar por otras vías — una petición HTTPS colgada,
    // por ejemplo: XMLHttpRequest no trae tiempo de espera por defecto. Estos
    // dos temporizadores son independientes del mecanismo de E/S, y por eso
    // cubren también los fallos que todavía no conocemos.

    // Arranque: si los catálogos no responden, se arranca igual. Mejor el texto
    // en crudo que un plugin que no publica nada.
    Timer {
        id: catalogGuard
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.catalogsReady)
                return;
            console.warn("claudeUsage: los catálogos no respondieron a tiempo; se arranca sin ellos");
            root.catalogsPending = 0;
            root.finishCatalogs();
        }
    }

    // Sondeo: si `inFlight` se quedase en true, poll() sería un no-op para
    // siempre y el plugin no volvería a actualizarse nunca. Generoso a
    // propósito — no es un tiempo de espera de red, es el último recurso.
    Timer {
        id: stallGuard
        interval: 120000
        repeat: false
        onTriggered: root.pollStalled()
    }

    // Antirrebote: mientras no esté cargado NO se arranca, porque sondear sin
    // él repetiría el mismo aviso en cada arranque. Pero tampoco se espera para
    // siempre —esa es la lección de la ronda 1—, así que a los 10 s se arranca
    // igual en modo degradado: la píldora sigue viva y las notificaciones se
    // callan, que es el único reparto posible entre "no quedarse mudo" y "no
    // hacer spam". Nunca en silencio: las dos salidas dejan aviso.
    Timer {
        id: notifyStateRetry
        interval: 500
        repeat: true
        running: false
        property int attempts: 0
        onTriggered: {
            attempts += 1;
            if (root.loadNotifyState()) {
                stop();
                root.maybeStart();
                return;
            }
            if (attempts >= 20) {
                stop();
                console.warn("claudeUsage: se arranca SIN antirrebote; las notificaciones quedan suprimidas");
                root.notifyStateDegraded = true;
                root.maybeStart();
            }
        }
    }

    // ── i18n ─────────────────────────────────────────────────────────────────

    // Resuelve un descriptor de logic.js contra el catálogo. Es la única
    // frontera donde el texto de cara al usuario toma forma: logic.js devuelve
    // claves porque no puede llamar al host (los tests lo cargan sin él), y
    // aquí es donde sí se puede. Un descriptor con `text` es intraducible por
    // naturaleza —el nombre de un `kind` que no conocemos— y pasa tal cual;
    // de eso se encarga i18n.js.
    function render(descriptor) {
        return I18n.render(descriptor, root.catalog, root.fallbackCatalog);
    }

    // El equivalente directo de noctalia.tr(clave, params), para las claves que
    // no vienen envueltas en un descriptor.
    function tr(key, params) {
        return I18n.render({
            key: key,
            params: params
        }, root.catalog, root.fallbackCatalog);
    }

    // Mismo criterio que el I18n de DMS (Common/I18n.qml) para la locale: la de
    // la sesión manda sobre la del sistema. Del tag solo interesa la lengua
    // ("es_ES" -> "es"), porque el plugin trae sus catálogos por lengua.
    //
    // Pero la locale ya no decide sola: el ajuste `language` la pisa cuando no
    // es "auto". Seguir la locale a secas condena al inglés a quien tenga la
    // sesión fijada en en_US aunque quiera el plugin en español, y forzar "es"
    // rompería el plugin para todos los demás. La regla vive en i18n.js
    // (`pickLanguage`) porque Settings.qml tiene que decidir EXACTAMENTE igual:
    // si divergieran, el panel de ajustes se vería en un idioma y la píldora en
    // otro.
    function localeLanguage() {
        const tag = (SessionData.locale && SessionData.locale !== "") ? SessionData.locale : Qt.locale().name;
        return I18n.pickLanguage(getConfig("language"), tag);
    }

    function loadCatalogs() {
        const lang = localeLanguage();
        root.activeLanguage = lang;
        const wantsOther = lang !== "en";
        root.catalogsPending = wantsOther ? 2 : 1;
        catalogGuard.restart();

        // en.json se carga SIEMPRE: es el respaldo que i18n.js consulta cuando
        // una clave falta en el catálogo activo.
        readJsonFile(pluginPath("translations/en.json"), function (doc) {
            root.fallbackCatalog = doc;
            root.catalogLoaded();
        });

        if (wantsOther) {
            readJsonFile(pluginPath("translations/" + lang + ".json"), function (doc) {
                // Un idioma sin catálogo deja `catalog` en null y render() cae
                // al respaldo inglés. Es el modo degradado que i18n.js
                // documenta, no un error.
                root.catalog = doc;
                root.catalogLoaded();
            });
        }
    }

    function catalogLoaded() {
        root.catalogsPending -= 1;
        if (root.catalogsPending > 0)
            return;
        finishCatalogs();
    }

    // Idempotente a propósito: la llaman tanto la última lectura que termina
    // como el vigilante de arranque, y solo una de las dos puede ganar.
    function finishCatalogs() {
        if (root.catalogsReady)
            return;
        catalogGuard.stop();
        if (!root.catalog)
            root.catalog = root.fallbackCatalog;
        if (!root.fallbackCatalog)
            console.warn("claudeUsage: translations/en.json no se pudo leer; el texto saldrá como claves");
        root.catalogsReady = true;
        root.maybeStart();
    }

    // Recarga en caliente del catálogo, cuando el ajuste `language` cambia con
    // el daemon YA arrancado.
    //
    // Deliberadamente NO reutiliza loadCatalogs(): ese camino es la máquina de
    // arranque (catalogsPending, catalogsReady, catalogGuard, maybeStart) y
    // volver a entrar en él con el daemon en marcha significaría rearmar el
    // vigilante de arranque para nada y pasar por un finishCatalogs() que ya no
    // hace nada. Este camino no toca ninguna de esas tres cosas: cambia el
    // catálogo y republica.
    //
    // `fallbackCatalog` no se relee: en.json no cambia en tiempo de ejecución.
    // Y NO se sondea: el texto se recompone del estado que ya hay, la red no
    // entra aquí.
    function reloadCatalogs() {
        const lang = localeLanguage();
        if (lang === root.activeLanguage)
            return;
        root.activeLanguage = lang;

        if (lang === "en") {
            root.catalog = root.fallbackCatalog;
            republishFromState();
            return;
        }

        readJsonFile(pluginPath("translations/" + lang + ".json"), function (doc) {
            // Un idioma sin catálogo cae al respaldo inglés, igual que en el
            // arranque.
            root.catalog = doc || root.fallbackCatalog;
            root.republishFromState();
        });
    }

    // ── Ajustes ──────────────────────────────────────────────────────────────

    // Un ajuste cambió (el modal de ajustes escribe, PluginService avisa y
    // PluginComponent recarga `pluginData` entero). Lo que se publica depende
    // de tres de ellos —`warn_threshold` decide el aviso, `show_remaining`
    // invierte los porcentajes y `language` cambia todo el texto—, y sin esto
    // el usuario no vería el efecto hasta el siguiente sondeo, que puede ser
    // dentro de cinco minutos.
    //
    // NINGUNA PETICIÓN sale de aquí: se recalcula desde `lastPublishArgs`, que
    // es lo último que se publicó.
    //
    // PERO NO SE APLICA EN EL ACTO, y ese es el motivo de settingsSettle: este
    // evento NO es "el usuario cambió un ajuste", es "DankSlider movió el
    // ratón". `DankSlider` emite en cada onPositionChanged, no al soltar, así
    // que arrastrar el umbral de 99 a 50 dispara del orden de cincuenta
    // eventos, y cada uno cuesta una republicación ENTERA —sortForPanel,
    // decorate de cada límite con tres render() dentro, y un setGlobalVar que
    // reevalúa los bindings de las dos píldoras (una por pantalla) y del popout
    // abierto—. Se coalesce y se aplica una sola vez, cuando el arrastre para.
    //
    // La cadencia (idle_interval/alert_interval) sigue SIN tocarse aquí, ni
    // siquiera coalescida, y ahora por un motivo que no es el coste:
    // applyCadence reprograma el temporizador de sondeo, o sea que adelantaría
    // o retrasaría la próxima PETICIÓN. Cambiar el intervalo se nota en la
    // vuelta siguiente, que es cuando toca, y no cuesta nada al usuario.
    onPluginDataChanged: {
        if (!root.started)
            return;
        settingsSettle.restart();
    }

    // El retardo se elige por percepción, no por ahorro: 150 ms desde el ÚLTIMO
    // evento está por debajo del umbral en el que una interfaz deja de parecer
    // instantánea, así que soltar el deslizador y ver reaccionar la píldora
    // sigue siendo un solo gesto. Es además el mismo número con el que
    // PluginService de DMS agrupa sus escrituras, así que el ajuste ni siquiera
    // está en disco antes.
    //
    // Un cambio de idioma es un evento ÚNICO (el desplegable no emite mientras
    // se arrastra nada), así que pasa por aquí una sola vez y llega 150 ms
    // después: ni se pierde —restart() siempre acaba disparando— ni se nota.
    Timer {
        id: settingsSettle

        interval: 150
        repeat: false
        onTriggered: root.applySettings()
    }

    function applySettings() {
        if (localeLanguage() !== root.activeLanguage) {
            // reloadCatalogs() republica cuando el catálogo nuevo llega.
            reloadCatalogs();
            return;
        }
        republishFromState();
    }

    // `noctalia.getConfig` devolvía nil para un ajuste sin poner; aquí la
    // ausencia es `undefined`. Deliberadamente NO se resuelve el default con
    // `||`: en Luau el 0 es truthy, así que `getConfig("warn_threshold") or
    // DEFAULT` conserva un 0 explícito y un `||` lo tiraría, convirtiendo un
    // umbral 0 legítimo en 90.
    function getConfig(key) {
        const data = root.pluginData;
        if (!data)
            return undefined;
        const value = data[key];
        return value === null ? undefined : value;
    }

    function configOr(key, fallback) {
        const value = getConfig(key);
        return value === undefined ? fallback : value;
    }

    // ── Estado persistido del antirrebote ────────────────────────────────────
    // Noctalia lo guardaba a mano en pluginDataDir()/state.json (mkdirAll +
    // writeFile + readFile). DMS tiene un almacén de estado por plugin —el
    // "Tier 2" de su guía de persistencia—, separado de los ajustes del
    // usuario y con su propio fichero. Las cinco ataduras se colapsan en dos
    // llamadas y el plugin deja de gestionar rutas.
    // Devuelve si se pudo cargar. La guarda de `pluginService` NO puede callar:
    // sin él no hay antirrebote, y sondear sin antirrebote repite el mismo
    // aviso en cada arranque. Quien llama reintenta (notifyStateRetry).
    function loadNotifyState() {
        if (!root.pluginService) {
            console.warn("claudeUsage: sin pluginService; el antirrebote no se ha podido cargar");
            return false;
        }
        const stored = root.pluginService.loadPluginState(root.pluginId, "notifyState", null);
        if (stored && typeof stored === "object")
            root.notifyState = stored;
        root.notifyStateLoaded = true;
        return true;
    }

    function saveNotifyState(next) {
        if (!root.pluginService) {
            console.warn("claudeUsage: sin pluginService; el antirrebote no se ha podido persistir");
            return;
        }

        // Solo se escribe si el contenido cambia: el ledger de la Task 10 de
        // Caelestia observó una reescritura por sondeo aunque nada cambiara.
        // DMS agrupa los volcados a disco, pero savePluginState marca el
        // plugin como sucio y rearma su temporizador de escritura en CADA
        // llamada, así que la guarda sigue haciendo falta.
        //
        // Pero se compara contra LO ÚLTIMO QUE ESCRIBIMOS, no contra la copia
        // en memoria. Comparar contra `notifyState` era un fallo real: en
        // cuanto el sondeo llega a régimen, `next` y `notifyState` son iguales
        // en cada vuelta y savePluginState no se vuelve a llamar JAMÁS. Si en
        // ese momento la copia persistida estuviera ausente o vieja —el fichero
        // borrado, o la escritura perdida en los 150 ms de rebote de
        // PluginService al cerrarse el shell—, el daemon no la repararía nunca,
        // y cada arranque en frío volvería a avisar de lo mismo. Con la marca
        // arrancando vacía, cada generación del daemon escribe una vez y la
        // divergencia se repara sola, sin reescribir por sondeo.
        const encoded = JSON.stringify(next);
        if (encoded === root.notifyStatePersisted)
            return;
        root.notifyStatePersisted = encoded;
        root.pluginService.savePluginState(root.pluginId, "notifyState", next);
    }

    // ── Lectura de ficheros ──────────────────────────────────────────────────

    // FileView quiere una RUTA, no una URL: el `file://` sobra. Es como lo usa
    // PluginService de DMS, que llama a su parámetro `manifestPathNoScheme`.
    // El `~` lo expande Paths (qs.Common).
    function localPath(path) {
        return Paths.expandTilde(path);
    }

    // Ruta de un fichero del propio plugin. Se resuelve desde la ubicación de
    // este .qml y no con pluginService.getPluginPath(), para que la lectura de
    // los catálogos no dependa de que el registro del plugin ya esté montado.
    function pluginPath(relative) {
        return Paths.strip(Qt.resolvedUrl(relative));
    }

    // Una instancia de FileView POR LECTURA, creada al vuelo y destruida en la
    // continuación. Es el mismo patrón con el que PluginService de DMS lee los
    // manifiestos (`manifestFvComp`), y evita el problema de un FileView fijo:
    // reasignar el MISMO `path` no vuelve a emitir `loaded`, así que un sondeo
    // tras otro leería la copia cacheada del primero y no vería nunca un token
    // renovado.
    Component {
        id: fileReader

        FileView {
            id: view

            // La continuación se pasa como propiedad inicial de createObject y
            // no con un .connect() posterior: si la carga terminase durante la
            // propia creación, el connect llegaría tarde y el callback se
            // perdería.
            property var deliver: null

            // Un fichero que no está es un caso NORMAL aquí —no hay
            // credenciales, no hay caché, no hay catálogo para ese idioma— y no
            // debe ensuciar el log del shell.
            printErrors: false
            watchChanges: false

            onLoaded: {
                const loadedText = view.text();
                const callback = view.deliver;
                if (callback)
                    callback(typeof loadedText === "string" && loadedText !== "" ? loadedText : null);
                view.destroy();
            }

            // FileViewError: 1 Unknown, 2 FileNotFound, 3 PermissionDenied,
            // 4 NotAFile. Los cuatro se traducen a lo mismo que devolvía
            // noctalia.readFile ante un fichero ilegible: nada. Quien llama ya
            // distingue "no hay dato" y no necesita el motivo, así que los
            // estados que se publican son los de siempre y no hay ninguno
            // nuevo: sin credenciales -> "missing", sin caché -> "stale".
            onLoadFailed: err => {
                const callback = view.deliver;
                if (callback)
                    callback(null);
                view.destroy();
            }
        }
    }

    function readTextFile(path, callback) {
        const view = fileReader.createObject(root, {
            path: path,
            deliver: callback
        });
        // createObject devuelve null si el componente no se puede instanciar.
        // Sin esta rama la continuación no llegaría NUNCA y el daemon se
        // quedaría mudo sin un solo error — que es exactamente el fallo que
        // costó la ronda de arreglo 1.
        if (!view)
            callback(null);
    }

    function readJsonFile(path, callback) {
        readTextFile(path, function (text) {
            callback(Logic.safeParse(text));
        });
    }

    // ── Publicación ──────────────────────────────────────────────────────────

    function decorate(limit, threshold, showRemaining, nowMs) {
        if (!limit)
            return null;
        const shown = showRemaining ? 100 - limit.percent : limit.percent;
        return {
            key: limit.key,
            label: root.render(limit.label),
            percent: shown,
            warning: Logic.isWarning(limit, threshold),
            // Nombres de Material Symbols, que es el juego de iconos de DMS.
            // Los de Noctalia eran "hourglass" y "calendar": el segundo no
            // existe en esta fuente y no habría pintado nada. Codex proporciona
            // su propio glifo para que no se confunda con las ventanas de Claude.
            glyph: limit.glyph ? limit.glyph : (limit.key === "session" ? "hourglass_empty" : "calendar_month"),
            resetsRel: root.render(Logic.describeRelative(limit.resetsAt, nowMs)),
            resetsAbs: root.render(Logic.describeAbsolute(limit.resetsAt, nowMs))
        };
    }

    // La SEGUNDA ranura de la píldora, y solo eso: la ventana semanal.
    //
    // Es el otro límite primario —`Logic.PRIMARY_KINDS` es exactamente
    // `["session", "weekly_all"]`— y NO «el más crítico de los demás». La
    // píldora enseñaba `others[0]`, que hoy coincide con la semanal pero deja
    // de coincidir en cuanto un sublímite por modelo (p. ej.
    // `weekly_scoped:Fable`) entra en aviso mientras la semanal sigue normal:
    // el orden por criticidad lo pondría delante y la semanal desaparecería de
    // la barra, en el mismo sitio y con la misma pinta, sin ninguna señal.
    // Los sublímites por modelo no son primarios y su sitio sigue siendo
    // `hiddenWarning` y el popout.
    //
    // Devuelve null si la semanal YA está en la primera ranura. `pickPrimary`
    // prefiere la sesión, pero si no hay sesión la primaria es la semanal, y
    // publicarla otra vez pintaría la misma ventana dos veces. Que el campo sea
    // null en ese caso deja al widget sin ninguna decisión que tomar: «hay
    // segunda ranura» es exactamente «este campo no es null».
    function pickWeekly(limits, primaryKey) {
        if (!limits)
            return null;
        for (let i = 0; i < limits.length; i++) {
            const limit = limits[i];
            if (limit && limit.key === "weekly_all")
                return limit.key === primaryKey ? null : limit;
        }
        return null;
    }

    // Monta el importe con las piezas que da logic.js: el separador decimal y
    // el lado del símbolo son de la lengua, no del número. En es sale "30,00 $"
    // y en en "$30.00", con el MISMO dato. Estaba en panel.luau, y baja aquí
    // porque el catálogo solo lo tiene el daemon.
    function moneyLabel(amountMinor, extra) {
        const m = Logic.describeMoney(amountMinor, extra.exponent, extra.currency);
        const amount = m.cents ? m.whole + root.tr("format.decimal") + m.cents : m.whole;
        return root.tr("format.money", {
            amount: amount,
            symbol: m.symbol
        });
    }

    // extraUsage viaja con sus campos crudos intactos —el panel los necesita
    // para decidir si se enseña la fila (enabled / everEnabled)— más los dos
    // importes ya formateados.
    function decorateExtraUsage(extra) {
        if (!extra)
            return null;
        const out = {};
        for (const key in extra)
            out[key] = extra[key];
        out.usedLabel = moneyLabel(extra.usedMinor, extra);
        out.limitLabel = moneyLabel(extra.limitMinor, extra);
        return out;
    }

    function decorateCodexCredits(credits) {
        if (!credits)
            return null;
        let label;
        if (credits.unlimited)
            label = root.tr("codex.creditsUnlimited");
        else if (credits.balance !== null)
            label = root.tr("codex.creditsBalance", { balance: credits.balance });
        else if (credits.hasCredits)
            label = root.tr("codex.creditsAvailable");
        else
            label = root.tr("codex.creditsNone");
        return {
            label: label,
            balance: credits.balance,
            unlimited: credits.unlimited,
            hasCredits: credits.hasCredits
        };
    }

    function codexStatusLabelFor(status, model) {
        if (status === "loading")
            return root.tr("state.codexLoading");
        if (status === "expired")
            return root.tr("state.codexExpired");
        if (status === "stale" && !model)
            return root.tr("state.codexOffline");
        return "";
    }

    function codexFooterLabelFor(status, fetchedAtLabel) {
        let marker = "";
        if (status === "stale")
            marker = root.tr("state.codexOffline");
        else if (status === "expired")
            marker = root.tr("state.codexExpiredShort");
        if (marker !== "" && fetchedAtLabel)
            return marker + " · " + fetchedAtLabel;
        return marker || (fetchedAtLabel || "");
    }

    function decorateCodexState(status, model, threshold, showRemaining, nowMs) {
        const out = {
            status: status,
            source: model ? model.source : null,
            primary: null,
            secondary: null,
            others: [],
            hiddenWarning: false,
            planLabel: null,
            credits: null,
            fetchedAtLabel: null,
            statusLabel: codexStatusLabelFor(status, model),
            footerLabel: "",
            titleLabel: root.tr("codex.title"),
            creditsTitleLabel: root.tr("codex.credits")
        };
        if (!model)
            return out;

        const primary = Logic.pickCodexPrimary(model.limits);
        const secondary = Logic.pickCodexSecondary(model.limits);
        const primaryKey = primary ? primary.key : null;
        const secondaryKey = secondary ? secondary.key : null;
        const sorted = Logic.sortCodexForPanel(model.limits, primaryKey, secondaryKey);
        for (let i = 0; i < sorted.length; i++)
            out.others.push(decorate(sorted[i], threshold, showRemaining, nowMs));

        out.primary = decorate(primary, threshold, showRemaining, nowMs);
        out.secondary = decorate(secondary, threshold, showRemaining, nowMs);
        out.hiddenWarning = Logic.hasCodexHiddenWarning(model.limits, primaryKey, secondaryKey, threshold);
        out.credits = decorateCodexCredits(model.credits);
        if (model.planType)
            out.planLabel = root.tr("codex.planValue", { plan: model.planType });

        out.fetchedAtLabel = model.fetchedAt === null ? null : root.tr("panel.updatedAgo", {
            age: Logic.formatAge(model.fetchedAt, nowMs)
        });
        out.footerLabel = codexFooterLabelFor(status, out.fetchedAtLabel);
        return out;
    }

    // El texto de los estados sin dato. Lo decidía el panel; baja aquí por el
    // catálogo. "missing" no tiene texto: el spec §9 pide ocultar el widget.
    function statusLabelFor(status, model) {
        if (status === "loading")
            return root.tr("state.loading");
        if (status === "expired")
            return root.tr("state.expired");
        if (status === "stale" && !model)
            return root.tr("state.offline");
        return "";
    }

    // El pie del panel: procedencia Y antigüedad. El spec §9 pide "Sin conexión
    // · dato de hace 8 min" y "Caché local · hace 4 días" — con dato viejo hay
    // que decir POR QUÉ es viejo, no solo cuánto. El separador " · " es
    // puntuación, no una frase, y por eso no está en el catálogo (igual que en
    // panel.luau).
    function footerLabelFor(status, source, fetchedAtLabel) {
        let marker = "";
        if (status === "stale")
            marker = source === "cache" ? root.tr("state.cache") : root.tr("state.offline");
        const age = fetchedAtLabel || "";
        if (marker !== "" && age !== "")
            return marker + " · " + age;
        if (marker !== "")
            return marker;
        return age;
    }

    // Las cadenas fijas que el panel necesita verbatim. Van dentro del estado
    // para que Widget.qml no tenga que cargar el catálogo: es una instancia por
    // pantalla y cada una releería los dos JSON.
    function uiStrings() {
        return {
            refresh: root.tr("panel.refresh"),
            extraCredits: root.tr("panel.extraCredits")
        };
    }

    function setUsage(value) {
        root.published = value;
        usageState.set(value);
    }

    function publish(status, model, source, fetchedAt) {
        // Lo que hizo falta para componer esto, guardado tal cual. Es lo que
        // permite recomponer el estado publicado cuando cambia un ajuste —otro
        // umbral, otro idioma, otro sentido de los porcentajes— sin volver a
        // pedirle nada a la API. `lastModel` por sí solo no basta: no dice si lo
        // último publicado era "ok" o "stale", ni de dónde venía.
        root.lastPublishArgs = {
            status: status,
            model: model,
            source: source,
            fetchedAt: fetchedAt
        };

        const threshold = configOr("warn_threshold", Logic.DEFAULT_WARN_THRESHOLD);
        const showRemaining = getConfig("show_remaining") === true;
        const nowMs = Date.now();
        const resolvedSource = (source === undefined || source === null) ? null : source;
        const codex = decorateCodexState(root.codexStatus, root.lastCodexModel, threshold, showRemaining, nowMs);

        if (!model) {
            // El original publicaba aquí solo tres claves. Se publica la forma
            // completa con nulos para que la píldora y el panel no tengan que
            // distinguir "clave ausente" de "sin valor": `status = "stale"` con
            // `primary` nulo significa sin conexión y sin dato, y se pinta "Sin
            // conexión", no una píldora al 0 %.
            setUsage({
                status: status,
                source: resolvedSource,
                primary: null,
                weekly: null,
                others: [],
                hiddenWarning: false,
                extraUsage: null,
                fetchedAtLabel: null,
                statusLabel: statusLabelFor(status, null),
                footerLabel: footerLabelFor(status, resolvedSource, null),
                inFlight: root.inFlight,
                strings: uiStrings(),
                codex: codex
            });
            return;
        }

        const primary = Logic.pickPrimary(model.limits);
        const primaryKey = primary ? primary.key : null;

        const sorted = Logic.sortForPanel(model.limits, primaryKey);
        const others = [];
        for (let i = 0; i < sorted.length; i++)
            others.push(decorate(sorted[i], threshold, showRemaining, nowMs));

        // formatAge, no describeRelative: fetchedAt está en el pasado y
        // describeRelative devolvería "reiniciando…" siempre.
        const fetchedAtLabel = (fetchedAt === undefined || fetchedAt === null) ? null : root.tr("panel.updatedAgo", {
            age: Logic.formatAge(fetchedAt, nowMs)
        });

        setUsage({
            status: status,
            source: resolvedSource,
            primary: decorate(primary, threshold, showRemaining, nowMs),
            weekly: decorate(pickWeekly(model.limits, primaryKey), threshold, showRemaining, nowMs),
            // `others` NO cambia: sigue siendo la lista completa y ordenada por
            // criticidad, que es lo que el popout necesita entera. `weekly` es
            // una segunda vista sobre el mismo dato, no un recorte de esta.
            others: others,
            hiddenWarning: Logic.hasHiddenWarning(model.limits, primaryKey, threshold),
            extraUsage: decorateExtraUsage(model.extraUsage),
            fetchedAtLabel: fetchedAtLabel,
            statusLabel: statusLabelFor(status, model),
            footerLabel: footerLabelFor(status, resolvedSource, fetchedAtLabel),
            inFlight: root.inFlight,
            strings: uiStrings(),
            codex: codex
        });
    }

    // La sesión caducada, por sus DOS caminos: el token que ya venció al leer
    // las credenciales y el 401/403 que responde la API. Uno solo, porque los
    // dos tienen que publicar exactamente lo mismo.
    //
    // Se publica CON el último modelo bueno —igual que antes— para que
    // `republishFromState()` pueda recomponer el estado cuando cambie un ajuste
    // sin volver a pedir nada. Lo que se enseña de él lo decide el widget, que
    // con `expired` colapsa al glifo (ver `hasNumber` en Widget.qml).
    //
    // La novedad son `source` y `fetchedAt`: sin ellos `footerLabelFor` no
    // tenía ninguna de sus dos mitades y el pie del popout salía VACÍO, con lo
    // que el único estado sin número que no puede resolverse solo —hay que
    // abrir Claude Code— era también el único que no decía de cuándo es lo
    // último que se supo. `lastModel` los trae dentro (los pone
    // `normalizeUsage`), así que no hace falta ninguna clave nueva: el pie sale
    // «Actualizado hace 8 min» bajo el «Sesión caducada…».
    function publishExpired() {
        const model = root.lastModel;
        if (!model) {
            publish("expired", null);
            return;
        }
        publish("expired", model, model.source, model.fetchedAt);
    }

    // El spec §7 exige que un refresco bajo demanda no se trague en silencio:
    // si hay una petición en vuelo, el botón del panel tiene que reflejarlo.
    // El estado es UNA sola clave, así que la bandera viaja dentro y cambiar de
    // bandera republica el mismo objeto con el valor nuevo.
    onInFlightChanged: {
        republishInFlight();
        if (root.inFlight)
            stallGuard.restart();
        else
            stallGuard.stop();
    }

    // Republica lo mismo que hay, recompuesto con los ajustes y el catálogo de
    // AHORA. Sin red y sin tocar `failures` ni la cadencia: es exactamente la
    // última publicación, pintada otra vez.
    function republishFromState() {
        const args = root.lastPublishArgs;
        if (!args)
            return;
        publish(args.status, args.model, args.source, args.fetchedAt);
    }

    function republishInFlight() {
        const current = root.published;
        if (!current || typeof current !== "object")
            return;
        if (current.inFlight === root.inFlight)
            return;
        const copy = {};
        for (const key in current)
            copy[key] = current[key];
        copy.inFlight = root.inFlight;
        setUsage(copy);
    }

    // ── Cadencia ─────────────────────────────────────────────────────────────

    function applyCadence(warning, retryAfterSeconds) {
        const seconds = Logic.nextInterval({
            warning: warning,
            failures: Math.max(root.failures, root.codexFailures),
            idleInterval: getConfig("idle_interval"),
            alertInterval: getConfig("alert_interval"),
            // Logic.nextInterval YA tiene la rama de Retry-After (tarea 5):
            // aquí solo se le pasa el valor. Programar la espera del 429 a mano
            // sería una segunda definición de la cadencia, y la lógica pura es
            // la única. Un 0 —que es lo que devuelve parseRetryAfter cuando no
            // hay cabecera— no supera su guarda y se sigue el camino normal.
            retryAfter: retryAfterSeconds
        });
        // La conversión a milisegundos vive en UN solo sitio (spec §7):
        // logic.js trabaja en segundos y el Timer de Qt en milisegundos.
        root.pollIntervalMs = Logic.toMilliseconds(seconds);
        pollTimer.restart();
    }

    // ── Respaldo por caché ───────────────────────────────────────────────────
    // Solo se lee y parsea cuando la API falla (spec §3.2). Nunca notifica: el
    // ledger de la Task 10 observó un aviso disparado por un dato de una hora
    // antes.
    function fallbackToCache(done) {
        // El valor bueno en memoria manda sobre la caché de disco. El spec §9
        // los distingue en dos filas —"API caída, hay último valor bueno"
        // frente a "API caída, SIN valor, hay caché"— y el orden importa de
        // verdad: la caché puede ser de hace días, mientras que lastModel es de
        // este arranque. Leer el disco primero enseñaba un dato de cuatro horas
        // teniendo uno de treinta segundos.
        //
        // lastModel ya lleva dentro su propio source y fetchedAt (los pone
        // normalizeUsage), así que la procedencia se conserva y el panel puede
        // decir "Sin conexión · hace 8 min" en vez de una antigüedad a secas.
        if (root.lastModel) {
            publish("stale", root.lastModel, root.lastModel.source, root.lastModel.fetchedAt);
            done();
            return;
        }

        readTextFile(localPath(root.cachePath), function (text) {
            if (!text) {
                // Ni memoria ni caché: publish() sin modelo hace que la UI diga
                // "Sin conexión" en vez de pintar una píldora al 0 %.
                root.publish("stale", null);
                done();
                return;
            }
            const cached = Logic.extractCache(Logic.safeParse(text));
            if (!cached) {
                root.publish("stale", null);
                done();
                return;
            }
            const model = Logic.normalizeUsage(cached.payload, "cache", cached.fetchedAt);
            root.lastModel = model;
            root.publish("stale", model, "cache", cached.fetchedAt);
            done();
        });
    }

    // ── Notificaciones ───────────────────────────────────────────────────────

    // El cuerpo de UN aviso. Dos claves enteras y no una frase + trozo pegado:
    // en la cláusula de reinicio la lengua decide dónde va, y concatenar se lo
    // impediría. Por eso `reset` entra como PARÁMETRO y sigue entrando así
    // aunque luego varios cuerpos se junten: lo que se une son frases ya
    // montadas, nunca trozos de una.
    function notifyBody(notification) {
        return notification.reset ? root.tr("notify.bodyWithReset", {
            percent: notification.percent,
            limit: root.render(notification.label),
            reset: root.render(notification.reset)
        }) : root.tr("notify.body", {
            percent: notification.percent,
            limit: root.render(notification.label)
        });
    }

    // UN toast por sondeo, no uno por límite.
    //
    // El spec §11 exige cubrir TODOS los límites, y mandar uno por límite no lo
    // conseguía: el resumen es siempre el mismo ("Claude") y el nivel siempre
    // warn, así que el ToastService de DMS descarta el tercero y siguientes
    // ANTES de mirar su propia cola —`toastQueue.some(t => t.message === message
    // && t.level === level)` y `return`—, y el techo real quedaba en DOS. Con
    // tres ventanas cruzadas en el mismo sondeo (session 91, weekly_all 93,
    // weekly_scoped:Opus 95, que es lo normal cerca del reinicio semanal) el
    // tercero se perdía en silencio; y como `notificationsFor` ya había
    // devuelto `notified: true` para los tres y eso se persiste, no se
    // reintentaba jamás para esa ventana.
    //
    // Juntar los cuerpos es inmune a las DOS barreras a la vez —el filtro de
    // duplicados y `maxQueueSize`— sin depender de las tripas de ToastService,
    // que pueden cambiar en 1.6. Y no toca logic.js ni el antirrebote:
    // `notificationsFor` sigue siendo la única definición de qué se notifica y
    // sigue marcando `notified` una vez por ventana, que ahora es correcto
    // porque el aviso sí sale.
    //
    // Se descartó dar a cada límite un resumen distinto: esquiva el filtro de
    // duplicados pero sigue perdiendo el cuarto por `maxQueueSize`, y taparlo
    // bien exigiría saber cuáles aceptó el host, que es justo lo que
    // `execDetached` no devuelve.
    //
    // El orden de las líneas es el de `result.notifications`, que es el de
    // `model.limits`, que es el del array de la API (o el orden fijo del camino
    // legado): determinista, no una iteración de claves de objeto.
    //
    // `noctalia.notify(resumen, cuerpo)` -> el toast de DMS. `toast warn`
    // acepta un solo texto y perdería el resumen "Claude" que pide el spec
    // §11; `toast warnWith` acepta resumen y detalle — y con detalle marca
    // `hasDetails` y alarga la duración, que es justo lo que hace falta cuando
    // el cuerpo son cinco líneas. Los dos argumentos que sobran van vacíos:
    // `command` porque el toast no lanza nada, y `category` con el id del
    // plugin para poder descartarlos por grupo.
    //
    // Verificado en vivo el 2026-08-10 contra el shell corriendo (sin este
    // plugin activo): `dms ipc toast warnWith Claude "…" "" claudeUsage`
    // devuelve TOAST_WARN_SUCCESS y `dms ipc toast status` enseña
    // `visible:warn:Claude`.
    function notify(notifications) {
        const bodies = [];
        for (let i = 0; i < notifications.length; i++)
            bodies.push(notifyBody(notifications[i]));
        if (bodies.length === 0)
            return;
        Quickshell.execDetached(["dms", "ipc", "toast", "warnWith", root.tr("title"), bodies.join("\n"), "", root.pluginId]);
    }

    // ── Sondeo ───────────────────────────────────────────────────────────────

    function endPoll(skipCodex) {
        if (!root.inFlight)
            return;
        // Claude termina primero para conservar la arquitectura existente; el
        // mismo ciclo hace a continuación una sola petición de Codex. Así el
        // daemon sigue siendo único aunque haya dos proveedores.
        if (!root.codexStarted && skipCodex !== true) {
            root.codexStarted = true;
            root.pollCodex();
            return;
        }
        root.inFlight = false;
        root.codexStarted = false;
    }

    // Ninguna continuación de la cadena llegó. Se cuenta como fallo y se libera
    // la guarda, que es lo único imprescindible: sin eso el sondeo queda muerto
    // para siempre. NO se cae a la caché — eso sería volver a leer un fichero,
    // que es justo lo que puede estar atascado —, así que con dato en memoria
    // se republica como viejo y sin él se deja el estado como esté. Ningún
    // estado nuevo.
    function pollStalled() {
        console.warn("claudeUsage: el sondeo se quedó sin respuesta; se aborta y se cuenta como fallo");
        const codexWasStarted = root.codexStarted;
        root.failures += 1;
        if (codexWasStarted) {
            root.codexFailures += 1;
            root.codexStatus = "stale";
        }
        root.endPoll(true);
        if (root.lastModel)
            root.publish("stale", root.lastModel, root.lastModel.source, root.lastModel.fetchedAt);
        else
            root.publish("stale", null);
        root.applyCadence(root.currentWarning);
    }

    // Noctalia exponía `HttpResponse = { ok, status, body }` y su `ok` NO
    // significaba 2xx: significaba que la transacción llegó a completarse. Se
    // ve en el orden de las ramas del original —el 401/403 se comprueba
    // DESPUÉS de `not res.ok`, y si `ok` fuese 2xx esa rama sería código
    // muerto. Con XMLHttpRequest el equivalente es `status > 0`: un fallo de
    // transporte deja el estado en 0.
    function transportOk(xhr) {
        return xhr.status > 0;
    }

    // Noctalia no exponía cabeceras de respuesta, así que Retry-After era
    // ilegible incluso en un 429 y su port cayó al backoff propio (§8 de la
    // spec heredada). XMLHttpRequest sí las lee —el spike de la tarea 1 lo
    // confirmó con un 429 real del endpoint—, así que la regla vuelve. El valor
    // NO programa aquí ninguna espera: entra en el objeto que recibe
    // Logic.nextInterval y decide la lógica pura.
    function retryAfterFrom(xhr) {
        let header = null;
        try {
            header = xhr.getResponseHeader("retry-after");
        } catch (e) {
            header = null;
        }
        return Logic.parseRetryAfter(header, Date.now());
    }

    function poll() {
        // El ledger de la Task 10 avisó de que dos refrescos seguidos
        // colapsaban en uno: la guarda hace que el segundo sea un no-op
        // explícito, no un silencio, y `inFlight` viaja en el estado para que
        // el botón del panel lo pueda decir.
        //
        // Cubre toda la cadena, no solo el GET: en Noctalia readFile era
        // síncrono y bastaba con proteger la petición; aquí leer las
        // credenciales ya es asíncrono, así que la ventana empieza antes.
        if (root.inFlight)
            return;
        // Sin catálogo no hay con qué renderizar el texto del estado. start()
        // dispara el primer sondeo en cuanto los catálogos están.
        if (!root.catalogsReady)
            return;

        root.inFlight = true;
        root.codexStarted = false;
        root.currentWarning = false;

        readTextFile(localPath(root.credentialsPath), function (credText) {
            if (!credText) {
                root.publish("missing", null);
                root.applyCadence(false);
                root.endPoll();
                return;
            }

            const creds = Logic.parseCredentials(Logic.safeParse(credText), Date.now());

            if (creds.status === "expired") {
                root.publishExpired();
                root.applyCadence(false);
                root.endPoll();
                return;
            }
            if (creds.status !== "ok") {
                root.publish("missing", null);
                root.applyCadence(false);
                root.endPoll();
                return;
            }

            root.requestUsage(creds.token);
        });
    }

    function requestUsage(token) {
        let delivered = false;
        function fail() {
            if (delivered)
                return;
            delivered = true;
            // Mismo camino que el `if not started` del original: la petición ni
            // siquiera arrancó, así que cuenta como fallo y se cae a la caché.
            root.failures += 1;
            root.fallbackToCache(root.endPoll);
            root.applyCadence(false);
        }

        let xhr;
        try {
            xhr = new XMLHttpRequest();
        } catch (e) {
            fail();
            return;
        }

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || delivered)
                return;
            delivered = true;
            root.handleResponse(xhr);
        };

        try {
            xhr.open("GET", root.endpoint);
            // El token viaja SOLO aquí (spec §12). No se registra, no se guarda
            // y no entra en el objeto de estado.
            xhr.setRequestHeader("Authorization", "Bearer " + token);
            xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
            xhr.send();
        } catch (e) {
            fail();
        }
    }

    function finishCodexFailure(status, retryAfterSeconds) {
        if (status === "expired") {
            root.codexStatus = "expired";
        } else {
            root.codexFailures += 1;
            root.codexStatus = "stale";
        }
        // El modelo anterior se conserva solo en memoria. No se publica el
        // token ni se escribe otra caché: la UI recibe el dato atenuado o el
        // estado de ausencia/caducidad, según corresponda.
        root.republishFromState();
        root.applyCadence(root.currentWarning, retryAfterSeconds);
        root.endPoll();
    }

    function pollCodex() {
        readTextFile(localPath(root.codexAuthPath), function (authText) {
            if (!authText) {
                root.codexStatus = "missing";
                root.codexFailures = 0;
                root.lastCodexModel = null;
                root.republishFromState();
                root.endPoll();
                return;
            }

            const parsedAuth = Logic.safeParse(authText);
            let creds;
            try {
                creds = Logic.parseCodexCredentials(parsedAuth);
            } catch (error) {
                root.codexStatus = "missing";
                root.codexFailures = 0;
                root.lastCodexModel = null;
                root.republishFromState();
                root.endPoll();
                return;
            }
            if (creds.status !== "ok") {
                root.codexStatus = "missing";
                root.codexFailures = 0;
                root.lastCodexModel = null;
                root.republishFromState();
                root.endPoll();
                return;
            }
            root.requestCodexUsage(creds.token, creds.accountId);
        });
    }

    function requestCodexUsage(token, accountId) {
        let delivered = false;
        function fail() {
            if (delivered)
                return;
            delivered = true;
            root.finishCodexFailure("stale", null);
        }

        let xhr;
        try {
            xhr = new XMLHttpRequest();
        } catch (e) {
            fail();
            return;
        }

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || delivered)
                return;
            delivered = true;
            root.handleCodexResponse(xhr);
        };

        try {
            xhr.open("GET", root.codexEndpoint);
            // El access token de Codex vive SOLO en esta variable local y en la
            // cabecera. Nunca se copia al estado global ni a un log.
            xhr.setRequestHeader("Authorization", "Bearer " + token);
            if (accountId !== null)
                xhr.setRequestHeader("ChatGPT-Account-Id", accountId);
            xhr.send();
        } catch (e) {
            fail();
        }
    }

    function handleCodexResponse(xhr) {
        const status = xhr.status;
        if (!transportOk(xhr) || status >= 500 || status === 429) {
            root.finishCodexFailure("stale", retryAfterFrom(xhr));
            return;
        }
        if (status === 401 || status === 403) {
            root.finishCodexFailure("expired", null);
            return;
        }
        if (status >= 400) {
            root.finishCodexFailure("stale", null);
            return;
        }

        const payload = Logic.safeParse(xhr.responseText);
        if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
            root.finishCodexFailure("stale", null);
            return;
        }

        const nowMs = Date.now();
        root.codexFailures = 0;
        root.codexStatus = "ok";
        root.lastCodexModel = Logic.normalizeCodexUsage(payload, "api", nowMs);
        root.republishFromState();

        const threshold = configOr("warn_threshold", Logic.DEFAULT_WARN_THRESHOLD);
        const warning = Logic.hasCodexWarning(root.lastCodexModel.limits, threshold);
        root.currentWarning = root.currentWarning || warning;
        root.applyCadence(root.currentWarning);
        root.endPoll();
    }

    function handleResponse(xhr) {
        const status = xhr.status;

        if (!transportOk(xhr) || status >= 500 || status === 429) {
            root.failures += 1;
            const retryAfter = retryAfterFrom(xhr);
            root.fallbackToCache(root.endPoll);
            root.applyCadence(false, retryAfter);
            return;
        }

        if (status === 401 || status === 403) {
            root.publishExpired();
            root.applyCadence(false);
            root.endPoll();
            return;
        }

        const payload = Logic.safeParse(xhr.responseText);
        if (!payload || typeof payload !== "object") {
            root.failures += 1;
            root.fallbackToCache(root.endPoll);
            root.applyCadence(false);
            return;
        }

        root.failures = 0;
        const nowMs = Date.now();
        const model = Logic.normalizeUsage(payload, "api", nowMs);
        root.lastModel = model;
        root.publish("ok", model, "api", nowMs);

        const threshold = configOr("warn_threshold", Logic.DEFAULT_WARN_THRESHOLD);
        const primary = Logic.pickPrimary(model.limits);
        const warning = Logic.isWarning(primary, threshold) || Logic.hasHiddenWarning(model.limits, null, threshold);
        root.currentWarning = warning;

        // Las notificaciones cubren TODOS los límites, no solo el que cabe en
        // el widget, y solo salen de datos de la API: esta rama es la única que
        // las emite, y fallbackToCache nunca llega aquí.
        const result = Logic.notificationsFor(model.limits, threshold, root.notifyState, nowMs);
        if (root.notifyStateLoaded) {
            notify(result.notifications);
            // Persistir SOLO cuando el antirrebote está cargado. Guardarlo en
            // modo degradado marcaba `notified: true` en disco para ventanas
            // que nunca se anunciaron —el aviso se acababa de suprimir tres
            // líneas más abajo—, así que el arranque siguiente, ya con el
            // antirrebote bueno, las veía notificadas y se las callaba para
            // siempre. Sin escribir, la ventana sigue viva y el primer sondeo
            // con antirrebote la anuncia.
            saveNotifyState(result.nextState);
        } else if (result.notifications.length > 0) {
            // Modo degradado. Notificar sin antirrebote cargado repetiría el
            // mismo aviso en cada arranque, que es justo el fallo que se
            // reportó; callar es lo correcto, pero nunca en silencio.
            console.warn("claudeUsage: " + result.notifications.length + " aviso(s) suprimido(s): el antirrebote no está cargado");
        }
        // La copia en memoria sí se actualiza siempre: mantiene el registro de
        // ventanas al día dentro de esta generación y no puede provocar un
        // silencio, porque en modo degradado los avisos ya están suprimidos por
        // la guarda de arriba.
        root.notifyState = result.nextState;

        root.applyCadence(warning);
        root.endPoll();
    }

    // ── Arranque y refresco manual ───────────────────────────────────────────

    // Arranca cuando se cumplen las DOS condiciones, venga primero la que
    // venga: catálogo cargado (sin él el texto saldría en crudo) y antirrebote
    // resuelto (cargado, o dado por perdido en modo degradado). Es idempotente
    // porque la llaman los dos caminos.
    function maybeStart() {
        if (root.started)
            return;
        if (!root.catalogsReady)
            return;
        if (!root.notifyStateLoaded && !root.notifyStateDegraded)
            return;
        root.started = true;
        publish("loading", null);
        applyCadence(false);
        // Sondeo inmediato: `loading` significa solo "arranque sin intento
        // completado" (spec §9) y nunca es terminal, así que no se espera un
        // intervalo entero para el primer dato.
        poll();
    }

    function refresh() {
        poll();
    }

    // `dms ipc plugins toggle claudeUsage`: PluginService llama a `toggle()`
    // sobre la instancia del daemon si existe. Es el único gancho por plugin
    // que expone la CLI (`plugins` solo tiene disable/enable/list/reload/
    // status/toggle), así que aquí cae el refresco manual desde fuera del
    // shell — el equivalente de `noctalia msg`.
    function toggle() {
        refresh();
    }

    Component.onCompleted: {
        // Tercer miembro de la familia "mudo sin error": PluginGlobalVar.set()
        // saca el pluginId de su `parent` y, si no lo encuentra, no publica y
        // solo deja un aviso en el log del host. El widget se quedaría con su
        // valor por defecto para siempre. Se comprueba una vez, aquí.
        if (!root.pluginId)
            console.warn("claudeUsage: sin pluginId; el estado no se publicará");
        // El antirrebote ANTES que nada, y si no se puede, se reintenta: el
        // sondeo no arranca hasta que maybeStart() vea las dos condiciones.
        if (!loadNotifyState())
            notifyStateRetry.restart();
        loadCatalogs();
    }
}

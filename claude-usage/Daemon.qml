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
//   noctalia.readFile        -> XMLHttpRequest con URL file://
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
// ── Lo que la traducción cambia de forma, y por qué ──────────────────────────
//
// `noctalia.readFile` era SÍNCRONO. XMLHttpRequest no lo es, así que poll()
// pasa de ser una función lineal a una cadena de continuaciones. Eso mueve la
// guarda `inFlight`: en el original solo protegía el GET, y aquí tiene que
// cubrir la cadena entera desde la lectura de credenciales, que ya es E/S.
//
// SEGURIDAD (spec heredada §12): el token OAuth viaja SOLO en la cabecera
// Authorization de requestUsage(). Nunca a un log, ni a la UI, ni a un mensaje
// de error, ni al objeto de estado publicado.

import QtQuick
import Quickshell
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

    // ── Estado interno (los `local` del original) ─────────────────────────────
    property int failures: 0
    property bool inFlight: false
    property var notifyState: ({})
    property var lastModel: null

    // Copia local de lo último publicado. No se relee `usageState.value` para
    // republicar: esa propiedad es un binding sobre el mapa de variables
    // globales de PluginService, y republicar a partir de una lectura que
    // pudiera estar sin reevaluar reintroduciría un estado viejo. La fuente de
    // verdad de lo que hay publicado es esta.
    property var published: null

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

    // Mismo criterio que el I18n de DMS (Common/I18n.qml): el idioma de la
    // sesión manda sobre el del sistema. Del tag solo interesa la lengua
    // ("es_ES" -> "es"), porque el plugin trae sus catálogos por lengua.
    function localeLanguage() {
        const tag = (SessionData.locale && SessionData.locale !== "") ? SessionData.locale : Qt.locale().name;
        return String(tag).split(/[_-]/)[0];
    }

    function loadCatalogs() {
        const lang = localeLanguage();
        const wantsOther = lang !== "en";
        root.catalogsPending = wantsOther ? 2 : 1;

        // en.json se carga SIEMPRE: es el respaldo que i18n.js consulta cuando
        // una clave falta en el catálogo activo.
        readJsonFile(Qt.resolvedUrl("translations/en.json"), function (doc) {
            root.fallbackCatalog = doc;
            root.catalogLoaded();
        });

        if (wantsOther) {
            readJsonFile(Qt.resolvedUrl("translations/" + lang + ".json"), function (doc) {
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
        if (!root.catalog)
            root.catalog = root.fallbackCatalog;
        if (!root.fallbackCatalog)
            console.warn("claudeUsage: translations/en.json no se pudo leer; el texto saldrá como claves");
        root.catalogsReady = true;
        root.start();
    }

    // ── Ajustes ──────────────────────────────────────────────────────────────

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
    function loadNotifyState() {
        if (!root.pluginService)
            return;
        const stored = root.pluginService.loadPluginState(root.pluginId, "notifyState", null);
        if (stored && typeof stored === "object")
            root.notifyState = stored;
    }

    function saveNotifyState(next) {
        if (!root.pluginService)
            return;
        // Solo se escribe si el contenido cambia: el ledger de la Task 10 de
        // Caelestia observó una reescritura por sondeo aunque nada cambiara.
        // DMS agrupa los volcados a disco, pero savePluginState marca el
        // plugin como sucio y rearma su temporizador de escritura en CADA
        // llamada, así que la guarda sigue haciendo falta.
        if (JSON.stringify(next) === JSON.stringify(root.notifyState))
            return;
        root.pluginService.savePluginState(root.pluginId, "notifyState", next);
    }

    // ── Lectura de ficheros ──────────────────────────────────────────────────

    // `~` lo expande Paths (qs.Common), y XMLHttpRequest necesita una URL
    // file://, no una ruta.
    function fileUrl(path) {
        return Paths.toFileUrl(Paths.expandTilde(path));
    }

    function readTextFile(url, callback) {
        let delivered = false;
        function deliver(text) {
            if (delivered)
                return;
            delivered = true;
            callback(text);
        }

        let xhr;
        try {
            xhr = new XMLHttpRequest();
        } catch (e) {
            deliver(null);
            return;
        }

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            // Con file:// no hay código de estado HTTP: Qt deja `status` en 0 y
            // el contenido en `responseText`. Un fichero ausente o ilegible
            // llega igual —DONE, con `responseText` vacío—, así que la ausencia
            // se detecta por el texto y no por el código. Es exactamente el
            // contrato de noctalia.readFile, que devolvía nil en ambos casos.
            const text = xhr.responseText;
            deliver(typeof text === "string" && text !== "" ? text : null);
        };

        try {
            xhr.open("GET", url);
            xhr.send();
        } catch (e) {
            deliver(null);
        }
    }

    function readJsonFile(url, callback) {
        readTextFile(url, function (text) {
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
            // existe en esta fuente y no habría pintado nada.
            glyph: limit.key === "session" ? "hourglass_empty" : "calendar_month",
            resetsRel: root.render(Logic.describeRelative(limit.resetsAt, nowMs)),
            resetsAbs: root.render(Logic.describeAbsolute(limit.resetsAt, nowMs))
        };
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
        const threshold = configOr("warn_threshold", Logic.DEFAULT_WARN_THRESHOLD);
        const showRemaining = getConfig("show_remaining") === true;
        const nowMs = Date.now();
        const resolvedSource = (source === undefined || source === null) ? null : source;

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
                others: [],
                hiddenWarning: false,
                extraUsage: null,
                fetchedAtLabel: null,
                statusLabel: statusLabelFor(status, null),
                footerLabel: footerLabelFor(status, resolvedSource, null),
                inFlight: root.inFlight,
                strings: uiStrings()
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
            others: others,
            hiddenWarning: Logic.hasHiddenWarning(model.limits, primaryKey, threshold),
            extraUsage: decorateExtraUsage(model.extraUsage),
            fetchedAtLabel: fetchedAtLabel,
            statusLabel: statusLabelFor(status, model),
            footerLabel: footerLabelFor(status, resolvedSource, fetchedAtLabel),
            inFlight: root.inFlight,
            strings: uiStrings()
        });
    }

    // El spec §7 exige que un refresco bajo demanda no se trague en silencio:
    // si hay una petición en vuelo, el botón del panel tiene que reflejarlo.
    // El estado es UNA sola clave, así que la bandera viaja dentro y cambiar de
    // bandera republica el mismo objeto con el valor nuevo.
    onInFlightChanged: republishInFlight()

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
            failures: root.failures,
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

        readTextFile(fileUrl(root.cachePath), function (text) {
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
    function notify(notification) {
        // Dos claves enteras y no una frase + trozo pegado: en la cláusula de
        // reinicio la lengua decide dónde va, y concatenar se lo impediría.
        const body = notification.reset ? root.tr("notify.bodyWithReset", {
            percent: notification.percent,
            limit: root.render(notification.label),
            reset: root.render(notification.reset)
        }) : root.tr("notify.body", {
            percent: notification.percent,
            limit: root.render(notification.label)
        });

        // `noctalia.notify(resumen, cuerpo)` -> el toast de DMS. `toast warn`
        // acepta un solo texto y perdería el resumen "Claude" que pide el spec
        // §11; `toast warnWith` acepta resumen y detalle. Los dos argumentos
        // que sobran van vacíos: `command` porque el toast no lanza nada, y
        // `category` con el id del plugin para poder descartarlos por grupo.
        //
        // Verificado en vivo el 2026-08-10 contra el shell corriendo (sin este
        // plugin activo): `dms ipc toast warnWith Claude "…" "" claudeUsage`
        // devuelve TOAST_WARN_SUCCESS y `dms ipc toast status` enseña
        // `visible:warn:Claude`.
        Quickshell.execDetached(["dms", "ipc", "toast", "warnWith", root.tr("title"), body, "", root.pluginId]);
    }

    // ── Sondeo ───────────────────────────────────────────────────────────────

    function endPoll() {
        root.inFlight = false;
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

        readTextFile(fileUrl(root.credentialsPath), function (credText) {
            if (!credText) {
                root.publish("missing", null);
                root.endPoll();
                return;
            }

            const creds = Logic.parseCredentials(Logic.safeParse(credText), Date.now());

            if (creds.status === "expired") {
                root.publish("expired", root.lastModel);
                root.endPoll();
                return;
            }
            if (creds.status !== "ok") {
                root.publish("missing", null);
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
            root.publish("expired", root.lastModel);
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

        // Las notificaciones cubren TODOS los límites, no solo el que cabe en
        // el widget, y solo salen de datos de la API: esta rama es la única que
        // las emite, y fallbackToCache nunca llega aquí.
        const result = Logic.notificationsFor(model.limits, threshold, root.notifyState, nowMs);
        for (let i = 0; i < result.notifications.length; i++)
            notify(result.notifications[i]);
        saveNotifyState(result.nextState);
        root.notifyState = result.nextState;

        root.applyCadence(warning);
        root.endPoll();
    }

    // ── Arranque y refresco manual ───────────────────────────────────────────

    function start() {
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
        loadNotifyState();
        // Encadena: cuando los catálogos están, catalogLoaded() llama a
        // start(). Publicar antes enseñaría las claves sin traducir.
        loadCatalogs();
    }
}

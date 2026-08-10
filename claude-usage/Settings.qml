// Superficie `settings` del plugin composite: los siete ajustes del spec §10
// más el selector de idioma.
//
// NINGUNA PETICIÓN SALE DE AQUÍ, igual que en Widget.qml. Toda la red vive en
// Daemon.qml, que corre una sola vez. Aquí solo se leen dos ficheros locales
// (los catálogos) y se escriben ajustes.
//
// ── Por qué este fichero SÍ carga el catálogo, y Widget.qml no ───────────────
//
// DMS no tiene i18n para plugins: el catálogo lo carga quien lo necesita y lo
// resuelve i18n.js. Widget.qml no lo carga a propósito —se instancia una vez
// POR PANTALLA y cada instancia releería los dos JSON—, así que el daemon le
// baja todo el texto ya resuelto dentro del estado publicado. El panel de
// ajustes es el caso contrario: se instancia UNA sola vez, dentro del modal de
// ajustes, y su texto (las etiquetas de los ajustes) no viaja en el estado
// porque el daemon no tiene por qué saber cómo se pinta un panel. Así que lo
// carga por su cuenta.
//
// ── Cómo se leen los catálogos, y por qué así ────────────────────────────────
//
// Con FileView de Quickshell.Io, NUNCA con XMLHttpRequest: Qt veta el GET
// sobre `file://` y falla EN SILENCIO (`open()` no lanza y el callback no
// llega nunca a DONE). Esa es la lección de la ronda 1 de la tarea 9, y está
// documentada largo y tendido en la cabecera de Daemon.qml.
//
// La diferencia con el daemon es `blockLoading: true`. El daemon lee en
// asíncrono porque no puede permitirse bloquear el arranque del shell y porque
// tiene un vigilante de atasco que lo cubre. Aquí la lectura es de dos ficheros
// de 2 KB que viven junto a este .qml, ocurre una vez al abrir el modal de
// ajustes, y la alternativa —pintar el panel mientras el catálogo llega— sería
// enseñar "settings.warn_threshold.label" en crudo durante el primer frame.
// `blockLoading` es exactamente la herramienta que Quickshell ofrece para esto:
// text() fuerza la lectura y devuelve el contenido en la misma llamada, así que
// en Component.onCompleted el catálogo ya está y no hay estado de carga que
// pintar.
//
// Aun así hay red de seguridad: si la lectura bloqueante no diera contenido
// (fichero ilegible, o un futuro Quickshell que ignore blockLoading), el panel
// pintaría las claves crudas para siempre. `catalogRetry` reintenta un puñado
// de veces —para entonces la lectura asíncrona que FileView arranca igualmente
// ya habrá terminado— y se para solo en cuanto hay catálogo. Nunca en
// silencio: el último intento deja aviso en el log.
//
// ── El idioma ────────────────────────────────────────────────────────────────
//
// La regla (ajuste explícito > locale de la sesión) vive en i18n.js
// (`pickLanguage`) y la usan Daemon.qml y este fichero. No se duplica aquí: si
// las dos superficies decidieran por su cuenta, el panel podría verse en un
// idioma y la píldora en otro.

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import "logic.js" as Logic
import "i18n.js" as I18n

PluginSettings {
    id: root

    pluginId: "claudeUsage"

    // ── Catálogo ─────────────────────────────────────────────────────────────

    property var catalog: null
    property var fallbackCatalog: null

    // La lengua con la que se cargó el catálogo que hay ahora mismo. Sirve para
    // no releer los ficheros cuando `language` se reevalúa sin cambiar de valor.
    property string loadedLanguage: ""

    // El tag de locale de la sesión, con el mismo criterio que Daemon.qml: la
    // sesión manda sobre el sistema.
    readonly property string localeTag: (SessionData.locale && SessionData.locale !== "") ? SessionData.locale : Qt.locale().name

    // La lengua efectiva. `languageSelector.value` es una propiedad, así que
    // esto se reevalúa solo en cuanto el usuario cambia el desplegable.
    readonly property string language: I18n.pickLanguage(languageSelector.value, root.localeTag)

    onLanguageChanged: root.loadCatalogs()

    // Ruta de un fichero del propio plugin. FileView quiere una RUTA, no una
    // URL: el `file://` sobra (es como lo usa PluginService de DMS).
    function pluginPath(relative) {
        return Paths.strip(Qt.resolvedUrl(relative));
    }

    // Una instancia de FileView POR LECTURA, creada al vuelo y destruida en el
    // acto. Es el mismo patrón con el que Daemon.qml lee sus ficheros (y con el
    // que PluginService de DMS lee los manifiestos), y aquí NO es una
    // precaución teórica: la primera versión de este fichero reutilizaba un
    // solo FileView cambiándole la ruta, y la sonda en vivo lo cazó devolviendo
    // el texto del fichero ANTERIOR. Con un FileView reutilizado, leer es.json
    // después de en.json devolvía en.json otra vez (el panel se quedaba en
    // inglés al cambiar de idioma), y leer un idioma inexistente devolvía
    // contenido en vez de nada. Una instancia por lectura no puede tener caché
    // que devolver.
    Component {
        id: catalogReader

        FileView {
            blockLoading: true
            // Un idioma sin catálogo es un caso NORMAL —la sesión está en
            // francés y este plugin solo trae en/es— y no debe ensuciar el log.
            printErrors: false
            watchChanges: false
        }
    }

    // El FileView de la lectura en curso. Es una propiedad TIPADA y no una
    // variable local porque createObject() devuelve un QObject a secas: sobre
    // una variable local, qmllint no sabe que eso tiene text() y avisa
    // (missing-property). Vuelve a null en cuanto la lectura termina.
    property FileView catalogView: null

    function readCatalog(lang) {
        // createObject devuelve null si el componente no se puede instanciar.
        root.catalogView = catalogReader.createObject(root, {
            path: root.pluginPath("translations/" + lang + ".json")
        });
        if (!root.catalogView)
            return null;
        // `blockLoading` hace que text() lea aquí mismo, sin continuación: el
        // panel de ajustes se instancia UNA vez, al abrir el modal, y son dos
        // ficheros de 2 KB que viven junto a este .qml.
        const doc = Logic.safeParse(root.catalogView.text());
        root.catalogView.destroy();
        root.catalogView = null;
        return doc;
    }

    function loadCatalogs() {
        const lang = root.language;
        if (lang === root.loadedLanguage && root.catalog)
            return;

        // en.json se carga SIEMPRE: es el respaldo que i18n.js consulta cuando
        // una clave falta en el catálogo activo.
        const fallback = readCatalog("en");
        if (fallback)
            root.fallbackCatalog = fallback;

        // Un idioma sin catálogo cae al respaldo inglés. Es el modo degradado
        // que i18n.js documenta, no un error.
        const active = lang === "en" ? root.fallbackCatalog : readCatalog(lang);
        root.catalog = active || root.fallbackCatalog;

        if (root.catalog)
            root.loadedLanguage = lang;
    }

    // Red de seguridad de la lectura bloqueante (ver la cabecera). No se arma
    // salvo que haga falta: `running` es un binding sobre "no hay catálogo".
    Timer {
        id: catalogRetry

        interval: 250
        repeat: true
        running: root.catalog === null
        property int attempts: 0
        onTriggered: {
            attempts += 1;
            root.loadCatalogs();
            if (root.catalog || attempts >= 8) {
                stop();
                if (!root.catalog)
                    console.warn("claudeUsage: los catálogos no se pudieron leer; los ajustes saldrán como claves");
            }
        }
    }

    // El equivalente de noctalia.tr(clave). Lee `catalog` y `fallbackCatalog`,
    // que son propiedades, así que cada etiqueta que llame a esto se repinta
    // sola cuando el catálogo cambia de idioma.
    function tr(key) {
        return I18n.render({
            key: key
        }, root.catalog, root.fallbackCatalog);
    }

    Component.onCompleted: {
        // `loadVariants()` es del tipo base: PluginSettings lo llama desde su
        // propio `Component.onCompleted`. No está claro —ni conviene depender de
        // ello— si una declaración de `Component.onCompleted` en un fichero
        // derivado se SUMA a la del base o la PISA, así que se llama aquí a
        // mano: es idempotente (recalcula `variants` desde pluginService, o lo
        // deja vacío si no hay), y con esto el panel se comporta igual en los
        // dos casos.
        root.loadVariants();
        root.loadCatalogs();
    }

    // ── Los ajustes ──────────────────────────────────────────────────────────
    //
    // Los `defaultValue` de los tres numéricos se atan a las constantes de
    // logic.js, que es la ÚNICA definición del valor por defecto: el daemon
    // resuelve el ajuste ausente con las mismas constantes
    // (`configOr("warn_threshold", Logic.DEFAULT_WARN_THRESHOLD)`,
    // `Logic.nextInterval` con `usableInterval(…, DEFAULT_*)`). Repetir el
    // número aquí dejaría al panel diciendo una cosa y al plugin haciendo otra.
    // tests/settings.test.js lo comprueba leyendo este fichero.
    //
    // Los rangos SÍ son de este panel (spec §10) y no de logic.js: son lo que
    // tiene sentido ofrecer con un deslizador, no los límites que la lógica
    // sabe encajar. logic.js sigue aceptando cualquier valor y recortándolo con
    // MIN_INTERVAL/MAX_INTERVAL, así que un ajuste fuera de rango escrito a
    // mano en el JSON no rompe nada.

    SliderSetting {
        settingKey: "warn_threshold"
        label: root.tr("settings.warn_threshold.label")
        description: root.tr("settings.warn_threshold.description")
        defaultValue: Logic.DEFAULT_WARN_THRESHOLD
        minimum: 50
        maximum: 99
        unit: "%"
        leftIcon: "warning"
    }

    SliderSetting {
        settingKey: "idle_interval"
        label: root.tr("settings.idle_interval.label")
        description: root.tr("settings.idle_interval.description")
        defaultValue: Logic.DEFAULT_IDLE_INTERVAL
        minimum: 60
        maximum: 3600
        unit: "s"
        leftIcon: "schedule"
    }

    SliderSetting {
        settingKey: "alert_interval"
        label: root.tr("settings.alert_interval.label")
        description: root.tr("settings.alert_interval.description")
        defaultValue: Logic.DEFAULT_ALERT_INTERVAL
        minimum: 15
        maximum: 600
        unit: "s"
        leftIcon: "notifications_active"
    }

    // Los tres toggles no tienen constante en logic.js: el daemon y el widget
    // resuelven su ausencia con un literal (`getConfig("show_remaining") ===
    // true`, `configOr("show_scoped_limits", true) !== false`). Estos
    // `defaultValue` tienen que coincidir con ESO, y tests/settings.test.js
    // compara los dos sitios.
    //
    // "Sublímites por modelo" es literal: el ajuste filtra los `weekly_scoped*`
    // del popout y NADA más. Apagarlo no esconde la ventana semanal, que es el
    // número que decide la semana del usuario.
    ToggleSetting {
        settingKey: "show_scoped_limits"
        label: root.tr("settings.show_scoped_limits.label")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "show_extra_usage"
        label: root.tr("settings.show_extra_usage.label")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "show_remaining"
        label: root.tr("settings.show_remaining.label")
        description: root.tr("settings.show_remaining.description")
        defaultValue: false
    }

    // El selector de idioma. No basta con seguir la locale de la sesión: una
    // sesión fijada a en_US condena el plugin al inglés, y forzar el español
    // lo rompería para todos los demás. Ver `pickLanguage` en i18n.js.
    //
    // Las etiquetas de las opciones son literales a propósito: "English" y
    // "Español" son endónimos y no se traducen nunca, y "Auto" se escribe igual
    // en los dos idiomas del catálogo.
    SelectionSetting {
        id: languageSelector

        settingKey: "language"
        label: root.tr("settings.language.label")
        description: root.tr("settings.language.description")
        options: [
            {
                label: "Auto",
                value: "auto"
            },
            {
                label: "English",
                value: "en"
            },
            {
                label: "Español",
                value: "es"
            }
        ]
        defaultValue: "auto"
    }
}

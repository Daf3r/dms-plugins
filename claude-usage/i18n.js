// Renderizador de traducciones del plugin claude-usage.
//
// Igual que logic.js, este fichero se carga desde dos entornos: el motor
// JavaScript de QML (via `import "i18n.js" as I18n`) y node (en las
// pruebas). Por eso:
//   - Nada de QML aquí dentro. Ni un import, ni un tipo, ni Qt.*
//   - ES5 estricto: sin ?., sin ??, sin arrow functions, sin template
//     literals.
//   - El guardián de module.exports al final sirve a los dos.
//   - Todo lo público se declara como `var`/`function` de nivel superior, no
//     colgado de un objeto contenedor interno (mismo motivo que en logic.js:
//     `import "i18n.js" as I18n` con un `var I18n = {}` interno anidaría
//     todo bajo `I18n.I18n.*`).
//
// logic.js no formatea texto de cara al usuario: devuelve descriptores
// `{ key, params }` (ver logic.js y §2bis de
// docs/superpowers/specs/2026-08-10-claude-usage-dms-design.md). Este
// fichero resuelve esos descriptores contra un catálogo de traducciones
// (translations/es.json o en.json) e interpola sus parámetros.
//
// Noctalia resolvía las claves por su cuenta, con noctalia.tr(). DMS no
// tiene i18n para plugins, así que esto sustituye a esa pieza del host: el
// catálogo principal es el idioma activo, y `fallbackCatalog` (pensado como
// en.json) cubre una clave que falte en él. Con los catálogos actuales esto
// no debería disparar nunca — translations.test exige que es.json y en.json
// tengan exactamente las mismas claves — pero es la red de seguridad ante
// una clave añadida a un catálogo y olvidada en el otro, o ante un tercer
// idioma incompleto en el futuro.
//
// `desc.text` y `desc.weekday` SÍ son parte del contrato de esta función, no
// pegamento de host: logic.luau los produce directamente (labelDescriptor
// línea 51 devuelve `{ text = kind }` para un `kind` que no reconoce;
// describeAbsolute línea 360 devuelve `{ key = "reset.weekday",
// params = { clock = ... }, weekday = t.wday }`). render.luau los resuelve
// en el mismo sitio donde resuelve la clave, con esta precedencia:
//   1. `desc.text` corta el paso y se devuelve tal cual, ANTES de mirar el
//      catálogo — es intraducible por naturaleza (el nombre de un `kind`
//      desconocido).
//   2. `desc.weekday` (un número 1-7) se traduce con la clave
//      `weekday.<N>` — con el mismo respaldo entre catálogos que cualquier
//      otra clave — y se inyecta como el parámetro `weekday`, en una COPIA
//      de `params` para no mutar el objeto que pasó quien llama.

var PLACEHOLDER_PATTERN = /\{(\w+)\}/g;

// Sustituye cada {nombre} por params[nombre]. Un hueco sin valor se deja
// intacto a propósito: así es como un parámetro que falta se hace visible en
// pantalla, en vez de imprimir "undefined" (ver tests/render.luau, el
// comportamiento que se conserva).
function substitute(pattern, params) {
    if (!params) return pattern;
    return pattern.replace(PLACEHOLDER_PATTERN, function (match, name) {
        var value = params[name];
        return value === undefined || value === null ? match : String(value);
    });
}

// Copia superficial de `params`, para poder añadir `weekday` sin tocar el
// objeto original.
function copyParams(params) {
    var copy = {};
    var name;
    for (name in params) {
        if (Object.prototype.hasOwnProperty.call(params, name)) {
            copy[name] = params[name];
        }
    }
    return copy;
}

// Resuelve `key` contra `catalog`, y si falta, contra `fallbackCatalog`.
// Devuelve undefined si no está en ninguno de los dos.
function resolve(key, catalog, fallbackCatalog) {
    return (catalog && catalog[key]) || (fallbackCatalog && fallbackCatalog[key]);
}

// render(descriptor, catalog, fallbackCatalog) -> string
//
//   - descriptor null/undefined, o sin `text` ni `key` -> ""
//   - `desc.text` presente                              -> se devuelve tal
//                                                          cual, sin tocar
//                                                          el catálogo
//   - `desc.weekday` presente                           -> se traduce con
//                                                          `weekday.<N>` y se
//                                                          inyecta como
//                                                          params.weekday
//                                                          antes de resolver
//                                                          `desc.key`
//   - `key` presente en `catalog`                       -> plantilla
//                                                          interpolada
//   - `key` ausente en `catalog` pero en
//     `fallbackCatalog`                                 -> la de éste
//   - `key` ausente en ambos                            -> la propia `key`
function render(descriptor, catalog, fallbackCatalog) {
    if (!descriptor) return "";
    if (typeof descriptor.text === "string") return descriptor.text;
    if (!descriptor.key) return "";

    var params = descriptor.params;
    if (typeof descriptor.weekday === "number") {
        var weekdayKey = "weekday." + descriptor.weekday;
        var weekdayLabel = resolve(weekdayKey, catalog, fallbackCatalog) || weekdayKey;
        params = copyParams(params);
        params.weekday = weekdayLabel;
    }

    var pattern = resolve(descriptor.key, catalog, fallbackCatalog);
    if (!pattern) return descriptor.key;

    return substitute(pattern, params);
}

// ---------------------------------------------------------------------------
// Elección de idioma
// ---------------------------------------------------------------------------
//
// El plugin trae un catálogo POR LENGUA (translations/en.json, es.json), así
// que de un tag de locale ("es_ES.UTF-8", "en-US") solo interesa la lengua.
// Un tag vacío o no utilizable cae a "en", que es el catálogo de respaldo que
// siempre existe.
function languageOf(localeTag) {
    if (localeTag === null || localeTag === undefined) return "en";
    var lang = String(localeTag).split(/[_\-.]/)[0].toLowerCase();
    return lang === "" ? "en" : lang;
}

// pickLanguage(setting, localeTag) -> "en" | "es" | …
//
// La regla que comparten Daemon.qml y Settings.qml, y por eso vive aquí: si
// hay ajuste explícito, gana el ajuste; si el ajuste es "auto" (o no está
// puesto), se sigue la locale de la sesión.
//
// Existe porque seguir la locale a secas no basta: una sesión con
// `i18n.defaultLocale = "en_US.UTF-8"` condena al inglés para siempre aunque
// el usuario quiera el plugin en español, y forzar "es" rompería el plugin
// para todos los demás. Las dos superficies TIENEN que decidir igual: si
// divergieran, el panel de ajustes se vería en un idioma y la píldora en otro.
function pickLanguage(setting, localeTag) {
    if (typeof setting === "string") {
        var chosen = languageOf(setting);
        if (chosen !== "auto" && setting !== "") return chosen;
    }
    return languageOf(localeTag);
}

var publicApi = {
    render: render,
    languageOf: languageOf,
    pickLanguage: pickLanguage
};

if (typeof module !== "undefined")
    module.exports = publicApi;

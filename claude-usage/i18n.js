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
// Fuera de alcance a propósito: el passthrough de un `desc.text` literal y
// la composición de `desc.weekday` (nombrar el día antes de encajarlo en
// reset.weekday) que hacía el `render()` local de service.luau (líneas
// 35-47 de la versión Luau). Eso es pegamento de host — cada entrada
// (Daemon.qml, Widget.qml) lo resuelve envolviendo a I18n.render, igual que
// service.luau envolvía a noctalia.tr en vez de llamarlo directo.

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

// render(descriptor, catalog, fallbackCatalog) -> string
//
//   - descriptor null/undefined, o sin `key`         -> ""
//   - `key` presente en `catalog`                     -> plantilla interpolada
//   - `key` ausente en `catalog` pero en `fallbackCatalog` -> la de éste
//   - `key` ausente en ambos                           -> la propia `key`
function render(descriptor, catalog, fallbackCatalog) {
    if (!descriptor || !descriptor.key) return "";

    var key = descriptor.key;
    var pattern = (catalog && catalog[key]) || (fallbackCatalog && fallbackCatalog[key]);
    if (!pattern) return key;

    return substitute(pattern, descriptor.params);
}

var publicApi = {
    render: render
};

if (typeof module !== "undefined")
    module.exports = publicApi;

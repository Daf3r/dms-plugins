// Pruebas de i18n.js: el renderizador que resuelve descriptores {key, params}
// contra el catálogo. Casos mínimos, calcados del contrato descrito en la
// tarea 2 y verificados contra tests/render.luau (el espejo de noctalia.tr
// de la implementación anterior) y contra §2bis de
// docs/superpowers/specs/2026-08-10-claude-usage-dms-design.md, que es quien
// pide el respaldo a un segundo catálogo: Noctalia resolvía eso dentro del
// host (noctalia.tr), y DMS no tiene ese host, así que el respaldo vive aquí.
//
// Cubre también `desc.text` (passthrough literal) y `desc.weekday`
// (traducción anidada de weekday.<N> antes de resolver la clave principal):
// logic.luau los produce directamente (labelDescriptor línea 51,
// describeAbsolute línea 360), así que son parte del contrato de render(),
// no pegamento de host. Ver la ronda de arreglo 1 en el informe de la
// tarea 2 para la discusión completa (la primera versión de este fichero
// los dejaba fuera por error).

"use strict";

var test = require("node:test");
var assert = require("node:assert/strict");

var I18n = require("../i18n.js");

test("clave presente en el catálogo principal se interpola", function () {
    var catalog = { "state.loading": "Cargando…" };
    var result = I18n.render({ key: "state.loading" }, catalog, {});
    assert.equal(result, "Cargando…");
});

test("clave ausente en el catálogo principal cae al catálogo de respaldo", function () {
    var catalog = {};
    var fallback = { "state.loading": "Loading…" };
    var result = I18n.render({ key: "state.loading" }, catalog, fallback);
    assert.equal(result, "Loading…");
});

test("clave ausente en los dos catálogos devuelve la clave literal", function () {
    var result = I18n.render({ key: "no.existe" }, {}, {});
    assert.equal(result, "no.existe");
});

test("interpola un {param} desde params", function () {
    var catalog = { "time.in": "en {duration}" };
    var result = I18n.render(
        { key: "time.in", params: { duration: "10 min" } },
        catalog,
        {}
    );
    assert.equal(result, "en 10 min");
});

test("un parámetro que falta deja el marcador intacto, sin escribir undefined", function () {
    var catalog = { "time.in": "en {duration}" };
    var result = I18n.render({ key: "time.in", params: {} }, catalog, {});
    assert.equal(result, "en {duration}");
});

test("descriptor null devuelve cadena vacía", function () {
    assert.equal(I18n.render(null, {}, {}), "");
});

test("descriptor sin key devuelve cadena vacía", function () {
    assert.equal(I18n.render({ params: { x: 1 } }, {}, {}), "");
});

test("el catálogo principal gana aunque la clave también exista en el de respaldo", function () {
    var catalog = { "state.loading": "Cargando…" };
    var fallback = { "state.loading": "Loading…" };
    var result = I18n.render({ key: "state.loading" }, catalog, fallback);
    assert.equal(result, "Cargando…");
});

test("funciona sin catálogo de respaldo (undefined)", function () {
    var catalog = { "state.loading": "Cargando…" };
    var result = I18n.render({ key: "state.loading" }, catalog);
    assert.equal(result, "Cargando…");
});

test("descriptor con text se devuelve tal cual, sin mirar el catálogo", function () {
    // Un catálogo que SÍ tendría algo para "monthly_xyz" probaría que el
    // passthrough corta el paso antes de llegar a resolve(): si mirase el
    // catálogo, este test fallaría con el valor de la clave en vez del texto.
    var catalog = { monthly_xyz: "no debería usarse nunca" };
    var result = I18n.render({ text: "monthly_xyz" }, catalog, {});
    assert.equal(result, "monthly_xyz");
});

test("descriptor con weekday presente en el catálogo se traduce e inyecta", function () {
    var catalog = { "weekday.3": "martes", "reset.weekday": "el {weekday} a las {clock}" };
    var result = I18n.render(
        { key: "reset.weekday", params: { clock: "19:30" }, weekday: 3 },
        catalog,
        {}
    );
    assert.equal(result, "el martes a las 19:30");
});

test("weekday ausente en el catálogo principal cae al de respaldo", function () {
    var catalog = { "reset.weekday": "el {weekday} a las {clock}" };
    var fallback = { "weekday.3": "Tuesday" };
    var result = I18n.render(
        { key: "reset.weekday", params: { clock: "19:30" }, weekday: 3 },
        catalog,
        fallback
    );
    assert.equal(result, "el Tuesday a las 19:30");
});

test("weekday ausente en los dos catálogos cae a la clave literal weekday.<N>", function () {
    var catalog = { "reset.weekday": "el {weekday} a las {clock}" };
    var result = I18n.render(
        { key: "reset.weekday", params: { clock: "19:30" }, weekday: 3 },
        catalog,
        {}
    );
    assert.equal(result, "el weekday.3 a las 19:30");
});

// ── pickLanguage ────────────────────────────────────────────────────────────
//
// La regla de qué idioma se usa. Vive en i18n.js, y no en cada .qml, porque la
// necesitan DOS superficies: Daemon.qml (que carga el catálogo con el que
// preformatea todo el texto del estado publicado) y Settings.qml (que carga el
// suyo para las etiquetas de los ajustes). Si divergieran, el panel de ajustes
// se vería en un idioma y la píldora en otro.
//
// Por qué existe el ajuste y no basta con la locale: una sesión con
// `i18n.defaultLocale = "en_US.UTF-8"` —que es una elección deliberada del
// usuario para el resto del escritorio— condenaría este plugin al inglés para
// siempre. Y forzar "es" lo rompería para cualquier otro, que es lo contrario
// de por qué se conservó el i18n.

test("un ajuste explícito gana a la locale", function () {
    assert.equal(I18n.pickLanguage("es", "en_US.UTF-8"), "es");
    assert.equal(I18n.pickLanguage("en", "es_ES.UTF-8"), "en");
});

test('"auto" sigue la locale', function () {
    assert.equal(I18n.pickLanguage("auto", "es_ES.UTF-8"), "es");
    assert.equal(I18n.pickLanguage("auto", "en_US.UTF-8"), "en");
});

test("el ajuste sin poner cuenta como auto", function () {
    // Es lo que devuelve getConfig() para una clave ausente, y lo que había
    // antes de que el ajuste existiera: la locale decidía sola.
    assert.equal(I18n.pickLanguage(undefined, "es_ES.UTF-8"), "es");
    assert.equal(I18n.pickLanguage(null, "es_ES.UTF-8"), "es");
    assert.equal(I18n.pickLanguage("", "es_ES.UTF-8"), "es");
});

test("del tag de locale solo interesa la lengua", function () {
    // El plugin trae un catálogo por LENGUA, no por región.
    assert.equal(I18n.pickLanguage("auto", "es_ES.UTF-8"), "es");
    assert.equal(I18n.pickLanguage("auto", "es-419"), "es");
    assert.equal(I18n.pickLanguage("auto", "pt_BR"), "pt");
    assert.equal(I18n.pickLanguage("auto", "es"), "es");
});

test("una locale ausente o vacía cae al inglés, que es el catálogo que siempre existe", function () {
    assert.equal(I18n.pickLanguage("auto", ""), "en");
    assert.equal(I18n.pickLanguage("auto", null), "en");
    assert.equal(I18n.pickLanguage("auto", undefined), "en");
});

test("un idioma sin catálogo se devuelve igual: el respaldo lo decide render, no esto", function () {
    // pickLanguage no sabe qué catálogos existen; devolver "fr" es correcto y
    // quien carga el fichero cae al respaldo inglés cuando no lo encuentra.
    assert.equal(I18n.pickLanguage("auto", "fr_FR.UTF-8"), "fr");
});

test("mayúsculas y sufijos no cambian la lengua elegida", function () {
    assert.equal(I18n.pickLanguage("ES", "en_US"), "es");
    assert.equal(I18n.pickLanguage("AUTO", "es_ES"), "es");
    assert.equal(I18n.pickLanguage("auto", "ES_es.UTF-8"), "es");
});

test("weekday no pisa otros params, y no muta el objeto params original", function () {
    var catalog = {
        "weekday.3": "martes",
        "reset.weekday": "el {weekday} a las {clock}, modelo {model}"
    };
    var originalParams = { clock: "19:30", model: "Opus" };
    var result = I18n.render(
        { key: "reset.weekday", params: originalParams, weekday: 3 },
        catalog,
        {}
    );
    assert.equal(result, "el martes a las 19:30, modelo Opus");
    // El objeto que pasó quien llama no debe llevar `weekday` añadido.
    assert.deepEqual(originalParams, { clock: "19:30", model: "Opus" });
});

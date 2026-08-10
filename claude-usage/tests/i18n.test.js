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

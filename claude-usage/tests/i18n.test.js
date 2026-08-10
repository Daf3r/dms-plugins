// Pruebas de i18n.js: el renderizador que resuelve descriptores {key, params}
// contra el catálogo. Casos mínimos, calcados del contrato descrito en la
// tarea 2 y verificados contra tests/render.luau (el espejo de noctalia.tr
// de la implementación anterior) y contra §2bis de
// docs/superpowers/specs/2026-08-10-claude-usage-dms-design.md, que es quien
// pide el respaldo a un segundo catálogo: Noctalia resolvía eso dentro del
// host (noctalia.tr), y DMS no tiene ese host, así que el respaldo vive aquí.
//
// Alcance: esta suite prueba SOLO la resolución de {key, params} contra el
// catálogo (el equivalente de noctalia.tr). El passthrough de `desc.text` y
// la composición de `desc.weekday` que hacía el `render()` local de
// service.luau (líneas 35-47) son pegamento de host: les toca a las tareas 8
// y 10 (Daemon.qml / Widget.qml), no a i18n.js. Ver el informe de la tarea 2
// para la discusión completa.

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

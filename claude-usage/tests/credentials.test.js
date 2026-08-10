// Traducción caso por caso de tests/credentials.test.luau, que es la
// ESPECIFICACIÓN de la lectura de credenciales y de la caché: mismos casos,
// mismos valores, mismos nombres. No se añade, no se quita, no se "mejora".
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · `h.nilish(x)` se convierte en `assert.equal(x, null)`. En Lua la clave
//     ausente de una tabla y el `nil` explícito son indistinguibles; aquí la
//     ausencia es SIEMPRE null y la propiedad existe (ver la cabecera de
//     logic.js), así que el aserto estricto la encuentra;
//   · `0 / 0` y `math.huge` se escriben NaN e Infinity.
//
// El bloque safeParse NO viene de Luau: allí el decode lo hacía el servicio y
// parseCredentials recibía ya la tabla (de ahí el caso "nil (decode fallido)
// es inválido"). En JS el decode es JSON.parse y vive aquí, así que se cubre
// aquí. Es la misma función que tenía el árbol de Caelestia.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");

var NOW = 1786078800000; // 2026-08-07T05:00:00Z

describe("parseCredentials", function () {
    test("credenciales sanas", function () {
        var r = Logic.parseCredentials(
            { claudeAiOauth: { accessToken: "sk-abc", expiresAt: NOW + 3600000 } }, NOW);
        assert.equal(r.status, "ok");
        assert.equal(r.token, "sk-abc");
    });

    test("vencidas dentro del margen no entregan token", function () {
        var r = Logic.parseCredentials(
            { claudeAiOauth: { accessToken: "sk-abc", expiresAt: NOW + 30000 } }, NOW);
        assert.equal(r.status, "expired");
        assert.equal(r.token, null);
    });

    test("null (decode fallido) es inválido", function () {
        assert.equal(Logic.parseCredentials(null, NOW).status, "invalid");
    });

    test("sin claudeAiOauth es inválido", function () {
        assert.equal(Logic.parseCredentials({ otra: true }, NOW).status, "invalid");
    });

    // Falla CERRADO: los tres hallazgos de seguridad de la Task 7 de Caelestia.
    // Los campos ausentes van aparte porque en Luau un nil dentro de un
    // constructor de tabla deja un hueco que la iteración se salta.
    test("expiresAt ausente NO entrega el token", function () {
        var r = Logic.parseCredentials({ claudeAiOauth: { accessToken: "sk-abc" } }, NOW);
        assert.equal(r.status, "invalid");
        assert.equal(r.token, null);
    });

    test("expiresAt no numérico NO entrega el token", function () {
        var bads = ["1786078800000", {}, true, NaN, Infinity, 0, -1];
        for (var i = 0; i < bads.length; i++) {
            var label = "expiresAt=" + String(bads[i]);
            var r = Logic.parseCredentials(
                { claudeAiOauth: { accessToken: "sk-abc", expiresAt: bads[i] } }, NOW);
            assert.equal(r.status, "invalid", label);
            assert.equal(r.token, null, label);
        }
    });

    test("accessToken ausente es inválido", function () {
        var r = Logic.parseCredentials(
            { claudeAiOauth: { expiresAt: NOW + 3600000 } }, NOW);
        assert.equal(r.status, "invalid");
        assert.equal(r.token, null);
    });

    test("accessToken vacío o no cadena es inválido", function () {
        var bads = ["", 12345, {}, true];
        for (var i = 0; i < bads.length; i++) {
            var label = "accessToken=" + String(bads[i]);
            var r = Logic.parseCredentials(
                { claudeAiOauth: { accessToken: bads[i], expiresAt: NOW + 3600000 } }, NOW);
            assert.equal(r.status, "invalid", label);
            assert.equal(r.token, null, label);
        }
    });
});

describe("extractCache", function () {
    test("extrae payload y fecha", function () {
        var r = Logic.extractCache({ cachedUsageUtilization: {
            utilization: { limits: [] }, fetchedAtMs: NOW } });
        assert.equal(r.fetchedAt, NOW);
        assert.ok(r.payload);
    });

    test("null, sin clave, o fetchedAtMs inválido devuelven null", function () {
        assert.equal(Logic.extractCache(null), null);
        assert.equal(Logic.extractCache({}), null);
        assert.equal(Logic.extractCache({ cachedUsageUtilization: {
            utilization: { limits: [] }, fetchedAtMs: 0 } }), null);
        assert.equal(Logic.extractCache({ cachedUsageUtilization: {
            utilization: { limits: [] }, fetchedAtMs: "ayer" } }), null);
        assert.equal(Logic.extractCache({ cachedUsageUtilization: {
            fetchedAtMs: NOW } }), null);
    });
});

// Sin equivalente en Luau (ver la cabecera): el decode que allí hacía el
// servicio. Devuelve null en vez de lanzar, que es lo que convierte un
// fichero corrupto en el caso "decode fallido" de parseCredentials.
describe("safeParse", function () {
    test("un documento válido se decodifica", function () {
        assert.deepEqual(Logic.safeParse('{"a":1}'), { a: 1 });
    });

    test("JSON corrupto devuelve null en vez de lanzar", function () {
        assert.equal(Logic.safeParse("{no es json"), null);
    });

    test("entrada vacía o que no es cadena devuelve null", function () {
        var bads = ["", null, undefined, 0, {}, true];
        for (var i = 0; i < bads.length; i++) {
            assert.equal(Logic.safeParse(bads[i]), null, "safeParse=" + String(bads[i]));
        }
    });
});

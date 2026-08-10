// parseRetryAfter: la ÚNICA pieza que viaja en sentido contrario al resto del
// port. No está en logic.luau porque el port a Noctalia la eliminó — su API
// HTTP no exponía las cabeceras de respuesta. En DMS sí se leen (el spike de
// la tarea 1 confirmó `XMLHttpRequest.getResponseHeader()`: la píldora de
// prueba devolvió `status=429 date=SI`), y el 429 no es teórico: el endpoint
// lo devolvió de verdad con muy poco tráfico.
//
// Los casos se recuperan tal cual del árbol de Caelestia:
//   cd ~/Projects/caelestia-plugins
//   git show feat/claude-usage:claude-usage/tests/logic.test.js
//
// ÚNICA adaptación: allí `now` era un objeto Date; aquí es un epoch en
// MILISEGUNDOS, que es el contrato de fechas de todo este módulo
// (parseCredentials, notificationsFor, describeAbsolute… todos toman nowMs).
// El caso "el reloj no es una fecha válida" se traduce por tanto a un nowMs
// que validMs rechaza: NaN y null en vez de `new Date("not-a-date")` y null.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");

describe("parseRetryAfter", function () {
    test("interpreta la forma delta-seconds", function () {
        var now = Date.UTC(2026, 7, 3, 8, 0, 0);
        assert.equal(Logic.parseRetryAfter("120", now), 120);
        assert.equal(Logic.parseRetryAfter("0", now), 0);
    });

    test("tolera espacios alrededor de delta-seconds", function () {
        var now = Date.UTC(2026, 7, 3, 8, 0, 0);
        assert.equal(Logic.parseRetryAfter(" 30 ", now), 30);
    });

    test("interpreta la forma de fecha HTTP (RFC 7231) en vez de devolver NaN||0", function () {
        var now = Date.UTC(2015, 9, 21, 7, 26, 0);
        var header = "Wed, 21 Oct 2015 07:28:00 GMT";
        // parseInt(header, 10) da NaN aquí; el fallback ingenuo `|| 0`
        // ignoraría los 120 s que el servidor pidió esperar tras un 429.
        assert.equal(Logic.parseRetryAfter(header, now), 120);
    });

    test("cae a 0 si la fecha HTTP ya pasó, nunca a un reintento inmediato negativo", function () {
        var now = Date.UTC(2015, 9, 21, 7, 30, 0);
        var header = "Wed, 21 Oct 2015 07:28:00 GMT";
        assert.equal(Logic.parseRetryAfter(header, now), 0);
    });

    test("cae a 0 ante una cabecera que no es ninguna de las dos formas", function () {
        var now = Date.UTC(2026, 7, 3, 8, 0, 0);
        var bads = ["", "no-es-un-numero-ni-una-fecha", "-5", "120.5", null, undefined, 120];
        for (var i = 0; i < bads.length; i++) {
            assert.equal(Logic.parseRetryAfter(bads[i], now), 0,
                "header=" + String(bads[i]));
        }
    });

    test("cae a 0 si el reloj (now) no es un epoch válido", function () {
        assert.equal(Logic.parseRetryAfter("120", NaN), 0);
        assert.equal(Logic.parseRetryAfter("120", null), 0);
    });
});

// Traducción caso por caso de tests/cadence.test.luau, que es la
// ESPECIFICACIÓN de la cadencia de sondeo: mismos casos, mismos valores,
// mismos nombres. No se añade, no se quita, no se "mejora".
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · `0 / 0` y `math.huge` se escriben NaN e Infinity;
//   · un ajuste ausente es `undefined` (la propiedad no existe) donde el
//     original tenía `nil`;
//   · el bucle sobre entrada basura usa un array literal, no `{...} :: any`.
//
// ADEMÁS: el bloque "Retry-After" NO viene de Luau. Viaja en sentido
// contrario al resto del port — el port a Noctalia lo eliminó porque su API
// HTTP no exponía cabeceras de respuesta, y en DMS sí se leen
// (XMLHttpRequest.getResponseHeader). Los casos se recuperan tal cual del
// árbol de Caelestia:
//   git show feat/claude-usage:claude-usage/tests/logic.test.js
// Ver la cabecera de retry-after.test.js para el detalle de parseRetryAfter.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");

describe("nextInterval", function () {
    test("reposo y alerta usan sus bases", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            idleInterval: 300, alertInterval: 60 }), 300);
        assert.equal(Logic.nextInterval({ warning: true, failures: 0,
            idleInterval: 300, alertInterval: 60 }), 60);
    });

    test("el backoff dobla por fallo hasta el techo", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 1,
            idleInterval: 300, alertInterval: 60 }), 600);
        assert.equal(Logic.nextInterval({ warning: false, failures: 2,
            idleInterval: 300, alertInterval: 60 }), 1200);
        assert.equal(Logic.nextInterval({ warning: false, failures: 3,
            idleInterval: 300, alertInterval: 60 }), 1800); // techo
        assert.equal(Logic.nextInterval({ warning: false, failures: 9,
            idleInterval: 300, alertInterval: 60 }), 1800);
    });

    // La corrección que costó la Task 9b de Caelestia. No reintroducir.
    test("un fallo NUNCA sondea más rápido que la base del usuario", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 1,
            idleInterval: 3600, alertInterval: 60 }), 3600);
    });

    test("la base del usuario se respeta aunque supere el techo", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            idleInterval: 3600, alertInterval: 60 }), 3600);
    });

    // El ajuste ausente va aparte: en Luau un `nil` dentro de un constructor
    // de tabla deja un hueco que la iteración generalizada se salta, así que
    // en la lista de abajo nunca se probaría. Aquí se conserva como caso
    // propio para que la traducción sea caso a caso.
    test("un intervalo ausente cae al default del spec", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            alertInterval: 60 }), 300);
        assert.equal(Logic.nextInterval({ warning: true, failures: 0,
            idleInterval: 300 }), 60);
    });

    test("entrada basura cae al default del spec, no al suelo", function () {
        var bads = [0, -5, NaN, Infinity, "300", {}, true];
        for (var i = 0; i < bads.length; i++) {
            assert.equal(Logic.nextInterval({ warning: false, failures: 0,
                idleInterval: bads[i], alertInterval: 60 }), 300,
                "idleInterval=" + String(bads[i]));
        }
    });

    test("el suelo protege de una base minúscula", function () {
        assert.equal(Logic.nextInterval({ warning: true, failures: 0,
            idleInterval: 300, alertInterval: 1 }), 15);
    });
});

// Bloque recuperado de Caelestia (no está en cadence.test.luau): la rama de
// Retry-After de nextInterval y el clamp que la acota.
describe("nextInterval con Retry-After", function () {
    test("respeta Retry-After por encima de todo, con techo", function () {
        assert.equal(Logic.nextInterval({ warning: true, failures: 0,
            idleInterval: 300, alertInterval: 60, retryAfter: 120 }), 120);
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            idleInterval: 300, alertInterval: 60, retryAfter: 99999 }), 1800);
    });

    test("un retryAfter no numérico cae al camino normal", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            idleInterval: 300, alertInterval: 60,
            retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT" }), 300);
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            idleInterval: 300, alertInterval: 60, retryAfter: -10 }), 300);
    });

    test("da precedencia a retryAfter sobre el backoff por fallos", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 5,
            idleInterval: 300, alertInterval: 60, retryAfter: 120 }), 120);
    });

    test("aplica el suelo también a retryAfter", function () {
        assert.equal(Logic.nextInterval({ warning: false, failures: 0,
            idleInterval: 300, alertInterval: 60, retryAfter: 5 }), 15);
    });
});

describe("toMilliseconds", function () {
    test("convierte segundos a la unidad del host", function () {
        assert.equal(Logic.toMilliseconds(300), 300000);
    });
});

// Los defaults son parte del contrato público: el panel de ajustes (tarea 12)
// se ata a estas constantes en vez de repetir los números.
describe("constantes exportadas", function () {
    test("los defaults del spec están exportados", function () {
        assert.equal(Logic.DEFAULT_IDLE_INTERVAL, 300);
        assert.equal(Logic.DEFAULT_ALERT_INTERVAL, 60);
        assert.equal(Logic.DEFAULT_WARN_THRESHOLD, 90);
        assert.equal(Logic.MIN_INTERVAL, 15);
        assert.equal(Logic.MAX_INTERVAL, 1800);
    });
});

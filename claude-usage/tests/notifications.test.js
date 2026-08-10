// Traducción caso por caso de tests/notifications.test.luau, que es la
// ESPECIFICACIÓN del antirrebote de notificaciones: mismos casos, mismos
// valores, mismos nombres. No se añade, no se quita, no se "mejora".
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · el catálogo se carga del .json de origen (require) en vez de la fixture
//     generada tests/translations.fixture.luau, y se renderiza con i18n.js en
//     vez de con tests/render.luau;
//   · el ancla local se construye con `new Date(y, mo - 1, ...)`, que ya
//     interpreta hora LOCAL — en Luau hacía falta h.localMs porque os.time
//     interpreta su tabla en UTC;
//   · `nil` se convierte en `null` (ver la cabecera de logic.js);
//   · `#r.notifications` es `r.notifications.length`, y `r.notifications[1]`
//     es `r.notifications[0]`: los índices de Luau empiezan en 1.
//
// La TZ la fija tests/run-js.fish (Europe/Madrid). Sin ella, la cláusula
// "se reinicia mañana a las 07:00" no es determinista.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");
var I18n = require("../i18n.js");

var ES = require("../translations/es.json");
var EN = require("../translations/en.json");

// Epoch en ms de una hora de pared LOCAL. Equivalente de h.localMs.
function ms(y, mo, d, hh, mm) {
    return new Date(y, mo - 1, d, hh, mm, 0, 0).getTime();
}

// Horas de pared locales: el cuerpo esperado de la notificación las lleva
// escritas.
var NOW = ms(2026, 8, 7, 9, 0);
var RESET = ms(2026, 8, 8, 7, 0);

function limit(key, percent, severity, resetsAt) {
    return { key: key, label: { key: "limit.weeklyAll" }, percent: percent,
             severity: severity, resetsAt: resetsAt, scope: null, primary: true };
}

// notificationsFor no devuelve el cuerpo montado: devuelve las piezas y es el
// servicio quien las pasa por el catálogo. Esto reproduce esa composición para
// poder seguir afirmando el texto que de verdad llega a la notificación.
function body(n, cat) {
    var key = n.reset ? "notify.bodyWithReset" : "notify.body";
    return I18n.render({
        key: key,
        params: {
            percent: n.percent,
            limit: I18n.render(n.label, cat),
            reset: I18n.render(n.reset, cat)
        }
    }, cat);
}

describe("notificationsFor", function () {
    test("notifica al cruzar el umbral", function () {
        var r = Logic.notificationsFor([limit("weekly_all", 90, "normal", RESET)],
                                       90, {}, NOW);
        assert.equal(r.notifications.length, 1);
        assert.equal(body(r.notifications[0], ES),
            "90 % de Semana consumido · se reinicia mañana a las 07:00");
        assert.equal(body(r.notifications[0], EN),
            "90 % of Week used · resets tomorrow at 07:00");
        assert.equal(r.nextState["weekly_all"].notified, true);
    });

    test("no vuelve a notificar dentro de la misma ventana", function () {
        var first = Logic.notificationsFor([limit("weekly_all", 90, "normal", RESET)],
                                           90, {}, NOW);
        var second = Logic.notificationsFor([limit("weekly_all", 95, "normal", RESET)],
                                            90, first.nextState, NOW);
        assert.equal(second.notifications.length, 0);
    });

    test("una ventana nueva rearma el aviso", function () {
        var first = Logic.notificationsFor([limit("weekly_all", 90, "normal", RESET)],
                                           90, {}, NOW);
        var newReset = RESET + 7 * 24 * 3600000;
        var second = Logic.notificationsFor([limit("weekly_all", 91, "normal", newReset)],
                                            90, first.nextState, NOW);
        assert.equal(second.notifications.length, 1);
    });

    // Rama dip-and-rise: el ledger de la Task 8 la dejó SIN test. Aquí sí.
    test("bajar y volver a subir en la misma ventana no re-notifica", function () {
        var a = Logic.notificationsFor([limit("weekly_all", 91, "normal", RESET)],
                                       90, {}, NOW);
        var b = Logic.notificationsFor([limit("weekly_all", 85, "normal", RESET)],
                                       90, a.nextState, NOW);
        var c = Logic.notificationsFor([limit("weekly_all", 92, "normal", RESET)],
                                       90, b.nextState, NOW);
        assert.equal(c.notifications.length, 0);
    });

    test("por debajo del umbral no notifica pero conserva la ventana", function () {
        var r = Logic.notificationsFor([limit("weekly_all", 10, "normal", RESET)],
                                       90, {}, NOW);
        assert.equal(r.notifications.length, 0);
        assert.equal(r.nextState["weekly_all"].notified, false);
    });

    test("un threshold inválido cae al default, no a cero", function () {
        var r = Logic.notificationsFor([limit("weekly_all", 50, "normal", RESET)],
                                       null, {}, NOW);
        assert.equal(r.notifications.length, 0); // 50 < 90; con threshold 0 habría notificado
    });

    // Sin cláusula la clave cambia entera (notify.body, no bodyWithReset): son
    // dos frases distintas y no una con un trozo pegado, porque dónde encaja el
    // "se reinicia …" lo decide la lengua.
    test("sin resetsAt válido omite la cláusula entera", function () {
        var r = Logic.notificationsFor([limit("weekly_all", 95, "normal", null)],
                                       90, {}, NOW);
        assert.equal(r.notifications[0].reset, null);
        assert.equal(body(r.notifications[0], ES), "95 % de Semana consumido");
        assert.equal(body(r.notifications[0], EN), "95 % of Week used");
    });

    test("sin un now válido omite la cláusula entera", function () {
        var r = Logic.notificationsFor([limit("weekly_all", 95, "normal", RESET)],
                                       90, {}, null);
        assert.equal(r.notifications[0].reset, null);
        assert.equal(body(r.notifications[0], ES), "95 % de Semana consumido");
    });

    test("limits que no es lista devuelve vacío sin lanzar", function () {
        var r = Logic.notificationsFor(null, 90, {}, NOW);
        assert.equal(r.notifications.length, 0);
    });

    // El plan escribía `{ nil, limit(...) }`, pero en Luau un nil en un
    // constructor deja un hueco que la iteración se salta: la guarda
    // `type(limit) ~= "table"` quedaba sin ejercitar. Con valores reales sí se
    // recorre.
    test("una entrada que no es objeto se salta sin lanzar", function () {
        var r = Logic.notificationsFor(
            [false, "basura", 42, limit("weekly_all", 95, "normal", RESET)],
            90, {}, NOW);
        assert.equal(r.notifications.length, 1);
        assert.equal(r.notifications[0].key, "weekly_all");
    });

    test("prevState que no es objeto se trata como vacío", function () {
        var r = Logic.notificationsFor([limit("weekly_all", 95, "normal", RESET)],
                                       90, "basura", NOW);
        assert.equal(r.notifications.length, 1);
    });
});

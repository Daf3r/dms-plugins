// Traducción caso por caso de tests/fixtures.test.luau: mismos casos, mismos
// valores, mismos nombres. No se añade, no se quita, no se "mejora".
//
// El fixture entra como JSON de la API y sale como el texto que el usuario lee,
// en los dos idiomas: es el tramo más largo que se puede probar sin levantar el
// shell.
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · los `.json` de tests/fixtures/ se cargan DIRECTAMENTE con require. En
//     Luau había que convertirlos antes a un módulo (tests/json2luau.py, que
//     invocaba tests/run.fish) porque el intérprete no parsea JSON ni tiene
//     `io`. node sí, así que el conversor se borra con esta tarea y
//     `payloads.fixture.luau` deja de tener sucesor;
//   · el catálogo se carga del .json de origen y se resuelve con i18n.render en
//     vez de con tests/render.luau;
//   · los índices de `limits` van de 0 en adelante, no de 1;
//   · `h.nilish(x)` se convierte en `assert.equal(x, null)`, que además
//     distingue null de undefined — ver el primer test de "carga", donde esa
//     distinción cambia lo que se está afirmando.
//
// La TZ la fija tests/run-js.fish (Europe/Madrid).

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");
var I18n = require("../i18n.js");

var ES = require("../translations/es.json");
var EN = require("../translations/en.json");

function es(desc) {
    return I18n.render(desc, ES);
}
function en(desc) {
    return I18n.render(desc, EN);
}

// Monta el importe como lo hará el panel: las piezas de describeMoney puestas
// en las plantillas del catálogo (format.decimal decide el separador,
// format.money el lado del símbolo).
function money(m, cat) {
    var text = m.cents === null ? m.whole : m.whole + cat["format.decimal"] + m.cents;
    return I18n.render(
        { key: "format.money", params: { amount: text, symbol: m.symbol } }, cat);
}

// Payloads reales de la API, heredados de Caelestia. Se leen tal cual, sin
// conversión: son los mismos ficheros que consumía el original.
//
// Esto es lo más parecido a una prueba extremo a extremo que se puede hacer
// sin levantar el shell: entra el JSON tal cual lo devuelve Anthropic y sale
// lo que el widget y el panel van a pintar.
var F = {
    "usage-normal": require("./fixtures/usage-normal.json"),
    "usage-warning": require("./fixtures/usage-warning.json"),
    "usage-credits-on": require("./fixtures/usage-credits-on.json"),
    "usage-no-limits": require("./fixtures/usage-no-limits.json")
};

// Epoch en ms de una hora de pared LOCAL (el equivalente de h.localMs).
function ms(y, mo, d, hh, mm) {
    return new Date(y, mo - 1, d, hh, mm, 0, 0).getTime();
}

// 2026-08-03 12:00 hora local de Madrid. Los resets de los fixtures caen ese
// mismo día por la tarde y a la mañana siguiente.
var NOW = ms(2026, 8, 3, 12, 0);

var SESSION_RESET = 1785777000000; // 2026-08-03T17:10:00Z
var WEEKLY_RESET = 1785819600000; // 2026-08-04T05:00:00Z

describe("fixtures / carga", function () {
    test("los cuatro fixtures cargan", function () {
        var names = ["usage-normal", "usage-warning",
                     "usage-credits-on", "usage-no-limits"];
        for (var i = 0; i < names.length; i++) {
            assert.ok(F[names[i]], "falta el fixture " + names[i]);
            assert.equal(typeof F[names[i]], "object", names[i] + " no es objeto");
        }
    });

    // Aquí el port DIVERGE del original, y a propósito. En Luau el conversor
    // dejaba caer los null (una tabla no puede tener un valor nil), así que el
    // test afirmaba "llega como campo ausente". En node el null sobrevive al
    // require, que es lo que de verdad recibe el daemon: JSON.parse tampoco lo
    // pierde. Lo que se afirma es lo mismo — que la lógica lo trata como
    // ausencia — pero ahora con el valor real delante, que es el caso más duro.
    test("un null de JSON llega como null, y la lógica lo trata como ausencia", function () {
        // "scope": null en usage-credits-on, "spend"/"extra_usage": null en
        // usage-no-limits.
        assert.equal(F["usage-credits-on"].limits[0].scope, null);
        assert.equal(F["usage-no-limits"].spend, null);
        assert.equal(F["usage-no-limits"].extra_usage, null);

        var model = Logic.normalizeUsage(F["usage-credits-on"], "api", NOW);
        assert.equal(model.limits[0].scope, null);
        assert.equal(model.limits[0].key, "session"); // sin sufijo de scope
    });
});

describe("fixtures / usage-normal", function () {
    var model = Logic.normalizeUsage(F["usage-normal"], "api", NOW);

    test("normaliza las tres ventanas con sus etiquetas", function () {
        assert.equal(model.limits.length, 3);
        assert.equal(model.limits[0].key, "session");
        assert.equal(es(model.limits[0].label), "Sesión 5 h");
        assert.equal(model.limits[1].key, "weekly_all");
        assert.equal(es(model.limits[1].label), "Semana");
        assert.equal(en(model.limits[1].label), "Week");
        assert.equal(model.limits[2].key, "weekly_scoped:Fable");
        assert.equal(es(model.limits[2].label), "Fable · semanal");
        assert.equal(model.limits[2].scope, "Fable");
    });

    test("los porcentajes salen del array limits[]", function () {
        assert.equal(model.limits[0].percent, 9);
        assert.equal(model.limits[1].percent, 21);
        assert.equal(model.limits[2].percent, 3);
    });

    // Esta es la comprobación que de verdad importa del lote: parseIsoMs contra
    // el formato EXACTO que emite la API, con microsegundos y offset +00:00.
    test("parsea los resets reales, con fracción y offset", function () {
        assert.equal(model.limits[0].resetsAt, SESSION_RESET);
        assert.equal(model.limits[1].resetsAt, WEEKLY_RESET);
    });

    test("solo session y weekly_all son primarios", function () {
        assert.equal(model.limits[0].primary, true);
        assert.equal(model.limits[1].primary, true);
        assert.equal(model.limits[2].primary, false);
    });

    // La sesión es la primaria aunque vaya por debajo (9 % contra 21 %): es la
    // ventana que va en la barra, no la que más ha subido.
    test("el primario es la sesión, no la que va más alta", function () {
        var primary = Logic.pickPrimary(model.limits);
        assert.equal(primary.key, "session");
        assert.equal(primary.percent, 9);
        assert.equal(Logic.isWarning(primary, 90), false);
    });

    test("el panel muestra el resto ordenado por criticidad", function () {
        var rest = Logic.sortForPanel(model.limits, "weekly_all");
        assert.equal(rest.length, 2);
        assert.equal(rest[0].key, "session"); // 9 %
        assert.equal(rest[1].key, "weekly_scoped:Fable"); // 3 %
    });

    test("nada oculto en aviso, y ninguna notificación", function () {
        assert.equal(Logic.hasHiddenWarning(model.limits, "weekly_all", 90), false);
        assert.equal(
            Logic.notificationsFor(model.limits, 90, {}, NOW).notifications.length, 0);
    });

    test("spend manda sobre extra_usage aunque esté deshabilitado", function () {
        var x = model.extraUsage;
        assert.equal(x.enabled, false);
        assert.equal(x.everEnabled, true); // credits_ever_enabled de extra_usage
        assert.equal(x.usedMinor, 0);
        assert.equal(x.limitMinor, 3000);
        assert.equal(x.currency, "USD");
        assert.equal(x.disabledReason, "out_of_credits");
        assert.equal(money(Logic.describeMoney(x.usedMinor, x.exponent, x.currency), ES),
                     "0,00 $");
        assert.equal(money(Logic.describeMoney(x.limitMinor, x.exponent, x.currency), ES),
                     "30,00 $");
    });

    test("los textos de fecha que verá el usuario", function () {
        // NOW son las 12:00 locales; el reset de sesión, las 19:10 locales.
        var session = model.limits[0];
        assert.equal(es(Logic.describeAbsolute(session.resetsAt, NOW)), "a las 19:10");
        assert.equal(es(Logic.describeRelative(session.resetsAt, NOW)), "en 7 h 10 min");
        var weekly = model.limits[1];
        assert.equal(es(Logic.describeAbsolute(weekly.resetsAt, NOW)), "mañana a las 07:00");
        assert.equal(es(Logic.describeRelative(weekly.resetsAt, NOW)), "en 19 h");
    });
});

describe("fixtures / usage-warning", function () {
    var model = Logic.normalizeUsage(F["usage-warning"], "api", NOW);

    // La barra lleva la sesión (42 %, tranquila) mientras la semanal está en
    // aviso al 88 %. Ese es el caso que justifica el punto: sin él, la ventana
    // que de verdad va mal no deja rastro en la barra.
    test("la semanal en aviso no es la primaria, pero sí deja punto", function () {
        var primary = Logic.pickPrimary(model.limits);
        assert.equal(primary.key, "session");
        assert.equal(Logic.isWarning(primary, 90), false);
        assert.equal(Logic.hasHiddenWarning(model.limits, primary.key, 90), true);
    });

    test("la severidad de la API gana al porcentaje, en el orden del panel", function () {
        var rest = Logic.sortForPanel(model.limits, "session");
        assert.equal(rest[0].key, "weekly_all");
        assert.equal(rest[0].percent, 88);
        assert.equal(rest[0].severity, "warning");
        // 88 < 90, así que el aviso viene de la severidad, no del umbral local
        assert.equal(Logic.isWarning(rest[0], 90), true);
    });

    test("notifica una sola vez, con el cuerpo completo", function () {
        var r = Logic.notificationsFor(model.limits, 90, {}, NOW);
        assert.equal(r.notifications.length, 1);
        assert.equal(r.notifications[0].key, "weekly_all");
        assert.equal(
            I18n.render({ key: "notify.bodyWithReset", params: {
                percent: r.notifications[0].percent,
                limit: es(r.notifications[0].label),
                reset: es(r.notifications[0].reset) } }, ES),
            "88 % de Semana consumido · se reinicia mañana a las 07:00");
    });

    test("el antirrebote aguanta un segundo sondeo idéntico", function () {
        var first = Logic.notificationsFor(model.limits, 90, {}, NOW);
        var second = Logic.notificationsFor(model.limits, 90, first.nextState, NOW);
        assert.equal(second.notifications.length, 0);
    });
});

describe("fixtures / usage-no-limits", function () {
    var model = Logic.normalizeUsage(F["usage-no-limits"], "cache", NOW);

    test("sin limits[] cae a five_hour / seven_day", function () {
        assert.equal(model.limits.length, 2);
        assert.equal(model.limits[0].key, "session");
        assert.equal(model.limits[0].percent, 42);
        assert.equal(model.limits[1].key, "weekly_all");
        assert.equal(model.limits[1].percent, 88);
        assert.equal(model.source, "cache");
    });

    test("los objetos sueltos no traen severidad", function () {
        assert.equal(model.limits[0].severity, "normal");
        assert.equal(model.limits[1].severity, "normal");
        // sin severidad, el aviso depende SOLO del umbral local
        assert.equal(Logic.isWarning(model.limits[1], 90), false);
        assert.equal(Logic.isWarning(model.limits[1], 80), true);
    });

    test("también parsea sus resets", function () {
        assert.equal(model.limits[0].resetsAt, SESSION_RESET);
        assert.equal(model.limits[1].resetsAt, WEEKLY_RESET);
    });

    test("sin spend ni extra_usage no hay créditos", function () {
        assert.equal(model.extraUsage, null);
    });
});

describe("fixtures / usage-credits-on", function () {
    var model = Logic.normalizeUsage(F["usage-credits-on"], "api", NOW);

    test("una sola ventana, y es la primaria", function () {
        assert.equal(model.limits.length, 1);
        var primary = Logic.pickPrimary(model.limits);
        assert.equal(primary.key, "session");
        assert.equal(primary.percent, 12);
        assert.equal(Logic.sortForPanel(model.limits, "session").length, 0);
    });

    test("los créditos salen de spend, en unidades menores", function () {
        var x = model.extraUsage;
        assert.equal(x.enabled, true);
        assert.equal(x.everEnabled, true);
        assert.equal(x.usedMinor, 750);
        assert.equal(x.limitMinor, 3000);
        assert.equal(x.percent, 25);
        // lo que el panel pinta en la fila de créditos extra
        assert.equal(money(Logic.describeMoney(x.usedMinor, x.exponent, x.currency), ES),
                     "7,50 $");
        assert.equal(money(Logic.describeMoney(x.limitMinor, x.exponent, x.currency), ES),
                     "30,00 $");
    });

    test("un reset con Z pelada también se parsea", function () {
        assert.equal(model.limits[0].resetsAt, SESSION_RESET);
    });
});

// Traducción caso por caso de tests/normalize.test.luau, que es la
// ESPECIFICACIÓN de la normalización del payload: mismos casos, mismos
// valores, mismos nombres. No se añade, no se quita, no se "mejora".
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · el catálogo se carga del .json de origen (require) en vez de la fixture
//     generada tests/translations.fixture.luau, y se resuelve con i18n.render
//     en vez de con tests/render.luau;
//   · los índices de `limits` van de 0 en adelante, no de 1: `r.limits[1]` del
//     original es `r.limits[0]` aquí, y `r.limits[3]` es `r.limits[2]`;
//   · `h.nilish(x)` se convierte en `assert.equal(x, null)` — ver la nota de
//     logic.js sobre por qué la ausencia es null y nunca undefined; el assert
//     estricto distingue los dos, así que esta comprobación es más fuerte que
//     la del original;
//   · `disabled_reason = nil` de Luau es una clave AUSENTE, no una clave con
//     valor nulo: aquí se omite la propiedad.
//
// La TZ la fija tests/run-js.fish (Europe/Madrid), igual que en format.test.js.

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

describe("severityRank", function () {
    test("conoce los tres estados", function () {
        assert.equal(Logic.severityRank("normal"), 0);
        assert.equal(Logic.severityRank("warning"), 1);
        assert.equal(Logic.severityRank("critical"), 2);
    });
    test("una severidad desconocida se rankea como crítica", function () {
        assert.equal(Logic.severityRank("meltdown"), 2);
        assert.equal(Logic.severityRank(null), 2);
    });
});

describe("labelDescriptor", function () {
    test("etiqueta las tres clases", function () {
        assert.equal(es(Logic.labelDescriptor("session", null)), "Sesión 5 h");
        assert.equal(en(Logic.labelDescriptor("session", null)), "5 h session");
        assert.equal(es(Logic.labelDescriptor("weekly_all", null)), "Semana");
        assert.equal(es(Logic.labelDescriptor("weekly_scoped", "Opus")), "Opus · semanal");
        assert.equal(en(Logic.labelDescriptor("weekly_scoped", "Opus")), "Opus · weekly");
    });
    test("weekly_scoped sin nombre de modelo", function () {
        assert.equal(es(Logic.labelDescriptor("weekly_scoped", null)), "Sublímite semanal");
    });
    // Un kind que no conocemos no tiene clave que traducir: viaja como `text` y
    // se pinta crudo, para que el usuario vea el nombre y no una clave rota.
    test("un kind desconocido se devuelve tal cual", function () {
        assert.equal(Logic.labelDescriptor("monthly_xyz", null).text, "monthly_xyz");
        assert.equal(es(Logic.labelDescriptor("monthly_xyz", null)), "monthly_xyz");
    });
});

describe("parseIsoMs", function () {
    // 1786078800000 es 2026-08-07T05:00:00Z. El plan traía 1786251600000, que
    // es el día 9, no el 7.
    test("parsea una fecha UTC con offset Z", function () {
        assert.equal(Logic.parseIsoMs("2026-08-07T05:00:00Z"), 1786078800000);
    });
    test("un offset explícito de cero equivale a Z", function () {
        assert.equal(Logic.parseIsoMs("2026-08-07T05:00:00+00:00"), 1786078800000);
    });
    test("un offset positivo se resta para llegar a UTC", function () {
        // 07:00+02:00 es el mismo instante que 05:00Z
        assert.equal(Logic.parseIsoMs("2026-08-07T07:00:00+02:00"), 1786078800000);
    });
    test("un offset negativo se suma", function () {
        // 00:00-05:00 es el mismo instante que 05:00Z
        assert.equal(Logic.parseIsoMs("2026-08-07T00:00:00-05:00"), 1786078800000);
    });
    test("tolera fracciones de segundo y offset sin dos puntos", function () {
        assert.equal(Logic.parseIsoMs("2026-08-07T05:00:00.123Z"), 1786078800000);
        assert.equal(Logic.parseIsoMs("2026-08-07T07:00:00+0200"), 1786078800000);
    });
    test("devuelve null ante basura o ausencia", function () {
        assert.equal(Logic.parseIsoMs("no soy una fecha"), null);
        assert.equal(Logic.parseIsoMs(null), null);
        assert.equal(Logic.parseIsoMs(""), null);
    });
});

describe("normalizeUsage", function () {
    test("payload null devuelve la forma vacía sin lanzar", function () {
        var r = Logic.normalizeUsage(null, "api", 1000);
        assert.equal(r.limits.length, 0);
        assert.equal(r.extraUsage, null);
        assert.equal(r.source, "api");
    });

    test("limits[] es la fuente canónica", function () {
        var payload = {
            limits: [
                { kind: "session", percent: 42.4, severity: "normal",
                  resets_at: "2026-08-07T05:00:00Z" },
                { kind: "weekly_all", percent: 88, severity: "warning",
                  resets_at: "2026-08-08T05:00:00Z" },
                { kind: "weekly_scoped", percent: 3, severity: "normal",
                  resets_at: "2026-08-08T05:00:00Z",
                  scope: { model: { display_name: "Opus" } } }
            ]
        };
        var r = Logic.normalizeUsage(payload, "api", 1000);
        assert.equal(r.limits.length, 3);
        assert.equal(r.limits[0].key, "session");
        assert.equal(r.limits[0].percent, 42); // redondeado
        assert.equal(r.limits[0].primary, true);
        assert.equal(r.limits[2].key, "weekly_scoped:Opus");
        assert.equal(es(r.limits[2].label), "Opus · semanal");
        assert.equal(r.limits[2].scope, "Opus");
        assert.equal(r.limits[2].primary, false);
    });

    test("sin limits[] cae a five_hour / seven_day", function () {
        var payload = {
            limits: [],
            five_hour: { utilization: 42, resets_at: "2026-08-07T05:00:00Z" },
            seven_day: { utilization: 88, resets_at: "2026-08-08T05:00:00Z" }
        };
        var r = Logic.normalizeUsage(payload, "cache", 1000);
        assert.equal(r.limits.length, 2);
        assert.equal(r.limits[0].key, "session");
        assert.equal(r.limits[1].key, "weekly_all");
        // los objetos sueltos no traen severidad
        assert.equal(r.limits[0].severity, "normal");
        assert.equal(r.limits[0].primary, true);
    });

    test("campos ausentes degradan a cero sin lanzar", function () {
        var r = Logic.normalizeUsage({ limits: [{ kind: "session" }] }, "api", null);
        assert.equal(r.limits[0].percent, 0);
        assert.equal(r.limits[0].severity, "normal");
        assert.equal(r.limits[0].resetsAt, null);
    });
});

describe("normalizeUsage / extraUsage", function () {
    test("spend tiene preferencia sobre extra_usage", function () {
        var payload = {
            limits: [],
            spend: {
                enabled: true, percent: 8,
                used: { amount_minor: 240, currency: "USD", exponent: 2 },
                limit: { amount_minor: 3000, currency: "USD", exponent: 2 }
            },
            extra_usage: {
                is_enabled: false, credits_ever_enabled: true,
                used_credits: 99, monthly_limit: 99, currency: "EUR"
            }
        };
        var r = Logic.normalizeUsage(payload, "api", 1000);
        assert.equal(r.extraUsage.usedMinor, 240);
        assert.equal(r.extraUsage.limitMinor, 3000);
        assert.equal(r.extraUsage.currency, "USD");
        assert.equal(r.extraUsage.enabled, true);
        assert.equal(r.extraUsage.everEnabled, true);
    });

    test("sin spend, extra_usage convierte créditos decimales a menores", function () {
        var payload = {
            limits: [],
            extra_usage: {
                is_enabled: true, credits_ever_enabled: true,
                used_credits: 2.4, monthly_limit: 3000,
                currency: "USD", decimal_places: 2, utilization: 8
                // `disabled_reason = nil` del original: en Luau eso es no poner
                // la clave, así que aquí tampoco se pone.
            }
        };
        var r = Logic.normalizeUsage(payload, "api", 1000);
        assert.equal(r.extraUsage.usedMinor, 240);
        assert.equal(r.extraUsage.exponent, 2);
        assert.equal(r.extraUsage.percent, 8);
    });

    test("sin spend ni extra_usage devuelve null", function () {
        var r = Logic.normalizeUsage({ limits: [] }, "api", 1000);
        assert.equal(r.extraUsage, null);
    });
});

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert");
const Logic = require("../logic.js");

function fixture(name) {
    return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"));
}

test("severityRank ordena las severidades conocidas", () => {
    assert.strictEqual(Logic.severityRank("normal"), 0);
    assert.strictEqual(Logic.severityRank("warning"), 1);
    assert.strictEqual(Logic.severityRank("critical"), 2);
});

test("severityRank trata lo desconocido como critico", () => {
    assert.strictEqual(Logic.severityRank("apocalyptic"), 2);
    assert.strictEqual(Logic.severityRank(null), 2);
    assert.strictEqual(Logic.severityRank(undefined), 2);
});

test("limitLabel etiqueta cada tipo de limite", () => {
    assert.strictEqual(Logic.limitLabel("session", null), "Sesión 5 h");
    assert.strictEqual(Logic.limitLabel("weekly_all", null), "Semana");
    assert.strictEqual(Logic.limitLabel("weekly_scoped", "Fable"), "Fable · semanal");
    assert.strictEqual(Logic.limitLabel("weekly_scoped", null), "Sublímite semanal");
    assert.strictEqual(Logic.limitLabel("kind_nuevo", null), "kind_nuevo");
});

test("normalizeUsage mapea limits[] al modelo interno", () => {
    const now = new Date("2026-08-03T06:36:00Z");
    const out = Logic.normalizeUsage(fixture("usage-warning.json"), "api", now);

    assert.strictEqual(out.source, "api");
    assert.strictEqual(out.fetchedAt.getTime(), now.getTime());
    assert.strictEqual(out.limits.length, 3);

    const session = out.limits.find(l => l.key === "session");
    assert.strictEqual(session.label, "Sesión 5 h");
    assert.strictEqual(session.percent, 42);
    assert.strictEqual(session.severity, "normal");
    assert.strictEqual(session.primary, true);
    assert.strictEqual(session.resetsAt.toISOString(), "2026-08-03T17:10:00.330Z");

    const weekly = out.limits.find(l => l.key === "weekly_all");
    assert.strictEqual(weekly.percent, 88);
    assert.strictEqual(weekly.severity, "warning");
    assert.strictEqual(weekly.primary, true);

    const scoped = out.limits.find(l => l.key === "weekly_scoped:Fable");
    assert.strictEqual(scoped.label, "Fable · semanal");
    assert.strictEqual(scoped.scope, "Fable");
    assert.strictEqual(scoped.primary, false);
});

test("normalizeUsage sobrevive a resets_at invalido y a campos ausentes", () => {
    const payload = { limits: [
        { kind: "session", percent: 5, severity: "normal", resets_at: "no-es-una-fecha" },
        { kind: "weekly_all", severity: "normal", resets_at: null }
    ] };
    const out = Logic.normalizeUsage(payload, "api", new Date("2026-08-03T06:36:00Z"));

    assert.strictEqual(out.limits[0].resetsAt, null);
    assert.strictEqual(out.limits[1].percent, 0);
    assert.strictEqual(out.limits[1].resetsAt, null);
});

test("normalizeUsage devuelve estructura vacia ante un payload nulo", () => {
    const out = Logic.normalizeUsage(null, "api", new Date());
    assert.deepStrictEqual(out.limits, []);
});

test("normalizeUsage cae a five_hour/seven_day cuando limits viene vacio", () => {
    const out = Logic.normalizeUsage(fixture("usage-no-limits.json"), "api", new Date());

    assert.strictEqual(out.limits.length, 2);
    assert.strictEqual(out.limits[0].key, "session");
    assert.strictEqual(out.limits[0].percent, 42);
    assert.strictEqual(out.limits[0].primary, true);
    assert.strictEqual(out.limits[1].key, "weekly_all");
    assert.strictEqual(out.limits[1].percent, 88);
    assert.strictEqual(out.limits[1].resetsAt.toISOString(), "2026-08-04T05:00:00.330Z");
});

test("normalizeUsage marca warning por umbral cuando el fallback no trae severidad", () => {
    const out = Logic.normalizeUsage(fixture("usage-no-limits.json"), "api", new Date());
    assert.strictEqual(out.limits[1].severity, "normal");
    assert.strictEqual(Logic.isWarning(out.limits[1], 90), false);
    assert.strictEqual(Logic.isWarning(out.limits[1], 80), true);
});

test("normalizeUsage lee los creditos desde spend", () => {
    const out = Logic.normalizeUsage(fixture("usage-credits-on.json"), "api", new Date());

    assert.strictEqual(out.extraUsage.enabled, true);
    assert.strictEqual(out.extraUsage.usedMinor, 750);
    assert.strictEqual(out.extraUsage.limitMinor, 3000);
    assert.strictEqual(out.extraUsage.currency, "USD");
    assert.strictEqual(out.extraUsage.exponent, 2);
    assert.strictEqual(out.extraUsage.percent, 25);
});

test("normalizeUsage deriva los creditos de extra_usage si no hay spend", () => {
    const payload = { limits: [], extra_usage: { is_enabled: false, monthly_limit: 3000, used_credits: 2.5, utilization: 8.0, currency: "USD", decimal_places: 2, disabled_reason: "out_of_credits", credits_ever_enabled: true } };
    const out = Logic.normalizeUsage(payload, "api", new Date());

    assert.strictEqual(out.extraUsage.usedMinor, 250);
    assert.strictEqual(out.extraUsage.limitMinor, 3000);
    assert.strictEqual(out.extraUsage.disabledReason, "out_of_credits");
    assert.strictEqual(out.extraUsage.everEnabled, true);
});

test("normalizeUsage devuelve extraUsage null si no hay datos de creditos", () => {
    const out = Logic.normalizeUsage(fixture("usage-no-limits.json"), "api", new Date());
    assert.strictEqual(out.extraUsage, null);
});

function lim(key, percent, severity, primary) {
    return { key: key, label: key, percent: percent, severity: severity, resetsAt: null, scope: null, primary: primary };
}

test("byCriticality ordena por severidad y luego por porcentaje", () => {
    const limits = [
        lim("a", 95, "normal", true),
        lim("b", 10, "warning", true),
        lim("c", 40, "normal", true)
    ];
    const sorted = limits.slice().sort(Logic.byCriticality);
    assert.deepStrictEqual(sorted.map(l => l.key), ["b", "a", "c"]);
});

test("pickPrimary solo considera limites primarios", () => {
    const limits = [
        lim("weekly_scoped:Opus", 99, "critical", false),
        lim("session", 42, "normal", true),
        lim("weekly_all", 88, "warning", true)
    ];
    assert.strictEqual(Logic.pickPrimary(limits).key, "weekly_all");
});

test("pickPrimary devuelve null si no hay primarios", () => {
    assert.strictEqual(Logic.pickPrimary([lim("x", 50, "normal", false)]), null);
    assert.strictEqual(Logic.pickPrimary([]), null);
});

test("hasHiddenWarning detecta un sublimite en aviso fuera del anillo", () => {
    const limits = [
        lim("session", 5, "normal", true),
        lim("weekly_all", 20, "normal", true),
        lim("weekly_scoped:Opus", 95, "normal", false)
    ];
    assert.strictEqual(Logic.hasHiddenWarning(limits, "weekly_all", 90), true);
    assert.strictEqual(Logic.hasHiddenWarning(limits, "weekly_all", 99), false);
});

test("hasHiddenWarning ignora el limite que ya se muestra", () => {
    const limits = [lim("weekly_all", 95, "warning", true)];
    assert.strictEqual(Logic.hasHiddenWarning(limits, "weekly_all", 90), false);
});

test("sortForPopout excluye el primario y ordena el resto", () => {
    const limits = [
        lim("session", 42, "normal", true),
        lim("weekly_all", 88, "warning", true),
        lim("weekly_scoped:Opus", 60, "normal", false)
    ];
    const rest = Logic.sortForPopout(limits, "weekly_all");
    assert.deepStrictEqual(rest.map(l => l.key), ["weekly_scoped:Opus", "session"]);
});

test("formatRelative cubre los cuatro tramos y el vencido", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const at = ms => new Date(now.getTime() + ms);

    assert.strictEqual(Logic.formatRelative(at(34 * 60000), now), "en 34 min");
    assert.strictEqual(Logic.formatRelative(at(60 * 60000), now), "en 1 h");
    assert.strictEqual(Logic.formatRelative(at((10 * 60 + 34) * 60000), now), "en 10 h 34 min");
    assert.strictEqual(Logic.formatRelative(at((52 * 60 + 0) * 60000), now), "en 2 d 4 h");
    assert.strictEqual(Logic.formatRelative(at(48 * 60 * 60000), now), "en 2 d");
    assert.strictEqual(Logic.formatRelative(at(-1000), now), "reiniciando…");
    assert.strictEqual(Logic.formatRelative(null, now), "");
});

test("formatAbsolute distingue hoy, mañana, esta semana y mas alla", () => {
    const now = new Date("2026-08-03T08:00:00+02:00"); // lunes

    assert.strictEqual(Logic.formatAbsolute(new Date("2026-08-03T19:10:00+02:00"), now), "a las 19:10");
    assert.strictEqual(Logic.formatAbsolute(new Date("2026-08-04T07:00:00+02:00"), now), "mañana a las 07:00");
    assert.strictEqual(Logic.formatAbsolute(new Date("2026-08-06T07:00:00+02:00"), now), "el jueves a las 07:00");
    assert.strictEqual(Logic.formatAbsolute(new Date("2026-08-20T07:00:00+02:00"), now), "el 20/8 a las 07:00");
    assert.strictEqual(Logic.formatAbsolute(null, now), "");
});

test("formatMoney convierte unidades menores", () => {
    assert.strictEqual(Logic.formatMoney(0, 2, "USD"), "0,00 $");
    assert.strictEqual(Logic.formatMoney(750, 2, "USD"), "7,50 $");
    assert.strictEqual(Logic.formatMoney(3000, 2, "EUR"), "30,00 €");
    assert.strictEqual(Logic.formatMoney(1234, 2, "GBP"), "12,34 GBP");
});

test("formatMoney cae a 2 decimales con exponent null, undefined o cadena", () => {
    assert.strictEqual(Logic.formatMoney(750, null, "USD"), "7,50 $");
    assert.strictEqual(Logic.formatMoney(750, undefined, "USD"), "7,50 $");
    assert.strictEqual(Logic.formatMoney(750, "2", "USD"), "7,50 $");
});

test("formatMoney cae a 2 decimales con exponent fuera de rango y no lanza", () => {
    assert.doesNotThrow(() => Logic.formatMoney(750, 101, "USD"));
    assert.strictEqual(Logic.formatMoney(750, 101, "USD"), "7,50 $");
    assert.doesNotThrow(() => Logic.formatMoney(750, -1, "USD"));
    assert.strictEqual(Logic.formatMoney(750, -1, "USD"), "7,50 $");
});

test("formatMoney respeta un exponent de 0", () => {
    assert.strictEqual(Logic.formatMoney(3000, 0, "USD"), "3000 $");
});

test("formatAbsolute con fecha pasada devuelve cadena vacia", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    assert.strictEqual(Logic.formatAbsolute(new Date("2026-08-02T07:00:00+02:00"), now), "");
    assert.strictEqual(Logic.formatAbsolute(new Date("2025-08-03T07:00:00+02:00"), now), "");
});

test("formatAbsolute con fecha de hoy mas tarde sigue devolviendo la hora", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    assert.strictEqual(Logic.formatAbsolute(new Date("2026-08-03T23:59:00+02:00"), now), "a las 23:59");
});

function cadence(over) {
    return Object.assign({ warning: false, failures: 0, idleInterval: 300, alertInterval: 60, retryAfter: 0 }, over);
}

test("nextInterval usa reposo y alerta segun el estado", () => {
    assert.strictEqual(Logic.nextInterval(cadence({})), 300);
    assert.strictEqual(Logic.nextInterval(cadence({ warning: true })), 60);
});

test("nextInterval duplica el intervalo por cada fallo, con techo", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ failures: 1 })), 600);
    assert.strictEqual(Logic.nextInterval(cadence({ failures: 2 })), 1200);
    assert.strictEqual(Logic.nextInterval(cadence({ failures: 3 })), 1800);
    assert.strictEqual(Logic.nextInterval(cadence({ failures: 99 })), 1800);
});

test("nextInterval respeta Retry-After por encima de todo, con techo", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ retryAfter: 120, warning: true })), 120);
    assert.strictEqual(Logic.nextInterval(cadence({ retryAfter: 99999 })), 1800);
});

test("nextInterval nunca baja de 15 segundos", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ warning: true, alertInterval: 1 })), 15);
});

test("nextInterval con estado vacio cae a los valores por defecto sin producir NaN", () => {
    assert.strictEqual(Logic.nextInterval({}), 300);
});

test("nextInterval con idleInterval no utilizable cae al valor por defecto de reposo (300), nunca al suelo", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: null })), 300);
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: 0 })), 300);
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: undefined })), 300);
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: "300" })), 300);
});

test("nextInterval con alertInterval no utilizable cae al valor por defecto de alerta (60)", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ warning: true, alertInterval: null })), 60);
});

test("nextInterval con retryAfter no numerico cae al camino normal", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT" })), 300);
});

test("nextInterval da precedencia a retryAfter sobre el backoff por fallos", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ retryAfter: 120, failures: 5 })), 120);
});

test("nextInterval aplica el suelo tambien a retryAfter", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ retryAfter: 5 })), 15);
});

test("nextInterval mantiene el comportamiento ya correcto en casos limite", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ failures: 1024 })), 1800);
    assert.strictEqual(Logic.nextInterval(cadence({ failures: -5 })), 300);
    assert.strictEqual(Logic.nextInterval(cadence({ retryAfter: -10 })), 300);
});

// Task 9b: MAX_INTERVAL (1800) acota el crecimiento del backoff, no la
// eleccion del usuario. Spec §8: idleInterval admite 60-3600.
test("nextInterval honra el idleInterval del usuario por encima de 1800 sin fallos", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: 3600 })), 3600);
});

test("nextInterval honra el alertInterval del usuario por encima de 1800 sin fallos", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ warning: true, alertInterval: 3600 })), 3600);
});

test("nextInterval duplica una base normal con fallos, acotado por MAX_INTERVAL (spec §6)", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: 300, failures: 1 })), 600);
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: 300, failures: 3 })), 1800);
});

test("nextInterval con fallos nunca sondea mas rapido que la base (backoff, no aceleracion)", () => {
    var result = Logic.nextInterval(cadence({ idleInterval: 3600, failures: 2 }));
    assert.ok(result >= 3600, "el backoff no debe bajar de la base: " + result);
    assert.strictEqual(result, 3600);
});

test("nextInterval en alerta tambien respeta el suelo de base con fallos", () => {
    var result = Logic.nextInterval(cadence({ warning: true, alertInterval: 3600, failures: 2 }));
    assert.strictEqual(result, 3600);
});

test("nextInterval con idleInterval basura cae a Logic.DEFAULT_IDLE_INTERVAL, nunca produce NaN", () => {
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: null })), Logic.DEFAULT_IDLE_INTERVAL);
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: undefined })), Logic.DEFAULT_IDLE_INTERVAL);
    assert.strictEqual(Logic.nextInterval(cadence({ idleInterval: "300" })), Logic.DEFAULT_IDLE_INTERVAL);
    assert.strictEqual(Logic.DEFAULT_IDLE_INTERVAL, 300);
    assert.ok(!isNaN(Logic.nextInterval(cadence({ idleInterval: null }))));
});

test("parseCredentials acepta un token vigente", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    const text = JSON.stringify({ claudeAiOauth: { accessToken: "sk-ant-oat01-xxx", expiresAt: now.getTime() + 3600000 } });
    const out = Logic.parseCredentials(text, now);

    assert.strictEqual(out.status, "ok");
    assert.strictEqual(out.token, "sk-ant-oat01-xxx");
});

test("parseCredentials marca caducado con margen de 60 s", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    const almost = JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: now.getTime() + 30000 } });

    assert.strictEqual(Logic.parseCredentials(almost, now).status, "expired");
    assert.strictEqual(Logic.parseCredentials(almost, now).token, null);
});

test("parseCredentials rechaza entradas malformadas sin lanzar", () => {
    const now = new Date();
    assert.strictEqual(Logic.parseCredentials("", now).status, "invalid");
    assert.strictEqual(Logic.parseCredentials("{no json", now).status, "invalid");
    assert.strictEqual(Logic.parseCredentials("{}", now).status, "invalid");
    assert.strictEqual(Logic.parseCredentials(JSON.stringify({ claudeAiOauth: {} }), now).status, "invalid");
    assert.strictEqual(Logic.parseCredentials(null, now).status, "invalid");
});

test("extractCache devuelve payload y fecha de captura", () => {
    const text = JSON.stringify({ cachedUsageUtilization: { fetchedAtMs: 1785417486544, utilization: { limits: [] } } });
    const out = Logic.extractCache(text);

    assert.strictEqual(out.fetchedAt.getTime(), 1785417486544);
    assert.deepStrictEqual(out.payload.limits, []);
});

test("extractCache devuelve null ante datos ausentes o corruptos", () => {
    assert.strictEqual(Logic.extractCache("{no json"), null);
    assert.strictEqual(Logic.extractCache("{}"), null);
    assert.strictEqual(Logic.extractCache(JSON.stringify({ cachedUsageUtilization: {} })), null);
});

// --- Ronda de correccion 1: S1/C1/C2 — fallar cerrado ante entrada corrupta ---

test("parseCredentials falla cerrado con expiresAt no numerico o corrupto", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    const cases = [
        JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: "manana" } }),
        JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: {} } }),
        JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: NaN } }),
        JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: Infinity } }),
        JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: "1785747600000" } })
    ];

    cases.forEach(text => {
        const out = Logic.parseCredentials(text, now);
        assert.strictEqual(out.status, "invalid");
        assert.strictEqual(out.token, null);
    });
});

test("parseCredentials falla cerrado con accessToken no valido", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    const expiresAt = now.getTime() + 3600000;
    const cases = [
        JSON.stringify({ claudeAiOauth: { accessToken: 12345, expiresAt } }),
        JSON.stringify({ claudeAiOauth: { accessToken: { a: 1 }, expiresAt } }),
        JSON.stringify({ claudeAiOauth: { accessToken: "", expiresAt } })
    ];

    cases.forEach(text => {
        const out = Logic.parseCredentials(text, now);
        assert.strictEqual(out.status, "invalid");
        assert.strictEqual(out.token, null);
    });
});

test("parseCredentials mantiene los caminos correctos tras el endurecimiento", () => {
    const now = new Date("2026-08-03T08:00:00Z");

    const ok = JSON.stringify({ claudeAiOauth: { accessToken: "sk-ant-oat01-xxx", expiresAt: now.getTime() + 3600000 } });
    const okOut = Logic.parseCredentials(ok, now);
    assert.strictEqual(okOut.status, "ok");
    assert.strictEqual(okOut.token, "sk-ant-oat01-xxx");

    const almost = JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: now.getTime() + 30000 } });
    const almostOut = Logic.parseCredentials(almost, now);
    assert.strictEqual(almostOut.status, "expired");
    assert.strictEqual(almostOut.token, null);

    const zero = JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: 0 } });
    assert.strictEqual(Logic.parseCredentials(zero, now).status, "invalid");

    const negative = JSON.stringify({ claudeAiOauth: { accessToken: "t", expiresAt: -1 } });
    assert.strictEqual(Logic.parseCredentials(negative, now).status, "expired");
});

test("extractCache falla cerrado con fetchedAtMs no numerico o corrupto", () => {
    const cases = [
        JSON.stringify({ cachedUsageUtilization: { fetchedAtMs: "1785417486544", utilization: { limits: [] } } }),
        JSON.stringify({ cachedUsageUtilization: { fetchedAtMs: NaN, utilization: { limits: [] } } }),
        JSON.stringify({ cachedUsageUtilization: { fetchedAtMs: {}, utilization: { limits: [] } } })
    ];

    cases.forEach(text => {
        assert.strictEqual(Logic.extractCache(text), null);
    });
});

test("extractCache mantiene los caminos correctos tras el endurecimiento", () => {
    assert.strictEqual(Logic.extractCache(JSON.stringify({ cachedUsageUtilization: { fetchedAtMs: 0, utilization: { limits: [] } } })), null);

    const text = JSON.stringify({ cachedUsageUtilization: { fetchedAtMs: 1785417486544, utilization: { limits: [] } } });
    const out = Logic.extractCache(text);
    assert.strictEqual(out.fetchedAt.getTime(), 1785417486544);
    assert.deepStrictEqual(out.payload.limits, []);
});

function warnLimit(key, label, percent, resetsAt) {
    return { key: key, label: label, percent: percent, severity: "normal", resetsAt: resetsAt, scope: null, primary: true };
}

test("notificationsFor avisa la primera vez que se cruza el umbral", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const resets = new Date("2026-08-04T07:00:00+02:00");
    const out = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 91, resets)], 90, {}, now);

    assert.strictEqual(out.notifications.length, 1);
    assert.strictEqual(out.notifications[0].summary, "Claude");
    assert.strictEqual(out.notifications[0].body, "91 % de Semana consumido · se reinicia mañana a las 07:00");
    assert.strictEqual(out.nextState["weekly_all"].notified, true);
});

test("notificationsFor no repite dentro de la misma ventana", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const resets = new Date("2026-08-04T07:00:00+02:00");
    const first = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 91, resets)], 90, {}, now);
    const second = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 95, resets)], 90, first.nextState, now);

    assert.strictEqual(second.notifications.length, 0);
});

test("notificationsFor rearma cuando cambia resets_at", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const week1 = new Date("2026-08-04T07:00:00+02:00");
    const week2 = new Date("2026-08-11T07:00:00+02:00");
    const first = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 91, week1)], 90, {}, now);
    const second = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 91, week2)], 90, first.nextState, now);

    assert.strictEqual(second.notifications.length, 1);
});

test("notificationsFor cubre tambien los sublimites por modelo", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const resets = new Date("2026-08-04T07:00:00+02:00");
    const scoped = { key: "weekly_scoped:Opus", label: "Opus · semanal", percent: 95, severity: "normal", resetsAt: resets, scope: "Opus", primary: false };
    const out = Logic.notificationsFor([scoped], 90, {}, now);

    assert.strictEqual(out.notifications.length, 1);
    assert.ok(out.notifications[0].body.indexOf("Opus · semanal") !== -1);
});

test("notificationsFor no avisa por debajo del umbral y poda estado obsoleto", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const prev = { "limite_que_ya_no_existe": { resetsAt: null, notified: true } };
    const out = Logic.notificationsFor([warnLimit("session", "Sesión 5 h", 10, null)], 90, prev, now);

    assert.strictEqual(out.notifications.length, 0);
    assert.strictEqual(out.nextState["limite_que_ya_no_existe"], undefined);
});

test("notificationsFor falla cerrado cuando limits no es un array", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    [null, undefined, "no-array", 42, {}].forEach(badLimits => {
        const out = Logic.notificationsFor(badLimits, 90, {}, now);
        assert.deepStrictEqual(out, { notifications: [], nextState: {} });
    });
});

test("notificationsFor cae al umbral por defecto (90) si threshold no es finito, y no al suelo del rango", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");

    // Un 89% no debe avisar nunca con el umbral por defecto (90). Si el
    // fallback cayera al suelo del rango (p. ej. 0 o el mínimo de intervalo)
    // en vez del valor por defecto del spec, esto avisaría por error.
    [NaN, "noventa", undefined, null, {}].forEach(badThreshold => {
        const below = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 89, null)], badThreshold, {}, now);
        assert.strictEqual(below.notifications.length, 0);
    });

    // Un 91% sí debe avisar con el umbral por defecto (90) aplicado.
    const above = Logic.notificationsFor([warnLimit("weekly_all", "Semana", 91, null)], "noventa", {}, now);
    assert.strictEqual(above.notifications.length, 1);
});

test("notificationsFor trata un prevState que no es objeto como estado vacio", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const resets = new Date("2026-08-04T07:00:00+02:00");
    const limit = warnLimit("weekly_all", "Semana", 91, resets);

    [null, undefined, "corrupt", 42].forEach(badPrev => {
        const out = Logic.notificationsFor([limit], 90, badPrev, now);
        assert.strictEqual(out.notifications.length, 1);
    });
});

test("notificationsFor omite la clausula de reinicio si now no es una fecha valida", () => {
    const resets = new Date("2026-08-04T07:00:00+02:00");
    const limit = warnLimit("weekly_all", "Semana", 91, resets);
    const out = Logic.notificationsFor([limit], 90, {}, new Date("not-a-date"));

    assert.strictEqual(out.notifications.length, 1);
    assert.strictEqual(out.notifications[0].body, "91 % de Semana consumido");
    assert.strictEqual(out.notifications[0].body.indexOf("Invalid"), -1);
});

test("notificationsFor no lanza y guarda resetsAt null si el limite trae una fecha invalida", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const limit = warnLimit("weekly_all", "Semana", 91, new Date("not-a-date"));

    assert.doesNotThrow(() => {
        const out = Logic.notificationsFor([limit], 90, {}, now);
        assert.strictEqual(out.notifications.length, 1);
        assert.strictEqual(out.notifications[0].body, "91 % de Semana consumido");
        assert.strictEqual(out.nextState["weekly_all"].resetsAt, null);
    });
});

test("notificationsFor omite la clausula de reinicio si el reset ya paso", () => {
    const now = new Date("2026-08-03T08:00:00+02:00");
    const past = new Date("2026-08-02T07:00:00+02:00");
    const limit = warnLimit("weekly_all", "Semana", 91, past);
    const out = Logic.notificationsFor([limit], 90, {}, now);

    assert.strictEqual(out.notifications.length, 1);
    assert.strictEqual(out.notifications[0].body, "91 % de Semana consumido");
});

test("parseRetryAfter interpreta la forma delta-seconds", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    assert.strictEqual(Logic.parseRetryAfter("120", now), 120);
    assert.strictEqual(Logic.parseRetryAfter("0", now), 0);
});

test("parseRetryAfter tolera espacios alrededor de delta-seconds", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    assert.strictEqual(Logic.parseRetryAfter(" 30 ", now), 30);
});

test("parseRetryAfter interpreta la forma de fecha HTTP (RFC 7231) en vez de devolver NaN||0", () => {
    const now = new Date("2015-10-21T07:26:00Z");
    const header = "Wed, 21 Oct 2015 07:28:00 GMT";
    // parseInt(header, 10) da NaN aqui; el fallback ingenuo `|| 0` ignoraria
    // los 120 s que el servidor pidio esperar tras un 429.
    assert.strictEqual(Logic.parseRetryAfter(header, now), 120);
});

test("parseRetryAfter cae a 0 si la fecha HTTP ya paso, nunca a un reintento inmediato negativo", () => {
    const now = new Date("2015-10-21T07:30:00Z");
    const header = "Wed, 21 Oct 2015 07:28:00 GMT";
    assert.strictEqual(Logic.parseRetryAfter(header, now), 0);
});

test("parseRetryAfter cae a 0 ante una cabecera que no es ninguna de las dos formas", () => {
    const now = new Date("2026-08-03T08:00:00Z");
    ["", "no-es-un-numero-ni-una-fecha", "-5", "120.5", null, undefined, 120].forEach(bad => {
        assert.strictEqual(Logic.parseRetryAfter(bad, now), 0);
    });
});

test("parseRetryAfter cae a 0 si el reloj (now) no es una fecha valida", () => {
    assert.strictEqual(Logic.parseRetryAfter("120", new Date("not-a-date")), 0);
    assert.strictEqual(Logic.parseRetryAfter("120", null), 0);
});

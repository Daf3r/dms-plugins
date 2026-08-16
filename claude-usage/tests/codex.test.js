"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");
var fs = require("node:fs");
var path = require("node:path");

var Logic = require("../logic.js");

var fixture = JSON.parse(fs.readFileSync(
    path.join(__dirname, "fixtures", "codex-usage.json"), "utf8"));

var NOW = 1787000000000;

describe("Codex / credenciales", function () {
    test("extrae el access token y el account id sin modificar la forma", function () {
        var r = Logic.parseCodexCredentials({
            auth_mode: "chatgpt",
            tokens: { access_token: "token-fixture", account_id: "account-fixture" }
        });
        assert.deepEqual(r, {
            status: "ok",
            token: "token-fixture",
            accountId: "account-fixture"
        });
    });

    test("permite token sin account id", function () {
        var r = Logic.parseCodexCredentials({
            tokens: { access_token: "token-fixture" }
        });
        assert.equal(r.status, "ok");
        assert.equal(r.accountId, null);
    });

    test("API key, token vacío y formas corruptas fallan cerrado", function () {
        [
            { auth_mode: "apikey", OPENAI_API_KEY: "not-used" },
            { tokens: { access_token: "" } },
            { tokens: { access_token: 123 } },
            { tokens: {} },
            null,
            "not-json-object"
        ].forEach(function (doc) {
            var r = Logic.parseCodexCredentials(doc);
            assert.equal(r.status, "invalid");
            assert.equal(r.token, null);
            assert.equal(r.accountId, null);
        });
    });
});

describe("Codex / normalización", function () {
    test("normaliza ventanas base y adicionales", function () {
        var model = Logic.normalizeCodexUsage(fixture, "api", NOW);
        assert.equal(model.source, "api");
        assert.equal(model.fetchedAt, NOW);
        assert.equal(model.planType, "pro");
        assert.equal(model.limits.length, 3);

        var primary = Logic.pickCodexPrimary(model.limits);
        var secondary = Logic.pickCodexSecondary(model.limits);
        assert.equal(primary.key, "codex:primary");
        assert.equal(primary.percent, 13);
        assert.equal(primary.resetsAt, 1790000000000);
        assert.equal(primary.label.key, "limit.codexWindow");
        assert.equal(primary.label.params.duration, "7 d");
        assert.equal(primary.glyph, "code");
        assert.equal(secondary.percent, 42);
        assert.equal(secondary.label.params.duration, "5 h");

        var rest = Logic.sortCodexForPanel(model.limits, primary.key, secondary.key);
        assert.equal(rest.length, 1);
        assert.equal(rest[0].scope, "Spark");
        assert.equal(rest[0].severity, "critical");
        assert.equal(rest[0].percent, 100);
    });

    test("conserva créditos y detecta avisos que no caben en la barra", function () {
        var model = Logic.normalizeCodexUsage(fixture, "api", NOW);
        assert.deepEqual(model.credits, {
            hasCredits: true,
            unlimited: false,
            balance: "12.50"
        });
        var primary = Logic.pickCodexPrimary(model.limits);
        var secondary = Logic.pickCodexSecondary(model.limits);
        assert.equal(Logic.hasCodexHiddenWarning(
            model.limits, primary.key, secondary.key, 90), true);
        assert.equal(Logic.hasCodexWarning(model.limits, 90), true);
    });

    test("respuestas sin rate limits son válidas pero no inventan datos", function () {
        var model = Logic.normalizeCodexUsage({
            plan_type: "free",
            rate_limit: null,
            additional_rate_limits: [],
            credits: null
        }, "api", NOW);
        assert.deepEqual(model.limits, []);
        assert.equal(Logic.pickCodexPrimary(model.limits), null);
        assert.equal(Logic.pickCodexSecondary(model.limits), null);
        assert.equal(Logic.sortCodexForPanel(model.limits, null, null).length, 0);
        assert.equal(Logic.hasCodexWarning(model.limits, 90), false);
    });

    test("reset y ventana inválidos no producen milisegundos o etiquetas falsas", function () {
        assert.equal(Logic.codexResetMs(null), null);
        assert.equal(Logic.codexResetMs("ayer"), null);
        assert.equal(Logic.codexResetMs(0), null);
        assert.equal(Logic.codexWindowDuration(null), null);
        assert.equal(Logic.codexWindowDuration(-1), null);
        assert.equal(Logic.codexLabelDescriptor("Spark", null).key, "limit.codexNamed");
    });
});

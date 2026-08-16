"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");
var fs = require("node:fs");
var path = require("node:path");

var PLUGIN_DIR = path.resolve(__dirname, "..");
var DAEMON = fs.readFileSync(path.join(PLUGIN_DIR, "Daemon.qml"), "utf8");
var WIDGET = fs.readFileSync(path.join(PLUGIN_DIR, "Widget.qml"), "utf8");

describe("Codex / contrato QML", function () {
    test("el daemon usa la ruta de auth y el endpoint del CLI", function () {
        assert.match(DAEMON, /codexEndpoint:\s*"https:\/\/chatgpt\.com\/backend-api\/wham\/usage"/);
        assert.match(DAEMON, /codexAuthPath:\s*"~\/\.codex\/auth\.json"/);
        assert.match(DAEMON, /const parsedAuth = Logic\.safeParse\(authText\)/);
        assert.match(DAEMON, /Logic\.parseCodexCredentials\(parsedAuth\)/);
        assert.match(DAEMON, /setRequestHeader\("Authorization", "Bearer " \+ token\)/);
        assert.match(DAEMON, /setRequestHeader\("ChatGPT-Account-Id", accountId\)/);
    });

    test("los dos caminos de publish publican el bloque Codex", function () {
        var publications = DAEMON.match(/codex:\s*codex/g) || [];
        assert.equal(publications.length, 2);
        assert.match(DAEMON, /function decorateCodexState\(/);
        assert.match(DAEMON, /function pollCodex\(/);
        assert.match(DAEMON, /function handleCodexResponse\(/);
    });

    test("Claude y Codex comparten ciclo, pero tienen estados y fallos separados", function () {
        assert.match(DAEMON, /property int failures: 0/);
        assert.match(DAEMON, /property int codexFailures: 0/);
        assert.match(DAEMON, /property string codexStatus: "loading"/);
        assert.match(DAEMON, /if \(!root\.codexStarted && skipCodex !== true\)/);
        assert.match(DAEMON, /root\.pollCodex\(\);/);
    });

    test("FileView entrega el contenido antes de destruirse", function () {
        var loaded = DAEMON.match(/onLoaded:\s*\{([\s\S]*?)\n            \}/);
        assert.ok(loaded, "onLoaded debe existir");
        assert.ok(loaded[1].indexOf("callback(") < loaded[1].indexOf("view.destroy()"));
    });

    test("el widget solo pinta Codex desde usage.codex", function () {
        assert.match(WIDGET, /readonly property var codex: usage \? usage\.codex : null/);
        assert.match(WIDGET, /readonly property var codexPrimary: codex \? codex\.primary : null/);
        assert.match(WIDGET, /limit: root\.hasCodexNumber \? root\.codexPrimary : null/);
        assert.match(WIDGET, /model: root\.codexPanelLimits/);
        assert.match(WIDGET, /visible: root\.hasCodexData/);
    });
});

// Traducción de tests/smoke.test.luau. Un solo caso, y su valor está en lo
// que rompe: si logic.js deja de cargarse en node (una sintaxis que el motor
// de QML acepta y node no, un module.exports mal cerrado), este es el primer
// fichero que lo dice, sin arrastrar el ruido de otras cien afirmaciones.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");

describe("arnés", function () {
    test("logic.js se puede importar y expone SEVERITY_RANK", function () {
        assert.equal(Logic.SEVERITY_RANK.critical, 2);
    });
});

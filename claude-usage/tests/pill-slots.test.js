// Las DOS ranuras de la píldora de barra.
//
// Fichero NUEVO, no es traducción de ningún .luau: cubre una regla que no
// existía en Noctalia, donde la píldora enseñaba una sola ventana.
//
// La regla: las dos ranuras son los dos límites primarios de
// `Logic.PRIMARY_KINDS` —`session` y `weekly_all`—, en ese orden. La versión
// anterior ponía en la segunda `others[0]`, o sea «el más crítico de los
// demás», y eso tiene un fallo que solo se ve con el tiempo: en cuanto un
// sublímite por modelo entra en aviso con la semanal tranquila, el orden por
// criticidad lo pone delante y la semanal desaparece de la barra en el mismo
// sitio y con la misma pinta. El caso "la semanal no se cede a un sublímite"
// de aquí abajo es exactamente ese, y falla con el código viejo.
//
// POR QUÉ SE EVALÚA `pickWeekly` SACÁNDOLA DE Daemon.qml: la selección vive en
// el daemon, que es QML y no se puede importar desde node. Copiar la función
// aquí probaría la copia y no lo que se envía. Así que se extrae del fichero
// real y se evalúa: es JavaScript puro —no toca ninguna API del host— y si
// alguien la reescribiese usando algo de QML, este test se caería en la
// extracción con un mensaje explícito, que es la señal correcta.
//
// Sobre el `new Function` de abajo: lo que se evalúa es un fichero del propio
// repo, versionado y revisado, dentro del runner de pruebas. No hay entrada de
// usuario en ningún punto de la cadena, y el código de producción no evalúa
// absolutamente nada — ni el daemon ni el widget.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var fs = require("node:fs");
var path = require("node:path");

var Logic = require("../logic.js");

var DAEMON_QML = path.resolve(__dirname, "..", "Daemon.qml");
var WIDGET_QML = path.resolve(__dirname, "..", "Widget.qml");

var DAEMON_SRC = fs.readFileSync(DAEMON_QML, "utf8");
var WIDGET_SRC = fs.readFileSync(WIDGET_QML, "utf8");

// Los comentarios de estos ficheros EXPLICAN la alternativa descartada, así que
// nombran `others[0]` a propósito. Un barrido que los mirase daría un falso
// positivo justo por estar bien documentado el cambio: se miran solo las
// líneas de código.
function stripComments(source) {
    return source.replace(/\/\*[\s\S]*?\*\//g, "").split("\n").map(function (line) {
        var at = line.indexOf("//");
        return at === -1 ? line : line.slice(0, at);
    }).join("\n");
}

// Extrae una declaración `function <nombre>(…) { … }` contando llaves.
function extractFunction(source, name) {
    var start = source.indexOf("function " + name + "(");
    assert.notEqual(start, -1, 'Daemon.qml ya no declara "function ' + name + '("');
    var open = source.indexOf("{", start);
    assert.notEqual(open, -1, "no se encontró el cuerpo de " + name);
    var depth = 0;
    for (var i = open; i < source.length; i++) {
        if (source[i] === "{") depth += 1;
        else if (source[i] === "}") {
            depth -= 1;
            if (depth === 0) return source.slice(start, i + 1);
        }
    }
    assert.fail("llaves sin cerrar en " + name);
}

var pickWeekly = (function () {
    var src = extractFunction(DAEMON_SRC, "pickWeekly");
    var fn;
    try {
        fn = new Function("return (" + src + ");")();
    } catch (e) {
        assert.fail("pickWeekly de Daemon.qml ya no es JavaScript puro evaluable: " + e);
    }
    assert.equal(typeof fn, "function");
    return fn;
})();

// Lo que el daemon hace en publish(): elige la primaria y luego la semanal.
function slots(limits) {
    var primary = Logic.pickPrimary(limits);
    var primaryKey = primary ? primary.key : null;
    return {
        first: primary,
        second: pickWeekly(limits, primaryKey)
    };
}

function limitsOf(payload) {
    return Logic.normalizeUsage(payload, "api", 0).limits;
}

function windowLimit(kind, percent, severity, modelName) {
    var item = {
        kind: kind,
        percent: percent,
        severity: severity || "normal",
        resets_at: "2026-08-11T05:00:00Z",
        scope: null
    };
    if (modelName)
        item.scope = { model: { display_name: modelName } };
    return item;
}

describe("píldora / las dos ranuras", function () {
    test("la primera es la sesión y la segunda la semanal", function () {
        var s = slots(limitsOf(require("./fixtures/usage-normal.json")));
        assert.equal(s.first.key, "session");
        assert.ok(s.second, "no hay segunda ranura");
        assert.equal(s.second.key, "weekly_all");
    });

    // El caso que motivó fijar la ranura. Con `others[0]` la segunda ranura
    // sería el sublímite de Fable —va delante por severidad— y la semanal, que
    // es el número que decide la semana, se caería de la barra sin señal.
    test("la semanal NO se cede a un sublímite por modelo más crítico", function () {
        var limits = limitsOf({
            limits: [
                windowLimit("session", 44),
                windowLimit("weekly_all", 84),
                windowLimit("weekly_scoped", 61, "warning", "Fable")
            ]
        });
        var s = slots(limits);

        // Primero, que el escenario es real: por criticidad el sublímite gana.
        var others = Logic.sortForPanel(limits, s.first.key);
        assert.equal(others[0].key, "weekly_scoped:Fable",
                     "el escenario ya no reproduce el fallo: others[0] no es el sublímite");

        // Y aun así la segunda ranura es la semanal.
        assert.equal(s.second.key, "weekly_all");
        assert.equal(s.second.percent, 84);

        // El sublímite no se pierde: lo delata el glifo pequeño.
        assert.equal(Logic.hasHiddenWarning(limits, s.first.key, 90), true);
    });

    // Caso de ausencia: sin ventana semanal la píldora es de una sola ranura.
    // usage-credits-on.json trae `limits` con la sesión y nada más.
    test("sin ventana semanal la segunda ranura viene null", function () {
        var limits = limitsOf(require("./fixtures/usage-credits-on.json"));
        assert.equal(limits.length, 1);
        assert.equal(limits[0].key, "session");

        var s = slots(limits);
        assert.equal(s.first.key, "session");
        assert.equal(s.second, null, "debería no haber segunda ranura");
    });

    // Sin sesión, `pickPrimary` devuelve la semanal: si además se publicase en
    // la segunda ranura, la misma ventana saldría dos veces en la barra.
    test("si la semanal ya es la primaria, no se repite en la segunda", function () {
        var limits = limitsOf({
            limits: [windowLimit("weekly_all", 84)]
        });
        var s = slots(limits);
        assert.equal(s.first.key, "weekly_all");
        assert.equal(s.second, null, "la semanal se estaría pintando dos veces");
    });

    test("sin límites no hay ni primera ni segunda", function () {
        var s = slots([]);
        assert.equal(s.first, null);
        assert.equal(s.second, null);
    });
});

describe("píldora / el contrato entre daemon y widget", function () {
    // El campo tiene que publicarse en LAS DOS ramas de publish(): la que
    // tiene modelo y la que no. Si faltara en la rama sin modelo, el widget
    // leería `undefined` donde espera `null` y la distinción «clave ausente»
    // frente a «sin valor» volvería a existir, que es lo que la tarea 8 quitó.
    test("Daemon.qml publica `weekly` en las dos ramas de publish()", function () {
        var publishes = stripComments(DAEMON_SRC).match(/\bweekly:/g) || [];
        assert.ok(publishes.length >= 2,
                  "solo " + publishes.length + " apariciones de `weekly:` en Daemon.qml, se esperaban 2");
    });

    // La red anti-regresión del fallo concreto: que nadie reponga el respaldo
    // a `others[0]` en el widget «por si acaso no hay semanal».
    test("Widget.qml lee `usage.weekly` y no `others[0]`", function () {
        var code = stripComments(WIDGET_SRC);
        assert.match(code, /usage\.weekly/,
                     "Widget.qml ya no lee usage.weekly");
        assert.equal(/others\s*\[\s*0\s*\]/.test(code), false,
                     "Widget.qml ha vuelto a caer a others[0] para la segunda ranura");
    });
});

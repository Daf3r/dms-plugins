// Traducción caso por caso de tests/ordering.test.luau, que es la
// ESPECIFICACIÓN del orden y del aviso: mismos casos, mismos valores, mismos
// nombres. No se añade, no se quita, no se "mejora".
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · byCriticality cambia de forma, no de intención. En Luau es un PREDICADO
//     ("¿va `a` antes que `b`?") porque eso es lo que espera table.sort; en
//     JavaScript, Array.prototype.sort espera un COMPARADOR que devuelve un
//     número negativo, cero o positivo. Cada `h.eq(Logic.byCriticality(a, b),
//     true)` se traduce por el SIGNO con el helper `before()`, y el caso
//     irreflexivo `comp(x, x) == false` se traduce por `comp(x, x) === 0`, que
//     es lo mismo dicho en la convención del comparador.
//   · los índices van de 0 en adelante: `list[1]` del original es `list[0]`
//     aquí y `list[4]` es `list[3]`; `rest[1]`/`rest[2]` son `rest[0]`/`rest[1]`.
//   · `h.nilish(x)` se convierte en `assert.equal(x, null)` — ver la nota de
//     logic.js sobre por qué la ausencia es null y nunca undefined.
//   · `nil` como `primaryKey` viaja como `null`.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");

function limit(key, percent, severity, primary) {
    return { key: key, label: key, percent: percent, severity: severity,
             resetsAt: null, scope: null, primary: primary };
}

// "¿va `a` antes que `b`?" — la pregunta que hacía el predicado de Luau,
// respondida ahora por el signo del comparador.
function before(a, b) {
    return Logic.byCriticality(a, b) < 0;
}

describe("isWarning", function () {
    test("por severidad, aunque el porcentaje sea bajo", function () {
        assert.equal(Logic.isWarning(limit("a", 3, "warning", true), 90), true);
    });
    test("por umbral, aunque la severidad sea normal", function () {
        assert.equal(Logic.isWarning(limit("a", 90, "normal", true), 90), true);
        assert.equal(Logic.isWarning(limit("a", 89, "normal", true), 90), false);
    });
    test("null no es aviso y no lanza", function () {
        assert.equal(Logic.isWarning(null, 90), false);
    });
});

describe("byCriticality", function () {
    test("la severidad manda sobre el porcentaje", function () {
        var a = limit("a", 10, "critical", true);
        var b = limit("b", 99, "normal", true);
        assert.equal(before(a, b), true);
        assert.equal(before(b, a), false);
    });
    test("a igual severidad, mayor porcentaje primero", function () {
        var a = limit("a", 80, "normal", true);
        var b = limit("b", 20, "normal", true);
        assert.equal(before(a, b), true);
    });
    // EL CASO QUE EL ORIGINAL NO TENÍA
    test("empate total desempata por key, de forma determinista", function () {
        var a = limit("aaa", 50, "normal", true);
        var b = limit("bbb", 50, "normal", true);
        assert.equal(before(a, b), true);
        assert.equal(before(b, a), false);
        // Irreflexivo: en Luau table.sort lanza si comp(x, x) es true; en la
        // convención del comparador, eso es devolver exactamente 0.
        assert.equal(Logic.byCriticality(a, a), 0);
    });
    test("ordenar una lista con empates totales no lanza y es estable", function () {
        var list = [
            limit("ccc", 50, "normal", true), limit("aaa", 50, "normal", true),
            limit("bbb", 50, "normal", true), limit("ddd", 50, "normal", true)
        ];
        list.sort(Logic.byCriticality);
        assert.equal(list[0].key, "aaa");
        assert.equal(list[3].key, "ddd");
    });
});

describe("pickPrimary", function () {
    // La sesión gana aunque la semanal vaya más alta Y más grave: es la ventana
    // que se recupera esperando, y por eso es la que vive en la barra.
    test("la sesión de 5 h manda sobre la semanal", function () {
        var limits = [
            limit("weekly_scoped:Opus", 99, "critical", false),
            limit("session", 42, "normal", true),
            limit("weekly_all", 88, "warning", true)
        ];
        assert.equal(Logic.pickPrimary(limits).key, "session");
    });
    // Si la API deja de mandar la ventana de sesión, se cae al primario más
    // grave; el sublímite por modelo sigue sin competir, que es lo de siempre.
    test("sin sesión, cae al primario más grave", function () {
        var limits = [
            limit("weekly_scoped:Opus", 99, "critical", false),
            limit("weekly_all", 88, "warning", true)
        ];
        assert.equal(Logic.pickPrimary(limits).key, "weekly_all");
    });
    // Con la sesión fija en la barra, el punto de aviso es la única señal de una
    // semanal en rojo. Si esto se rompe, la semanal se vuelve invisible.
    test("una semanal en aviso deja punto aunque la primaria sea la sesión", function () {
        var limits = [
            limit("session", 10, "normal", true),
            limit("weekly_all", 95, "warning", true)
        ];
        var primary = Logic.pickPrimary(limits);
        assert.equal(primary.key, "session");
        assert.equal(Logic.hasHiddenWarning(limits, primary.key, 90), true);
    });
    test("sin primarios devuelve null", function () {
        assert.equal(Logic.pickPrimary([limit("x", 99, "critical", false)]), null);
    });
    test("lista vacía devuelve null", function () {
        assert.equal(Logic.pickPrimary([]), null);
    });
    test("no muta el array de entrada", function () {
        var limits = [limit("session", 10, "normal", true),
                      limit("weekly_all", 90, "normal", true)];
        Logic.pickPrimary(limits);
        assert.equal(limits[0].key, "session");
    });
});

describe("sortForPanel", function () {
    test("excluye el primario y ordena el resto", function () {
        var limits = [
            limit("session", 42, "normal", true),
            limit("weekly_all", 88, "warning", true),
            limit("weekly_scoped:Opus", 60, "normal", false)
        ];
        var rest = Logic.sortForPanel(limits, "weekly_all");
        assert.equal(rest.length, 2);
        assert.equal(rest[0].key, "weekly_scoped:Opus");
        assert.equal(rest[1].key, "session");
    });
    test("primaryKey null devuelve todos", function () {
        assert.equal(Logic.sortForPanel([limit("a", 1, "normal", true)], null).length, 1);
    });
});

describe("hasHiddenWarning", function () {
    test("detecta un sublímite en aviso fuera del primario", function () {
        var limits = [
            limit("weekly_all", 10, "normal", true),
            limit("weekly_scoped:Opus", 95, "normal", false)
        ];
        assert.equal(Logic.hasHiddenWarning(limits, "weekly_all", 90), true);
    });
    test("ignora el propio primario", function () {
        var limits = [limit("weekly_all", 95, "normal", true)];
        assert.equal(Logic.hasHiddenWarning(limits, "weekly_all", 90), false);
    });
});

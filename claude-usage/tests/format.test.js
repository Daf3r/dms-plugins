// Traducción caso por caso de tests/format.test.luau, que es la
// ESPECIFICACIÓN de los helpers de formato: mismos casos, mismos valores,
// mismos nombres. No se añade, no se quita, no se "mejora".
//
// Diferencias inevitables respecto del original en Luau, todas mecánicas:
//   · el catálogo se carga del .json de origen (require) en vez de la
//     fixture generada tests/translations.fixture.luau;
//   · el ancla local se construye con `new Date(y, mo - 1, ...)`, que ya
//     interpreta hora LOCAL — en Luau hacía falta h.localMs porque os.time
//     interpreta su tabla en UTC;
//   · `nil` se convierte en `null` (ver la nota de logic.js sobre por qué
//     la ausencia es null y no undefined en todo el módulo).
//
// La TZ la fija tests/run-js.fish (Europe/Madrid). Sin ella, describeAbsolute
// no es determinista y el primer test de "entorno" lo delata.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var Logic = require("../logic.js");
var I18n = require("../i18n.js");

var ES = require("../translations/es.json");
var EN = require("../translations/en.json");

// Cada formato se afirma en los DOS idiomas. Antes solo se miraba el español,
// que era justo el que estaba incrustado en el código: el inglés se quedaba sin
// comprobar y así es como el panel acabó mezclando lenguas en pantalla.
function es(desc) {
    return I18n.render(desc, ES);
}
function en(desc) {
    return I18n.render(desc, EN);
}

// Epoch en ms de una hora de pared LOCAL. El equivalente de h.localMs, que en
// Luau tenía que compensar a mano porque os.time interpreta UTC; el
// constructor de Date ya es local.
function ms(y, mo, d, hh, mm) {
    return new Date(y, mo - 1, d, hh, mm, 0, 0).getTime();
}

// Ancla fija en Europe/Madrid (TZ la pone run-js.fish): 2026-08-07 09:00 local.
var NOW = ms(2026, 8, 7, 9, 0);

describe("entorno", function () {
    // Sin TZ fija, describeAbsolute no es determinista. Si esto falla, el
    // fichero se está ejecutando fuera de run-js.fish.
    test("el lanzador fija TZ=Europe/Madrid", function () {
        var t = new Date(NOW);
        assert.equal(t.getHours(), 9, "hora local del ancla");
        assert.equal(t.getDate(), 7, "día local del ancla");
    });
});

describe("describeRelative", function () {
    test("menos de una hora", function () {
        assert.equal(es(Logic.describeRelative(NOW + 34 * 60000, NOW)), "en 34 min");
        assert.equal(en(Logic.describeRelative(NOW + 34 * 60000, NOW)), "in 34 min");
    });
    test("menos de un día, con y sin minutos sueltos", function () {
        assert.equal(es(Logic.describeRelative(NOW + (10 * 60 + 34) * 60000, NOW)), "en 10 h 34 min");
        assert.equal(es(Logic.describeRelative(NOW + 10 * 3600000, NOW)), "en 10 h");
    });
    test("más de un día, con y sin horas sueltas", function () {
        assert.equal(es(Logic.describeRelative(NOW + (2 * 24 + 4) * 3600000, NOW)), "en 2 d 4 h");
        assert.equal(es(Logic.describeRelative(NOW + 2 * 24 * 3600000, NOW)), "en 2 d");
    });
    test("ya vencido", function () {
        assert.equal(es(Logic.describeRelative(NOW - 1000, NOW)), "reiniciando…");
        assert.equal(es(Logic.describeRelative(NOW, NOW)), "reiniciando…");
        assert.equal(en(Logic.describeRelative(NOW, NOW)), "resetting…");
    });
    // null, no cadena vacía: el descriptor ausente es lo que le dice al
    // servicio que no hay nada que pintar, y render() lo convierte en "".
    test("sin fecha no hay descriptor", function () {
        assert.equal(Logic.describeRelative(null, NOW), null);
        assert.equal(es(Logic.describeRelative(null, NOW)), "");
    });
});

describe("describeAbsolute", function () {
    test("hoy es solo la hora", function () {
        assert.equal(es(Logic.describeAbsolute(ms(2026, 8, 7, 19, 30), NOW)), "a las 19:30");
        assert.equal(en(Logic.describeAbsolute(ms(2026, 8, 7, 19, 30), NOW)), "at 19:30");
    });
    test("mañana lleva prefijo", function () {
        assert.equal(es(Logic.describeAbsolute(ms(2026, 8, 8, 7, 0), NOW)), "mañana a las 07:00");
        assert.equal(en(Logic.describeAbsolute(ms(2026, 8, 8, 7, 0), NOW)), "tomorrow at 07:00");
    });
    test("dentro de la semana usa el día", function () {
        // 2026-08-10 es lunes
        assert.equal(es(Logic.describeAbsolute(ms(2026, 8, 10, 7, 0), NOW)), "el lunes a las 07:00");
        assert.equal(en(Logic.describeAbsolute(ms(2026, 8, 10, 7, 0), NOW)), "on Monday at 07:00");
    });
    // El orden día/mes es de la lengua, y por eso viajan sueltos: el mismo
    // descriptor da "20/8" en español y "8/20" en inglés.
    test("más allá de una semana usa la fecha, en el orden de cada lengua", function () {
        assert.equal(es(Logic.describeAbsolute(ms(2026, 8, 20, 7, 0), NOW)), "el 20/8 a las 07:00");
        assert.equal(en(Logic.describeAbsolute(ms(2026, 8, 20, 7, 0), NOW)), "on 8/20 at 07:00");
    });
    test("una fecha pasada no tiene descriptor", function () {
        assert.equal(Logic.describeAbsolute(ms(2026, 8, 6, 7, 0), NOW), null);
    });
    test("sin fecha no hay descriptor", function () {
        assert.equal(Logic.describeAbsolute(null, NOW), null);
    });
});

describe("formatAge", function () {
    test("por debajo del minuto, en segundos", function () {
        assert.equal(Logic.formatAge(NOW - 3000, NOW), "3 s");
        assert.equal(Logic.formatAge(NOW, NOW), "0 s");
        assert.equal(Logic.formatAge(NOW - 59000, NOW), "59 s");
    });
    test("minutos, horas y días", function () {
        assert.equal(Logic.formatAge(NOW - 12 * 60000, NOW), "12 min");
        assert.equal(Logic.formatAge(NOW - (2 * 60 + 5) * 60000, NOW), "2 h 5 min");
        assert.equal(Logic.formatAge(NOW - 3 * 3600000, NOW), "3 h");
        assert.equal(Logic.formatAge(NOW - (2 * 24 + 4) * 3600000, NOW), "2 d 4 h");
        assert.equal(Logic.formatAge(NOW - 2 * 24 * 3600000, NOW), "2 d");
    });
    // El reloj puede ir hacia atrás (NTP, suspensión). Un pie que diga
    // "hace -4 min" es peor que uno que diga "hace 0 s".
    test("un instante futuro no pinta negativos", function () {
        assert.equal(Logic.formatAge(NOW + 60000, NOW), "0 s");
    });
    test("sin fecha devuelve cadena vacía", function () {
        assert.equal(Logic.formatAge(null, NOW), "");
    });
    // La confusión que motivó esta función: describeRelative mira hacia adelante.
    test("describeRelative NO sirve para un instante pasado", function () {
        assert.equal(es(Logic.describeRelative(NOW - 3 * 60000, NOW)), "reiniciando…");
    });
});

describe("describeMoney", function () {
    // El importe se monta con format.decimal y format.money, así que el MISMO
    // descriptor sale "2,40 $" en español y "$2.40" en inglés.
    //
    // La sustitución va por split/join y no por String.replace a propósito:
    // gsub reemplaza TODAS las apariciones y no interpreta el "$" del
    // reemplazo, que en String.replace sí es un carácter especial y el
    // símbolo del dólar es justo uno de los valores que se inyectan aquí.
    function replaceAll(text, needle, value) {
        return text.split(needle).join(value);
    }
    function amount(m, cat) {
        // typeof y no truthiness: una cadena vacía es truthy en Lua y falsy
        // en JS, y aquí el original mira si HAY céntimos, no si valen algo.
        var text = typeof m.cents === "string" ? m.whole + cat["format.decimal"] + m.cents : m.whole;
        return replaceAll(replaceAll(cat["format.money"], "{amount}", text), "{symbol}", m.symbol);
    }

    test("el separador y el lado del símbolo son de la lengua", function () {
        assert.equal(amount(Logic.describeMoney(240, 2, "USD"), ES), "2,40 $");
        assert.equal(amount(Logic.describeMoney(240, 2, "USD"), EN), "$2.40");
        assert.equal(amount(Logic.describeMoney(3000, 2, "EUR"), ES), "30,00 €");
    });
    test("las piezas salen partidas", function () {
        var m = Logic.describeMoney(240, 2, "USD");
        assert.equal(m.whole, "2");
        assert.equal(m.cents, "40");
        assert.equal(m.symbol, "$");
    });
    test("una divisa desconocida usa su propio código", function () {
        assert.equal(amount(Logic.describeMoney(100, 2, "GBP"), ES), "1,00 GBP");
    });
    test("un exponente inválido cae a 2", function () {
        assert.equal(amount(Logic.describeMoney(240, null, "USD"), ES), "2,40 $");
        assert.equal(amount(Logic.describeMoney(240, -1, "USD"), ES), "2,40 $");
        assert.equal(amount(Logic.describeMoney(240, 2.5, "USD"), ES), "2,40 $"); // blindaje del ledger
    });
    // Con exponente 0 no hay punto que partir: sin céntimos y sin separador
    // colgando (el yen y el franco CFA son así).
    test("un exponente 0 no deja separador suelto", function () {
        var m = Logic.describeMoney(1200, 0, "JPY");
        assert.equal(m.whole, "1200");
        assert.equal(m.cents, null);
        assert.equal(amount(m, ES), "1200 JPY");
    });
    test("importe ausente es cero", function () {
        assert.equal(amount(Logic.describeMoney(null, 2, "USD"), ES), "0,00 $");
    });
});

// El panel de ajustes (Settings.qml) frente a lo que el plugin hace de verdad.
//
// Fichero NUEVO, no es traducción de ningún .luau: en Noctalia los ajustes se
// declaraban en plugin.toml con sus defaults escritos a mano, y el spec §10 del
// port pide justo lo contrario — que el panel se ate a las constantes de
// logic.js en vez de repetir los números.
//
// Lo que protege: que el panel diga lo mismo que el plugin hace. Una
// divergencia aquí no revienta nada y no se ve en ningún log: el panel enseña
// "90 %" mientras el daemon avisa a otro umbral, o el toggle sale apagado
// mientras el widget se comporta como si estuviera encendido. El usuario cambia
// el ajuste, "no pasa nada", y no hay forma de saber por qué.
//
// Por qué se LEE Settings.qml en vez de importarlo: es QML y node no puede
// cargarlo. Se escanea el fichero real —el mismo idioma que ya usa
// tests/translations.test.js— y los valores se resuelven contra logic.js, así
// que ningún número por defecto aparece escrito en este fichero. Si alguien
// cambia un `defaultValue` a un literal, estos casos se caen.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var fs = require("node:fs");
var path = require("node:path");

var Logic = require("../logic.js");

var PLUGIN_DIR = path.resolve(__dirname, "..");
var SETTINGS_QML = path.join(PLUGIN_DIR, "Settings.qml");
var DAEMON_QML = path.join(PLUGIN_DIR, "Daemon.qml");
var WIDGET_QML = path.join(PLUGIN_DIR, "Widget.qml");

// Los comentarios de estos ficheros explican el porqué de cada default y
// nombran los valores, así que un barrido que los mirase daría falsos positivos
// justo por estar bien documentados. Se mira solo el código. (Mismo criterio
// que pill-slots.test.js.)
function stripComments(source) {
    return source.replace(/\/\*[\s\S]*?\*\//g, "").split("\n").map(function (line) {
        var at = line.indexOf("//");
        return at === -1 ? line : line.slice(0, at);
    }).join("\n");
}

var SETTINGS_SRC = stripComments(fs.readFileSync(SETTINGS_QML, "utf8"));
var DAEMON_SRC = stripComments(fs.readFileSync(DAEMON_QML, "utf8"));
var WIDGET_SRC = stripComments(fs.readFileSync(WIDGET_QML, "utf8"));

// ── Lectura del panel ───────────────────────────────────────────────────────

// Cada ajuste es un bloque `<Tipo>Setting { … }`. Se extrae contando llaves
// desde la apertura del bloque, sobre el fichero ya sin comentarios.
function blocks(source) {
    var found = [];
    var pattern = /(\w+Setting)\s*\{/g;
    var m;
    while ((m = pattern.exec(source)) !== null) {
        var open = source.indexOf("{", m.index);
        var depth = 0;
        for (var i = open; i < source.length; i++) {
            if (source[i] === "{") depth += 1;
            else if (source[i] === "}") {
                depth -= 1;
                if (depth === 0) {
                    found.push({ type: m[1], body: source.slice(open + 1, i) });
                    break;
                }
            }
        }
    }
    return found;
}

function propertyOf(body, name) {
    var m = new RegExp("(?:^|\\n)\\s*" + name + "\\s*:\\s*([^\\n]+)").exec(body);
    return m === null ? null : m[1].trim().replace(/;$/, "");
}

// Resuelve la EXPRESIÓN de un `defaultValue` de QML a un valor de JavaScript.
// Una referencia `Logic.X` se resuelve contra logic.js de verdad: es lo que
// hace que este fichero no repita ni un solo número por defecto.
function resolveExpression(expression) {
    var named = /^Logic\.([A-Z0-9_]+)$/.exec(expression);
    if (named !== null) {
        assert.ok(Object.prototype.hasOwnProperty.call(Logic, named[1]),
                  'Settings.qml usa Logic.' + named[1] + ', que logic.js no exporta');
        return Logic[named[1]];
    }
    if (expression === "true") return true;
    if (expression === "false") return false;
    if (/^-?\d+$/.test(expression)) return parseInt(expression, 10);
    var quoted = /^"([^"]*)"$/.exec(expression);
    if (quoted !== null) return quoted[1];
    assert.fail('no sé resolver la expresión "' + expression + '" de Settings.qml');
}

var SETTINGS = (function () {
    var byKey = {};
    blocks(SETTINGS_SRC).forEach(function (block) {
        var key = propertyOf(block.body, "settingKey");
        if (key === null) return;
        var quoted = /^"([^"]*)"$/.exec(key);
        byKey[quoted === null ? key : quoted[1]] = {
            type: block.type,
            body: block.body,
            defaultExpression: propertyOf(block.body, "defaultValue"),
            minimum: propertyOf(block.body, "minimum"),
            maximum: propertyOf(block.body, "maximum")
        };
    });
    return byKey;
})();

function setting(key) {
    var found = SETTINGS[key];
    assert.ok(found, 'Settings.qml no declara ningún ajuste con settingKey "' + key + '"');
    assert.ok(found.defaultExpression, 'el ajuste "' + key + '" no declara defaultValue');
    return found;
}

function defaultOf(key) {
    return resolveExpression(setting(key).defaultExpression);
}

describe("ajustes / el panel se lee entero", function () {
    test("declara los seis ajustes del spec §10 y el selector de idioma", function () {
        ["warn_threshold", "idle_interval", "alert_interval", "show_scoped_limits", "show_extra_usage", "show_remaining", "language"].forEach(function (key) {
            setting(key);
        });
    });
});

describe("ajustes / los defaults numéricos vienen de logic.js", function () {
    // La comprobación de forma: el panel tiene que REFERENCIAR la constante,
    // no copiar su valor. Un `defaultValue: 90` pasaría todas las
    // comprobaciones de valor de aquí abajo el día que se escribe, y se
    // quedaría viejo en silencio el día que alguien cambie logic.js.
    var TIED = {
        warn_threshold: "DEFAULT_WARN_THRESHOLD",
        idle_interval: "DEFAULT_IDLE_INTERVAL",
        alert_interval: "DEFAULT_ALERT_INTERVAL"
    };

    Object.keys(TIED).forEach(function (key) {
        test('"' + key + '" referencia Logic.' + TIED[key] + ", no un número", function () {
            assert.equal(setting(key).defaultExpression, "Logic." + TIED[key],
                         'el defaultValue de "' + key + '" tiene que ser la constante de logic.js');
        });
    });

    test("el default de cada deslizador cae dentro de su propio rango", function () {
        ["warn_threshold", "idle_interval", "alert_interval"].forEach(function (key) {
            var found = setting(key);
            assert.ok(found.minimum !== null && found.maximum !== null,
                      'el deslizador "' + key + '" no declara rango');
            var min = resolveExpression(found.minimum);
            var max = resolveExpression(found.maximum);
            var value = defaultOf(key);
            assert.ok(min <= value && value <= max,
                      'el default de "' + key + '" (' + value + ') queda fuera de [' + min + ", " + max + "]");
        });
    });
});

describe("ajustes / el default del panel es lo que el plugin hace sin el ajuste", function () {
    // Esta es la mitad que de verdad importa: no basta con que el panel cite la
    // constante, tiene que citar LA MISMA que el consumidor usa cuando el
    // ajuste no está puesto.

    test("warn_threshold: el daemon resuelve la ausencia con la misma constante", function () {
        // El umbral no tiene default dentro de logic.js (isWarning exige un
        // número), así que la atadura es textual: el daemon lo resuelve con
        // configOr(clave, Logic.X) y ese Logic.X tiene que ser el del panel.
        var pattern = /configOr\(\s*"warn_threshold"\s*,\s*(Logic\.[A-Z0-9_]+)\s*\)/g;
        var seen = [];
        var m;
        while ((m = pattern.exec(DAEMON_SRC)) !== null) seen.push(m[1]);
        assert.ok(seen.length > 0, "Daemon.qml ya no resuelve warn_threshold con configOr(clave, Logic.X)");
        seen.forEach(function (expression) {
            assert.equal(expression, setting("warn_threshold").defaultExpression,
                         "Daemon.qml y Settings.qml no usan la misma constante para warn_threshold");
        });
    });

    // Los dos intervalos sí tienen su default DENTRO de logic.js
    // (usableInterval cae a DEFAULT_* ante un ajuste ausente), así que aquí la
    // atadura se comprueba por comportamiento: se pregunta a nextInterval qué
    // hace sin el ajuste, que es literalmente lo que el daemon le pasa
    // (`idleInterval: getConfig("idle_interval")` -> undefined).
    test("idle_interval: sin el ajuste, la cadencia en reposo es la que enseña el panel", function () {
        var seconds = Logic.nextInterval({
            warning: false,
            failures: 0,
            idleInterval: undefined,
            alertInterval: undefined
        });
        assert.equal(seconds, defaultOf("idle_interval"));
    });

    test("alert_interval: sin el ajuste, la cadencia en alerta es la que enseña el panel", function () {
        var seconds = Logic.nextInterval({
            warning: true,
            failures: 0,
            idleInterval: undefined,
            alertInterval: undefined
        });
        assert.equal(seconds, defaultOf("alert_interval"));
    });

    // Los tres toggles no tienen constante en logic.js —no aportarían nada: son
    // decisiones de presentación, no de la lógica—, así que su "verdad" es cómo
    // resuelve cada consumidor la ausencia del ajuste. Se lee del código de los
    // consumidores, no de una lista escrita aquí: una lista se quedaría vieja
    // en cuanto alguien cambie el sentido de un toggle.
    var CONSUMERS = {
        show_scoped_limits: WIDGET_SRC,
        show_extra_usage: WIDGET_SRC,
        show_remaining: DAEMON_SRC
    };

    // Dos formas, las dos presentes en el código:
    //   configOr("clave", X)     -> la ausencia vale X
    //   getConfig("clave") === true -> la ausencia vale false
    function assumedDefaults(key, source) {
        var assumed = [];
        var withFallback = new RegExp('configOr\\(\\s*"' + key + '"\\s*,\\s*(true|false)\\s*\\)', "g");
        var m;
        while ((m = withFallback.exec(source)) !== null) assumed.push(m[1] === "true");
        var strict = new RegExp('getConfig\\(\\s*"' + key + '"\\s*\\)\\s*===\\s*true', "g");
        while (strict.exec(source) !== null) assumed.push(false);
        return assumed;
    }

    Object.keys(CONSUMERS).forEach(function (key) {
        test('"' + key + '": el toggle arranca como se comporta el plugin sin el ajuste', function () {
            var assumed = assumedDefaults(key, CONSUMERS[key]);
            assert.ok(assumed.length > 0,
                      'nadie consume "' + key + '" de una forma reconocible (configOr(clave, bool) o getConfig(clave) === true)');
            assumed.forEach(function (value) {
                assert.equal(defaultOf(key), value,
                             'el panel arranca "' + key + '" en ' + defaultOf(key) + ' y el consumidor asume ' + value + " cuando el ajuste no está");
            });
        });
    });
});

describe("ajustes / el selector de idioma", function () {
    test('ofrece auto, en y es, y arranca en "auto"', function () {
        var found = setting("language");
        assert.equal(found.type, "SelectionSetting");
        assert.equal(defaultOf("language"), "auto");
        ["auto", "en", "es"].forEach(function (value) {
            assert.ok(new RegExp('value\\s*:\\s*"' + value + '"').test(found.body),
                      'el selector de idioma no ofrece el valor "' + value + '"');
        });
    });

    test("los tres valores que ofrece son los que pickLanguage entiende", function () {
        // "auto" tiene que seguir la locale, y los otros dos tienen que ganarle.
        var I18n = require("../i18n.js");
        assert.equal(I18n.pickLanguage("auto", "fr_FR"), "fr");
        assert.equal(I18n.pickLanguage("en", "fr_FR"), "en");
        assert.equal(I18n.pickLanguage("es", "fr_FR"), "es");
    });

    test("hay catálogo para cada idioma que el selector ofrece", function () {
        ["en", "es"].forEach(function (lang) {
            var file = path.join(PLUGIN_DIR, "translations", lang + ".json");
            assert.ok(fs.existsSync(file), "el selector ofrece " + lang + " y no hay translations/" + lang + ".json");
        });
    });
});

// ── El alcance de show_scoped_limits ────────────────────────────────────────
//
// La etiqueta del ajuste dice «mostrar sublímites POR MODELO», pero el popout
// escondía `others` entera al apagarlo, y ahí dentro va la ventana semanal: el
// ajuste te quitaba el número que decide tu semana. Un ajuste no puede hacer
// más de lo que promete su etiqueta.
//
// Se evalúa la función REAL sacada de Widget.qml, con el mismo método (y las
// mismas razones) que pill-slots.test.js usa con `pickWeekly` de Daemon.qml:
// copiarla aquí probaría la copia, no lo que se envía.
describe("ajustes / show_scoped_limits filtra solo los sublímites por modelo", function () {
    function extractFunction(source, name) {
        var start = source.indexOf("function " + name + "(");
        assert.notEqual(start, -1, 'Widget.qml ya no declara "function ' + name + '("');
        var open = source.indexOf("{", start);
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

    var withoutScopedLimits = (function () {
        var src = extractFunction(WIDGET_SRC, "withoutScopedLimits");
        var fn;
        try {
            fn = new Function("return (" + src + ");")();
        } catch (e) {
            assert.fail("withoutScopedLimits de Widget.qml ya no es JavaScript puro evaluable: " + e);
        }
        assert.equal(typeof fn, "function");
        return fn;
    })();

    // Las claves se construyen con la función de verdad, no a mano: es
    // Logic.limitKey quien decide el formato ("kind" o "kind:modelo").
    var WEEKLY = { key: Logic.limitKey("weekly_all", null), percent: 40 };
    var SESSION = { key: Logic.limitKey("session", null), percent: 10 };
    var SCOPED_OPUS = { key: Logic.limitKey("weekly_scoped", "Opus"), percent: 80 };
    var SCOPED_BARE = { key: Logic.limitKey("weekly_scoped", null), percent: 70 };

    test("encendido, la lista pasa entera", function () {
        var all = [WEEKLY, SCOPED_OPUS, SCOPED_BARE];
        assert.deepEqual(withoutScopedLimits(all, true), all);
    });

    test("apagado, la semanal SIGUE estando", function () {
        var kept = withoutScopedLimits([WEEKLY, SCOPED_OPUS], false);
        assert.deepEqual(kept, [WEEKLY]);
    });

    test("apagado, se van los sublímites por modelo, con y sin modelo en la clave", function () {
        var kept = withoutScopedLimits([SESSION, SCOPED_OPUS, WEEKLY, SCOPED_BARE], false);
        assert.deepEqual(kept, [SESSION, WEEKLY]);
    });

    test("apagado y sin nada más que sublímites, la lista queda vacía", function () {
        // El caso que deja al separador del popout sin nada que separar.
        assert.deepEqual(withoutScopedLimits([SCOPED_OPUS, SCOPED_BARE], false), []);
    });

    test("aguanta una lista ausente o con huecos", function () {
        assert.deepEqual(withoutScopedLimits(null, false), []);
        assert.deepEqual(withoutScopedLimits(undefined, true), []);
        assert.deepEqual(withoutScopedLimits([null, SCOPED_OPUS, WEEKLY], false), [WEEKLY]);
    });

    test("una clave que no conocemos NO se filtra", function () {
        // Filtrar por prefijo tiene un riesgo: llevarse por delante un kind
        // futuro que empiece igual. `weekly_scopedX` no es un sublímite.
        var extraño = { key: "weekly_scopedX", percent: 5 };
        assert.deepEqual(withoutScopedLimits([extraño], false), [extraño]);
    });

    // Y el separador: si se ata a `others` y no a la lista filtrada, se queda
    // una línea colgando encima de nada.
    test("el separador del popout se ata a la lista filtrada", function () {
        assert.ok(/PanelDivider\s*\{\s*visible:\s*root\.panelLimits\.length\s*>\s*0/.test(WIDGET_SRC),
                  "el PanelDivider de la lista de límites no mira root.panelLimits");
        assert.ok(/model:\s*root\.panelLimits/.test(WIDGET_SRC),
                  "el Repeater de la lista de límites no mira root.panelLimits");
    });
});

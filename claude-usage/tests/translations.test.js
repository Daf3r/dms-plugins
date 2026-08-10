// Traducción de tests/translations.test.luau: la red de seguridad del i18n.
// Su propiedad, la que hay que conservar cueste lo que cueste, es que NINGUNA
// clave que la lógica pueda emitir llegue a producción sin traducir en los DOS
// catálogos. Un fallo aquí no revienta nada: el usuario ve "panel.refresh" en
// la interfaz y nadie se entera hasta que lo mira.
//
// Diferencias respecto del original en Luau:
//   · los catálogos se cargan de translations/*.json con require, en vez de la
//     fixture generada tests/translations.fixture.luau;
//   · el escaneo de las entradas y del manifiesto ya no mira `plugin.toml` ni
//     los `.luau`: mira los ficheros del PORT (plugin.json y los .qml). Esos
//     ficheros llegan en las tareas 7 a 12, así que mientras no existan los dos
//     casos se marcan SKIP con el motivo escrito — visibles en el resumen de
//     `node --test`, no silenciados — y se activan solos en cuanto aparezcan.
//     Lo que se busca ya no es `noctalia.tr("…")`: DMS no tiene esa función y
//     cada entrada resolverá con i18n.render, así que se buscan las claves como
//     literales, sea cual sea la llamada que las envuelva;
//   · un caso NUEVO al final: que el descriptor no solo tenga clave en el
//     catálogo, sino que se PINTE. Ver su comentario.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var fs = require("node:fs");
var path = require("node:path");

var Logic = require("../logic.js");
var I18n = require("../i18n.js");

var ES = require("../translations/es.json");
var EN = require("../translations/en.json");

var PLUGIN_DIR = path.resolve(__dirname, "..");

function keysOf(catalog) {
    return Object.keys(catalog).sort();
}

// Ficheros fuente del plugin: todo menos las pruebas y los propios catálogos.
// Los `.luau` se listan también, pero ninguna comprobación los usa: son la
// fuente que se está traduciendo, no el port, y desaparecen en la tarea 13.
function walk(dir, out) {
    var entries = fs.readdirSync(dir, { withFileTypes: true });
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i];
        if (e.name === "tests" || e.name === "translations" || e.name[0] === ".")
            continue;
        var full = path.join(dir, e.name);
        if (e.isDirectory()) walk(full, out);
        else out.push(full);
    }
    return out;
}

var SOURCES = walk(PLUGIN_DIR, []);

function withExtension(ext) {
    return SOURCES.filter(function (f) { return path.extname(f) === ext; });
}

var QML_SOURCES = withExtension(".qml");
var MANIFEST = path.join(PLUGIN_DIR, "plugin.json");

// Un literal con forma de clave de catálogo: o bien "title" a secas, o bien uno
// de los espacios de nombres seguido de al menos un punto. Exigir el punto evita
// tragarse un "state" o un "format" sueltos de QML, que no son claves.
var KEY_LITERAL =
    /["'](title|(?:settings|state|panel|limit|time|reset|weekday|format|notify)\.[A-Za-z0-9_.]+)["']/g;

function keyLiteralsIn(text) {
    var found = [];
    var m;
    KEY_LITERAL.lastIndex = 0;
    while ((m = KEY_LITERAL.exec(text)) !== null) found.push(m[1]);
    return found;
}

describe("traducciones / paridad", function () {
    test("los dos idiomas cargan y no están vacíos", function () {
        assert.ok(ES && keysOf(ES).length > 0, "es.json vacío o ausente");
        assert.ok(EN && keysOf(EN).length > 0, "en.json vacío o ausente");
    });

    // Una clave presente en un idioma y no en el otro no revienta: i18n.render
    // cae al catálogo de respaldo y, si tampoco está, al literal de la clave —
    // así es como el usuario acaba viendo "panel.refresh" en la interfaz.
    // Es un fallo silencioso, y por eso hay test.
    test("los dos idiomas tienen exactamente las mismas claves", function () {
        keysOf(ES).forEach(function (k) {
            assert.ok(EN[k], 'en.json no tiene "' + k + '"');
        });
        keysOf(EN).forEach(function (k) {
            assert.ok(ES[k], 'es.json no tiene "' + k + '"');
        });
    });

    test("ninguna traducción está vacía", function () {
        keysOf(ES).forEach(function (k) {
            assert.ok(typeof ES[k] === "string" && ES[k] !== "", 'es."' + k + '" vacía');
            assert.ok(typeof EN[k] === "string" && EN[k] !== "", 'en."' + k + '" vacía');
        });
    });
});

describe("traducciones / cobertura del manifiesto", function () {
    // El manifiesto declara los seis ajustes con sus claves de etiqueta y
    // descripción. Una clave que falte deja la etiqueta de un ajuste mostrando
    // su propio id.
    test("cada clave settings.* del manifiesto existe en ambos idiomas", function (t) {
        if (!fs.existsSync(MANIFEST)) {
            t.skip("plugin.json todavía no existe (llega en la tarea 7)");
            return;
        }
        var text = fs.readFileSync(MANIFEST, "utf8");
        var found = 0;
        keyLiteralsIn(text).forEach(function (key) {
            if (key.indexOf("settings.") !== 0) return;
            found += 1;
            assert.ok(ES[key], 'plugin.json usa "' + key + '", que no está en es.json');
            assert.ok(EN[key], 'plugin.json usa "' + key + '", que no está en en.json');
        });
        assert.ok(found >= 6,
                  "solo " + found + " claves en el manifiesto, se esperaban >= 6");
    });
});

describe("traducciones / cobertura de las entradas", function () {
    // Cierra el círculo por el otro lado: cada clave escrita en el daemon, el
    // widget o el panel tiene que estar traducida. Sin esto, una clave mal
    // escrita solo se descubre viéndola en pantalla.
    test("cada clave usada en los .qml está traducida", function (t) {
        if (QML_SOURCES.length === 0) {
            t.skip("no hay .qml todavía (llegan en las tareas 8 a 12)");
            return;
        }
        var found = 0;
        QML_SOURCES.forEach(function (file) {
            var name = path.relative(PLUGIN_DIR, file);
            keyLiteralsIn(fs.readFileSync(file, "utf8")).forEach(function (key) {
                found += 1;
                assert.ok(ES[key], name + ' usa "' + key + '", que no está en es.json');
                assert.ok(EN[key], name + ' usa "' + key + '", que no está en en.json');
            });
        });
        assert.ok(found >= 5, "solo " + found + " claves en los .qml, se esperaban >= 5");
    });

    // panel.updatedAgo existía sin que nadie la usara, y esa orfandad era el
    // síntoma de un bug: el servicio formateaba fetchedAt con formatRelative,
    // que mira hacia adelante y devolvía "reiniciando…" siempre. No volver a
    // dejar claves huérfanas sin mirar por qué lo son.
    test("ninguna clave de panel.* queda sin usar", function (t) {
        if (QML_SOURCES.length === 0) {
            t.skip("no hay .qml todavía (llegan en las tareas 8 a 12)");
            return;
        }
        var used = {};
        QML_SOURCES.forEach(function (file) {
            keyLiteralsIn(fs.readFileSync(file, "utf8")).forEach(function (key) {
                used[key] = true;
            });
        });
        keysOf(ES).forEach(function (k) {
            if (k.indexOf("panel.") !== 0) return;
            assert.ok(used[k], '"' + k + '" está traducida pero no la usa ninguna entrada');
        });
    });
});

describe("traducciones / claves que produce logic.js", function () {
    // El escaneo de arriba busca literales, y desde el paso a descriptores la
    // mitad de las claves ya no aparecen escritas en ninguna entrada: logic.js
    // las devuelve y quien pinta las resuelve por variable. Quedaban fuera de
    // toda comprobación, que es exactamente el fallo silencioso que este
    // fichero existe para evitar.
    //
    // Se recogen LLAMANDO a las funciones, no listándolas a mano: una lista se
    // queda vieja en cuanto alguien renombra una clave, y esto no.
    function ms(y, mo, d, hh, mm) {
        return new Date(y, mo - 1, d, hh, mm, 0, 0).getTime();
    }
    var NOW = ms(2026, 8, 7, 9, 0);

    var descriptors = [
        Logic.labelDescriptor("session", null),
        Logic.labelDescriptor("weekly_all", null),
        Logic.labelDescriptor("weekly_scoped", "Opus"),
        Logic.labelDescriptor("weekly_scoped", null),
        Logic.labelDescriptor("monthly_xyz", null), // kind desconocido: sin clave
        Logic.describeRelative(NOW + 60000, NOW),
        Logic.describeRelative(NOW, NOW), // vencido
        Logic.describeAbsolute(ms(2026, 8, 7, 19, 30), NOW), // hoy
        Logic.describeAbsolute(ms(2026, 8, 8, 7, 0), NOW), // mañana
        Logic.describeAbsolute(ms(2026, 8, 10, 7, 0), NOW), // día de la semana
        Logic.describeAbsolute(ms(2026, 8, 20, 7, 0), NOW) // fecha
    ];

    test("cada clave de descriptor está en los dos idiomas", function () {
        var checked = 0;
        descriptors.forEach(function (d) {
            if (!d.key) return;
            checked += 1;
            assert.ok(ES[d.key], 'logic.js produce "' + d.key + '", que no está en es.json');
            assert.ok(EN[d.key], 'logic.js produce "' + d.key + '", que no está en en.json');
        });
        assert.ok(checked >= 9, "solo " + checked + " claves recogidas, se esperaban >= 9");
    });

    // weekday.N se compone con el índice, así que ninguna de las siete aparece
    // escrita en el código: si falta una, solo se ve el día que caiga en martes.
    test("los siete días de la semana están nombrados", function () {
        for (var i = 1; i <= 7; i++) {
            assert.ok(ES["weekday." + i], 'es.json no tiene "weekday.' + i + '"');
            assert.ok(EN["weekday." + i], 'en.json no tiene "weekday.' + i + '"');
        }
    });

    // NUEVO respecto del original, y es la mitad que faltaba. El test de arriba
    // comprueba que la clave EXISTE; este comprueba que el descriptor se PINTA.
    // Son cosas distintas y fallan por motivos distintos:
    //   · una clave presente pero con el hueco mal escrito ("{modelo}" donde el
    //     código manda `model`) pasa el test de existencia y sale en pantalla
    //     con el marcador crudo;
    //   · y sobre todo, `weekday.<N>` no se comprueba entera en ningún sitio: el
    //     original solo miraba que las siete claves estuvieran en el catálogo,
    //     porque quien componía el número con la clave era tests/render.luau —
    //     un espejo de la suite, no código de producción. En el port esa
    //     composición vive en i18n.js, que SÍ es producción, así que aquí se
    //     recorre entera: describeAbsolute emite `{key, params, weekday}`, e
    //     i18n.render tiene que devolver el día nombrado y no "weekday.4".
    test("ningún descriptor se pinta como su clave ni deja un hueco sin rellenar", function () {
        var catalogs = { es: ES, en: EN };
        descriptors.forEach(function (d) {
            Object.keys(catalogs).forEach(function (lang) {
                var out = I18n.render(d, catalogs[lang], {});
                var what = JSON.stringify(d) + " en " + lang;
                assert.notEqual(out, "", "se pinta vacío: " + what);
                if (d.key)
                    assert.notEqual(out, d.key, "se pinta como su propia clave: " + what);
                assert.equal(/\{\w+\}/.test(out), false,
                             "deja un hueco sin rellenar (" + out + "): " + what);
                assert.equal(/weekday\.\d/.test(out), false,
                             "el día de la semana no se nombró (" + out + "): " + what);
            });
        });
    });
});

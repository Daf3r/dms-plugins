// Traducción de tests/manifest.test.luau: la red de seguridad del manifiesto.
// El original comprobaba plugin.toml (formato de Noctalia) como TEXTO, porque
// Luau no lo parsea; aquí el manifiesto es plugin.json (formato de DMS), así
// que se lee con JSON.parse de verdad, sin regex sobre texto.
//
// El esquema es otro, no solo el formato: docs/.../PLUGINS/plugin-schema.json
// (dms-shell 1.6-beta) no tiene un array `[[setting]]` con label_key/default/
// min/max embebido en el manifiesto — DMS declara los ajustes con un
// componente QML aparte (`settings: "./Settings.qml"`, tarea 12). Las cinco
// aserciones del original chocan con eso de formas distintas; el resultado de
// cada una está anotado abajo.
//
// De los 5 casos de manifest.test.luau:
//   1. "declara al menos plugin_api 12"            -> DESCARTADO
//   2. "las tres entradas están declaradas"        -> PORTADO (adaptado a 2 surfaces)
//   3. "los defaults coinciden con logic.luau"     -> DESCARTADO
//   4. "los seis ajustes del spec existen"         -> PORTADO PARCIAL (ver abajo)
//   5. "los rangos respetan MIN_INTERVAL"          -> DESCARTADO
//
// Casos 1, 3 y 5 dependían todos de que el manifiesto llevase los ajustes
// inline (formato `[[setting]] key = "..." default = ... min = ...` de
// Noctalia). En DMS esos datos no existen en plugin.json en absoluto, así que
// no hay nada que leer para portarlos: la comparación de defaults y rangos
// contra logic.js tendrá que hacerse contra Settings.qml en la tarea 12, no
// aquí. Forzar una versión de estos tres casos contra plugin.json sería
// comprobar un valor que el fichero no declara.
//
// El caso de "plugin_api" tampoco tiene equivalente: DMS no versiona
// capacidades por nivel numérico (plugin_api = N), usa el rango semver de
// `requires_dms`, que es un mecanismo distinto y ya cubierto por el propio
// schema (pattern de la propiedad). No hay traducción 1:1 razonable.

"use strict";

var test = require("node:test");
var describe = require("node:test").describe;
var assert = require("node:assert/strict");

var fs = require("node:fs");
var path = require("node:path");

var MANIFEST_PATH = path.resolve(__dirname, "../plugin.json");
var manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8"));

describe("plugin.json", function () {
    test("id es camelCase, como exige el schema de DMS", function () {
        assert.match(manifest.id, /^[a-zA-Z][a-zA-Z0-9]*$/);
        // El directorio del plugin sigue llamándose con guiones; el id NO.
        assert.notEqual(manifest.id, "claude-usage");
    });

    // Portado de "las tres entradas están declaradas": el original miraba
    // [[service]], [[widget]], [[panel]] en el TOML de Noctalia. El mapa de
    // ficheros de esta tarea (§ "Estructura de ficheros") fusiona panel.luau
    // dentro de Widget.qml, así que aquí son dos surfaces, no tres.
    test("declara type composite con los componentes daemon y widget", function () {
        assert.equal(manifest.type, "composite");
        assert.ok(manifest.components, "falta components");
        assert.match(manifest.components.daemon, /^\.\/.*\.qml$/, "falta components.daemon");
        assert.match(manifest.components.widget, /^\.\/.*\.qml$/, "falta components.widget");
    });

    // Portado parcial de "los seis ajustes del spec existen": el original
    // verificaba las seis claves label_key inline. Aquí el manifiesto no
    // lleva los ajustes, solo la ruta al componente que los declara; verificar
    // que existan los seis de verdad es tarea de un test contra Settings.qml
    // en la tarea 12, cuando ese fichero exista.
    test("declara un componente de ajustes (los seis del spec viven ahí, tarea 12)", function () {
        assert.match(manifest.settings, /^\.\/.*\.qml$/, "falta settings");
    });

    // No viene de manifest.test.luau: es la advertencia del propio brief de
    // la tarea 7 ("settings_write es obligatorio: sin él, DMS muestra un
    // error en vez del panel de ajustes"), y no hay ningún otro test que la
    // cubra.
    test("permissions incluye settings_write", function () {
        assert.ok(Array.isArray(manifest.permissions), "permissions no es un array");
        assert.ok(manifest.permissions.includes("settings_write"),
                  "falta settings_write: DMS mostrará un error en el panel de ajustes");
    });

    test("requires_dms sigue el patrón semver con comparador", function () {
        assert.match(manifest.requires_dms, /^(>=?|<=?|=)\d+\.\d+\.\d+$/);
    });
});

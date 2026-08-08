local h = require("./harness")
local Logic = require("../logic")

-- El manifiesto es TOML y Luau no lo parsea. No hace falta: basta con leerlo
-- como texto y comprobar que los defaults que declara son los mismos que los
-- de logic.luau. Es la duplicación que el spec §10 acepta a regañadientes,
-- y este test es el precio de aceptarla.
--
-- El texto llega por un módulo que genera run.fish, no por io.open: el
-- intérprete de Luau está sandboxeado y no expone `io` en absoluto.
local toml = require("./manifest.fixture").toml

h.describe("plugin.toml", function()
  h.test("declara plugin_api 3", function()
    h.truthy(string.find(toml, "plugin_api = 3", 1, true))
  end)

  h.test("las tres entradas están declaradas", function()
    h.truthy(string.find(toml, "[[service]]", 1, true), "falta [[service]]")
    h.truthy(string.find(toml, "[[widget]]", 1, true), "falta [[widget]]")
    h.truthy(string.find(toml, "[[panel]]", 1, true), "falta [[panel]]")
  end)

  h.test("los defaults coinciden con los de logic.luau", function()
    local function defaultFor(key: string): number?
      local block = string.match(toml, `key = "{key}".-default = (%-?%d+)`)
      return tonumber(block)
    end
    h.eq(defaultFor("warn_threshold"), Logic.DEFAULT_WARN_THRESHOLD)
    h.eq(defaultFor("idle_interval"), Logic.DEFAULT_IDLE_INTERVAL)
    h.eq(defaultFor("alert_interval"), Logic.DEFAULT_ALERT_INTERVAL)
  end)

  h.test("los seis ajustes del spec existen", function()
    for _, key in { "warn_threshold", "idle_interval", "alert_interval",
                    "show_scoped_limits", "show_extra_usage", "show_remaining" } do
      h.truthy(string.find(toml, `key = "{key}"`, 1, true), `falta {key}`)
    end
  end)

  -- El suelo y el techo de cadencia de logic.luau tienen que caber en los
  -- rangos que el manifiesto deja elegir, o el usuario podrá fijar un valor
  -- que la lógica recorta sin decírselo.
  h.test("los rangos del manifiesto respetan MIN_INTERVAL", function()
    local minAlert = tonumber(string.match(toml, 'key = "alert_interval".-min = (%d+)'))
    h.truthy(minAlert, "alert_interval no declara min")
    h.truthy(minAlert :: number >= Logic.MIN_INTERVAL,
             `min de alert_interval ({tostring(minAlert)}) por debajo del suelo`)
  end)
end)

h.finish()

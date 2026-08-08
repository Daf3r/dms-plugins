local h = require("./harness")
local Logic = require("../logic")
local R = require("./render")
local T = require("./translations.fixture")

-- El fixture entra como JSON de la API y sale como el texto que el usuario lee,
-- en los dos idiomas: es el tramo más largo que se puede probar sin levantar el
-- shell.
local function es(desc): string return R.render(desc, T.es) end
local function en(desc): string return R.render(desc, T.en) end

local function money(m, cat): string
  local text = if m.cents then `{m.whole}{cat["format.decimal"]}{m.cents}` else m.whole
  return (string.gsub(string.gsub(cat["format.money"], "{amount}", text),
                      "{symbol}", m.symbol))
end

-- Payloads reales de la API, heredados de Caelestia. Llegan como módulo Luau
-- porque el intérprete no parsea JSON ni tiene `io`; los convierte
-- tests/json2luau.py desde tests/run.fish.
--
-- Esto es lo más parecido a una prueba extremo a extremo que se puede hacer
-- sin levantar el shell: entra el JSON tal cual lo devuelve Anthropic y sale
-- lo que el widget y el panel van a pintar.
-- No "./fixtures": sería ambiguo con el directorio tests/fixtures/.
local F = require("./payloads.fixture")

-- 2026-08-03 12:00 hora local de Madrid. Los resets de los fixtures caen ese
-- mismo día por la tarde y a la mañana siguiente.
local NOW = h.localMs(2026, 8, 3, 12, 0)

local SESSION_RESET = 1785777000000 -- 2026-08-03T17:10:00Z
local WEEKLY_RESET = 1785819600000 -- 2026-08-04T05:00:00Z

h.describe("fixtures / carga", function()
  h.test("los cuatro fixtures se convierten y cargan", function()
    for _, name in { "usage-normal", "usage-warning",
                     "usage-credits-on", "usage-no-limits" } do
      h.truthy(F[name], `falta el fixture {name}`)
      h.truthy(type(F[name]) == "table", `{name} no es tabla`)
    end
  end)

  h.test("un null de JSON llega como campo ausente, no como valor", function()
    -- "scope": null en usage-credits-on, "spend": null en usage-no-limits.
    h.nilish(F["usage-credits-on"].limits[1].scope)
    h.nilish(F["usage-no-limits"].spend)
    h.nilish(F["usage-no-limits"].extra_usage)
  end)
end)

h.describe("fixtures / usage-normal", function()
  local model = Logic.normalizeUsage(F["usage-normal"], "api", NOW)

  h.test("normaliza las tres ventanas con sus etiquetas", function()
    h.eq(#model.limits, 3)
    h.eq(model.limits[1].key, "session")
    h.eq(es(model.limits[1].label), "Sesión 5 h")
    h.eq(model.limits[2].key, "weekly_all")
    h.eq(es(model.limits[2].label), "Semana")
    h.eq(en(model.limits[2].label), "Week")
    h.eq(model.limits[3].key, "weekly_scoped:Fable")
    h.eq(es(model.limits[3].label), "Fable · semanal")
    h.eq(model.limits[3].scope, "Fable")
  end)

  h.test("los porcentajes salen del array limits[]", function()
    h.eq(model.limits[1].percent, 9)
    h.eq(model.limits[2].percent, 21)
    h.eq(model.limits[3].percent, 3)
  end)

  -- Esta es la comprobación que de verdad importa del lote: parseIsoMs contra
  -- el formato EXACTO que emite la API, con microsegundos y offset +00:00.
  h.test("parsea los resets reales, con fracción y offset", function()
    h.eq(model.limits[1].resetsAt, SESSION_RESET)
    h.eq(model.limits[2].resetsAt, WEEKLY_RESET)
  end)

  h.test("solo session y weekly_all son primarios", function()
    h.eq(model.limits[1].primary, true)
    h.eq(model.limits[2].primary, true)
    h.eq(model.limits[3].primary, false)
  end)

  -- La sesión es la primaria aunque vaya por debajo (9 % contra 21 %): es la
  -- ventana que va en la barra, no la que más ha subido.
  h.test("el primario es la sesión, no la que va más alta", function()
    local primary = Logic.pickPrimary(model.limits)
    h.eq(primary.key, "session")
    h.eq(primary.percent, 9)
    h.eq(Logic.isWarning(primary, 90), false)
  end)

  h.test("el panel muestra el resto ordenado por criticidad", function()
    local rest = Logic.sortForPanel(model.limits, "weekly_all")
    h.eq(#rest, 2)
    h.eq(rest[1].key, "session") -- 9 %
    h.eq(rest[2].key, "weekly_scoped:Fable") -- 3 %
  end)

  h.test("nada oculto en aviso, y ninguna notificación", function()
    h.eq(Logic.hasHiddenWarning(model.limits, "weekly_all", 90), false)
    h.eq(#Logic.notificationsFor(model.limits, 90, {}, NOW).notifications, 0)
  end)

  h.test("spend manda sobre extra_usage aunque esté deshabilitado", function()
    local x = model.extraUsage
    h.eq(x.enabled, false)
    h.eq(x.everEnabled, true) -- credits_ever_enabled de extra_usage
    h.eq(x.usedMinor, 0)
    h.eq(x.limitMinor, 3000)
    h.eq(x.currency, "USD")
    h.eq(x.disabledReason, "out_of_credits")
    h.eq(money(Logic.describeMoney(x.usedMinor, x.exponent, x.currency), T.es), "0,00 $")
    h.eq(money(Logic.describeMoney(x.limitMinor, x.exponent, x.currency), T.es), "30,00 $")
  end)

  h.test("los textos de fecha que verá el usuario", function()
    -- NOW son las 12:00 locales; el reset de sesión, las 19:10 locales.
    local session = model.limits[1]
    h.eq(es(Logic.describeAbsolute(session.resetsAt, NOW)), "a las 19:10")
    h.eq(es(Logic.describeRelative(session.resetsAt, NOW)), "en 7 h 10 min")
    local weekly = model.limits[2]
    h.eq(es(Logic.describeAbsolute(weekly.resetsAt, NOW)), "mañana a las 07:00")
    h.eq(es(Logic.describeRelative(weekly.resetsAt, NOW)), "en 19 h")
  end)
end)

h.describe("fixtures / usage-warning", function()
  local model = Logic.normalizeUsage(F["usage-warning"], "api", NOW)

  -- La barra lleva la sesión (42 %, tranquila) mientras la semanal está en
  -- aviso al 88 %. Ese es el caso que justifica el punto: sin él, la ventana
  -- que de verdad va mal no deja rastro en la barra.
  h.test("la semanal en aviso no es la primaria, pero sí deja punto", function()
    local primary = Logic.pickPrimary(model.limits)
    h.eq(primary.key, "session")
    h.eq(Logic.isWarning(primary, 90), false)
    h.eq(Logic.hasHiddenWarning(model.limits, primary.key, 90), true)
  end)

  h.test("la severidad de la API gana al porcentaje, en el orden del panel", function()
    local rest = Logic.sortForPanel(model.limits, "session")
    h.eq(rest[1].key, "weekly_all")
    h.eq(rest[1].percent, 88)
    h.eq(rest[1].severity, "warning")
    -- 88 < 90, así que el aviso viene de la severidad, no del umbral local
    h.eq(Logic.isWarning(rest[1], 90), true)
  end)

  h.test("notifica una sola vez, con el cuerpo completo", function()
    local r = Logic.notificationsFor(model.limits, 90, {}, NOW)
    h.eq(#r.notifications, 1)
    h.eq(r.notifications[1].key, "weekly_all")
    h.eq(R.render({ key = "notify.bodyWithReset", params = {
           percent = r.notifications[1].percent,
           limit = es(r.notifications[1].label),
           reset = es(r.notifications[1].reset) } }, T.es),
         "88 % de Semana consumido · se reinicia mañana a las 07:00")
  end)

  h.test("el antirrebote aguanta un segundo sondeo idéntico", function()
    local first = Logic.notificationsFor(model.limits, 90, {}, NOW)
    local second = Logic.notificationsFor(model.limits, 90, first.nextState, NOW)
    h.eq(#second.notifications, 0)
  end)
end)

h.describe("fixtures / usage-no-limits", function()
  local model = Logic.normalizeUsage(F["usage-no-limits"], "cache", NOW)

  h.test("sin limits[] cae a five_hour / seven_day", function()
    h.eq(#model.limits, 2)
    h.eq(model.limits[1].key, "session")
    h.eq(model.limits[1].percent, 42)
    h.eq(model.limits[2].key, "weekly_all")
    h.eq(model.limits[2].percent, 88)
    h.eq(model.source, "cache")
  end)

  h.test("los objetos sueltos no traen severidad", function()
    h.eq(model.limits[1].severity, "normal")
    h.eq(model.limits[2].severity, "normal")
    -- sin severidad, el aviso depende SOLO del umbral local
    h.eq(Logic.isWarning(model.limits[2], 90), false)
    h.eq(Logic.isWarning(model.limits[2], 80), true)
  end)

  h.test("también parsea sus resets", function()
    h.eq(model.limits[1].resetsAt, SESSION_RESET)
    h.eq(model.limits[2].resetsAt, WEEKLY_RESET)
  end)

  h.test("sin spend ni extra_usage no hay créditos", function()
    h.nilish(model.extraUsage)
  end)
end)

h.describe("fixtures / usage-credits-on", function()
  local model = Logic.normalizeUsage(F["usage-credits-on"], "api", NOW)

  h.test("una sola ventana, y es la primaria", function()
    h.eq(#model.limits, 1)
    local primary = Logic.pickPrimary(model.limits)
    h.eq(primary.key, "session")
    h.eq(primary.percent, 12)
    h.eq(#Logic.sortForPanel(model.limits, "session"), 0)
  end)

  h.test("los créditos salen de spend, en unidades menores", function()
    local x = model.extraUsage
    h.eq(x.enabled, true)
    h.eq(x.everEnabled, true)
    h.eq(x.usedMinor, 750)
    h.eq(x.limitMinor, 3000)
    h.eq(x.percent, 25)
    -- lo que el panel pinta en la fila de créditos extra
    h.eq(money(Logic.describeMoney(x.usedMinor, x.exponent, x.currency), T.es), "7,50 $")
    h.eq(money(Logic.describeMoney(x.limitMinor, x.exponent, x.currency), T.es), "30,00 $")
  end)

  h.test("un reset con Z pelada también se parsea", function()
    h.eq(model.limits[1].resetsAt, SESSION_RESET)
  end)
end)

h.finish()

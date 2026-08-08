local h = require("./harness")
local Logic = require("../logic")

h.describe("severityRank", function()
  h.test("conoce los tres estados", function()
    h.eq(Logic.severityRank("normal"), 0)
    h.eq(Logic.severityRank("warning"), 1)
    h.eq(Logic.severityRank("critical"), 2)
  end)
  h.test("una severidad desconocida se rankea como crítica", function()
    h.eq(Logic.severityRank("meltdown"), 2)
    h.eq(Logic.severityRank(nil), 2)
  end)
end)

h.describe("limitLabel", function()
  h.test("etiqueta las tres clases", function()
    h.eq(Logic.limitLabel("session", nil), "Sesión 5 h")
    h.eq(Logic.limitLabel("weekly_all", nil), "Semana")
    h.eq(Logic.limitLabel("weekly_scoped", "Opus"), "Opus · semanal")
  end)
  h.test("weekly_scoped sin nombre de modelo", function()
    h.eq(Logic.limitLabel("weekly_scoped", nil), "Sublímite semanal")
  end)
  h.test("un kind desconocido se devuelve tal cual", function()
    h.eq(Logic.limitLabel("monthly_xyz", nil), "monthly_xyz")
  end)
end)

h.describe("parseIsoMs", function()
  -- 1786078800000 es 2026-08-07T05:00:00Z. El plan traía 1786251600000, que
  -- es el día 9, no el 7.
  h.test("parsea una fecha UTC con offset Z", function()
    h.eq(Logic.parseIsoMs("2026-08-07T05:00:00Z"), 1786078800000)
  end)
  h.test("un offset explícito de cero equivale a Z", function()
    h.eq(Logic.parseIsoMs("2026-08-07T05:00:00+00:00"), 1786078800000)
  end)
  h.test("un offset positivo se resta para llegar a UTC", function()
    -- 07:00+02:00 es el mismo instante que 05:00Z
    h.eq(Logic.parseIsoMs("2026-08-07T07:00:00+02:00"), 1786078800000)
  end)
  h.test("un offset negativo se suma", function()
    -- 00:00-05:00 es el mismo instante que 05:00Z
    h.eq(Logic.parseIsoMs("2026-08-07T00:00:00-05:00"), 1786078800000)
  end)
  h.test("tolera fracciones de segundo y offset sin dos puntos", function()
    h.eq(Logic.parseIsoMs("2026-08-07T05:00:00.123Z"), 1786078800000)
    h.eq(Logic.parseIsoMs("2026-08-07T07:00:00+0200"), 1786078800000)
  end)
  h.test("devuelve nil ante basura o ausencia", function()
    h.nilish(Logic.parseIsoMs("no soy una fecha"))
    h.nilish(Logic.parseIsoMs(nil))
    h.nilish(Logic.parseIsoMs(""))
  end)
end)

h.describe("normalizeUsage", function()
  h.test("payload nil devuelve la forma vacía sin lanzar", function()
    local r = Logic.normalizeUsage(nil, "api", 1000)
    h.eq(#r.limits, 0)
    h.nilish(r.extraUsage)
    h.eq(r.source, "api")
  end)

  h.test("limits[] es la fuente canónica", function()
    local payload = {
      limits = {
        { kind = "session", percent = 42.4, severity = "normal",
          resets_at = "2026-08-07T05:00:00Z" },
        { kind = "weekly_all", percent = 88, severity = "warning",
          resets_at = "2026-08-08T05:00:00Z" },
        { kind = "weekly_scoped", percent = 3, severity = "normal",
          resets_at = "2026-08-08T05:00:00Z",
          scope = { model = { display_name = "Opus" } } },
      },
    }
    local r = Logic.normalizeUsage(payload, "api", 1000)
    h.eq(#r.limits, 3)
    h.eq(r.limits[1].key, "session")
    h.eq(r.limits[1].percent, 42) -- redondeado
    h.eq(r.limits[1].primary, true)
    h.eq(r.limits[3].key, "weekly_scoped:Opus")
    h.eq(r.limits[3].label, "Opus · semanal")
    h.eq(r.limits[3].scope, "Opus")
    h.eq(r.limits[3].primary, false)
  end)

  h.test("sin limits[] cae a five_hour / seven_day", function()
    local payload = {
      limits = {},
      five_hour = { utilization = 42, resets_at = "2026-08-07T05:00:00Z" },
      seven_day = { utilization = 88, resets_at = "2026-08-08T05:00:00Z" },
    }
    local r = Logic.normalizeUsage(payload, "cache", 1000)
    h.eq(#r.limits, 2)
    h.eq(r.limits[1].key, "session")
    h.eq(r.limits[2].key, "weekly_all")
    -- los objetos sueltos no traen severidad
    h.eq(r.limits[1].severity, "normal")
    h.eq(r.limits[1].primary, true)
  end)

  h.test("campos ausentes degradan a cero sin lanzar", function()
    local r = Logic.normalizeUsage({ limits = { { kind = "session" } } }, "api", nil)
    h.eq(r.limits[1].percent, 0)
    h.eq(r.limits[1].severity, "normal")
    h.nilish(r.limits[1].resetsAt)
  end)
end)

h.describe("normalizeUsage / extraUsage", function()
  h.test("spend tiene preferencia sobre extra_usage", function()
    local payload = {
      limits = {},
      spend = {
        enabled = true, percent = 8,
        used = { amount_minor = 240, currency = "USD", exponent = 2 },
        limit = { amount_minor = 3000, currency = "USD", exponent = 2 },
      },
      extra_usage = {
        is_enabled = false, credits_ever_enabled = true,
        used_credits = 99, monthly_limit = 99, currency = "EUR",
      },
    }
    local r = Logic.normalizeUsage(payload, "api", 1000)
    h.eq(r.extraUsage.usedMinor, 240)
    h.eq(r.extraUsage.limitMinor, 3000)
    h.eq(r.extraUsage.currency, "USD")
    h.eq(r.extraUsage.enabled, true)
    h.eq(r.extraUsage.everEnabled, true)
  end)

  h.test("sin spend, extra_usage convierte créditos decimales a menores", function()
    local payload = {
      limits = {},
      extra_usage = {
        is_enabled = true, credits_ever_enabled = true,
        used_credits = 2.4, monthly_limit = 3000,
        currency = "USD", decimal_places = 2, utilization = 8,
        disabled_reason = nil,
      },
    }
    local r = Logic.normalizeUsage(payload, "api", 1000)
    h.eq(r.extraUsage.usedMinor, 240)
    h.eq(r.extraUsage.exponent, 2)
    h.eq(r.extraUsage.percent, 8)
  end)

  h.test("sin spend ni extra_usage devuelve nil", function()
    local r = Logic.normalizeUsage({ limits = {} }, "api", 1000)
    h.nilish(r.extraUsage)
  end)
end)

h.finish()

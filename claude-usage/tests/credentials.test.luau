local h = require("./harness")
local Logic = require("../logic")

local NOW = 1786078800000 -- 2026-08-07T05:00:00Z

h.describe("parseCredentials", function()
  h.test("credenciales sanas", function()
    local r = Logic.parseCredentials(
      { claudeAiOauth = { accessToken = "sk-abc", expiresAt = NOW + 3600000 } }, NOW)
    h.eq(r.status, "ok")
    h.eq(r.token, "sk-abc")
  end)

  h.test("vencidas dentro del margen no entregan token", function()
    local r = Logic.parseCredentials(
      { claudeAiOauth = { accessToken = "sk-abc", expiresAt = NOW + 30000 } }, NOW)
    h.eq(r.status, "expired")
    h.nilish(r.token)
  end)

  h.test("nil (decode fallido) es inválido", function()
    h.eq(Logic.parseCredentials(nil, NOW).status, "invalid")
  end)

  h.test("sin claudeAiOauth es inválido", function()
    h.eq(Logic.parseCredentials({ otra = true }, NOW).status, "invalid")
  end)

  -- Falla CERRADO: los tres hallazgos de seguridad de la Task 7 de Caelestia.
  -- Los campos ausentes van aparte porque un nil dentro de un constructor de
  -- tabla deja un hueco que la iteración generalizada se salta.
  h.test("expiresAt ausente NO entrega el token", function()
    local r = Logic.parseCredentials({ claudeAiOauth = { accessToken = "sk-abc" } }, NOW)
    h.eq(r.status, "invalid")
    h.nilish(r.token)
  end)

  h.test("expiresAt no numérico NO entrega el token", function()
    for _, bad in { "1786078800000", {}, true, 0 / 0, math.huge, 0, -1 } :: any do
      local r = Logic.parseCredentials(
        { claudeAiOauth = { accessToken = "sk-abc", expiresAt = bad } }, NOW)
      h.eq(r.status, "invalid", `expiresAt={tostring(bad)}`)
      h.nilish(r.token, `expiresAt={tostring(bad)}`)
    end
  end)

  h.test("accessToken ausente es inválido", function()
    local r = Logic.parseCredentials(
      { claudeAiOauth = { expiresAt = NOW + 3600000 } }, NOW)
    h.eq(r.status, "invalid")
    h.nilish(r.token)
  end)

  h.test("accessToken vacío o no cadena es inválido", function()
    for _, bad in { "", 12345, {}, true } :: any do
      local r = Logic.parseCredentials(
        { claudeAiOauth = { accessToken = bad, expiresAt = NOW + 3600000 } }, NOW)
      h.eq(r.status, "invalid", `accessToken={tostring(bad)}`)
      h.nilish(r.token, `accessToken={tostring(bad)}`)
    end
  end)
end)

h.describe("extractCache", function()
  h.test("extrae payload y fecha", function()
    local r = Logic.extractCache({ cachedUsageUtilization = {
      utilization = { limits = {} }, fetchedAtMs = NOW } })
    h.eq(r.fetchedAt, NOW)
    h.truthy(r.payload)
  end)

  h.test("nil, sin clave, o fetchedAtMs inválido devuelven nil", function()
    h.nilish(Logic.extractCache(nil))
    h.nilish(Logic.extractCache({}))
    h.nilish(Logic.extractCache({ cachedUsageUtilization = {
      utilization = { limits = {} }, fetchedAtMs = 0 } }))
    h.nilish(Logic.extractCache({ cachedUsageUtilization = {
      utilization = { limits = {} }, fetchedAtMs = "ayer" } }))
    h.nilish(Logic.extractCache({ cachedUsageUtilization = {
      fetchedAtMs = NOW } }))
  end)
end)

h.finish()

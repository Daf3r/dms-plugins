--!strict
-- Lógica pura del plugin claude-usage. Traducción de logic.js (Caelestia).
--
-- REGLA: este fichero no llama a NINGUNA API host. Ni noctalia.*, ni ui.*.
-- Lo que necesite del entorno se le pasa por parámetro. Es lo que permite
-- correr la suite con `luau` sin levantar el shell.
--
-- Luau no trae JSON ni Date: las fechas viajan como epoch en milisegundos.

local M = {}

-- Una severidad que no conocemos se trata como la más grave: si Anthropic
-- añade un estado nuevo, preferimos un falso rojo a un silencio.
M.SEVERITY_RANK = { normal = 0, warning = 1, critical = 2 }

function M.severityRank(severity: string?): number
  local rank = if severity ~= nil then M.SEVERITY_RANK[severity] else nil
  return if rank == nil then 2 else rank
end

function M.limitLabel(kind: string, scopeName: string?): string
  if kind == "session" then return "Sesión 5 h" end
  if kind == "weekly_all" then return "Semana" end
  if kind == "weekly_scoped" then
    return if scopeName then `{scopeName} · semanal` else "Sublímite semanal"
  end
  return kind
end

M.PRIMARY_KINDS = { "session", "weekly_all" }

local function isPrimaryKind(kind: string): boolean
  for _, k in M.PRIMARY_KINDS do
    if k == kind then return true end
  end
  return false
end

-- Luau no parsea ISO 8601. La API entrega "2026-08-07T05:00:00+00:00" o "...Z".
--
-- `os.time` de Luau interpreta su tabla en UTC (timegm), a diferencia de Lua,
-- donde es hora local (mktime). Esta función devuelve por tanto 0 aquí. Se
-- conserva porque la misma fórmula da el desfase correcto en cualquiera de las
-- dos semánticas, así que el parseo no depende de cuál esté vigente.
local function localUtcOffsetSeconds(): number
  local t = os.time({ year = 2000, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
  local utc = os.time(os.date("!*t", t) :: any)
  return t - utc
end

function M.parseIsoMs(value: string?): number?
  if type(value) ~= "string" or value == "" then return nil end
  local y, mo, d, hh, mm, ss = string.match(
    value, "^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then return nil end

  local base = os.time({
    year = tonumber(y) :: number, month = tonumber(mo) :: number,
    day = tonumber(d) :: number, hour = tonumber(hh) :: number,
    min = tonumber(mm) :: number, sec = tonumber(ss) :: number,
  })
  if not base then return nil end
  base += localUtcOffsetSeconds()

  -- Offset explícito de la cadena: Z (0) o ±HH:MM. Un "+02:00" significa que
  -- la hora leída va dos horas por delante de UTC, así que se resta.
  local sign, oh, om = string.match(value, "([%+%-])(%d%d):?(%d%d)$")
  if sign then
    local delta = (tonumber(oh) :: number) * 3600 + (tonumber(om) :: number) * 60
    base += if sign == "+" then -delta else delta
  end

  return base * 1000
end

local function scopeNameOf(limit: {[string]: any}): string?
  local scope = limit.scope
  if type(scope) ~= "table" then return nil end
  local model = scope.model
  if type(model) ~= "table" then return nil end
  local name = model.display_name
  return if type(name) == "string" and name ~= "" then name else nil
end

local function limitKey(kind: string, scopeName: string?): string
  return if scopeName then `{kind}:{scopeName}` else kind
end

local function num(v: any, fallback: number): number
  return if type(v) == "number" and v == v then v else fallback
end

-- `spend` es la fuente preferida: trae importes en unidades menores y
-- exponente explícito. `extra_usage` da los créditos en decimal y hay que
-- convertirlos.
local function normalizeExtraUsage(payload: {[string]: any}): {[string]: any}?
  local extra = payload.extra_usage
  local spend = payload.spend
  if type(extra) ~= "table" and type(spend) ~= "table" then return nil end

  if type(spend) == "table" and type(spend.used) == "table"
     and type(spend.limit) == "table" then
    return {
      enabled = not not spend.enabled,
      everEnabled = if type(extra) == "table"
        then not not extra.credits_ever_enabled else true,
      usedMinor = num(spend.used.amount_minor, 0),
      limitMinor = num(spend.limit.amount_minor, 0),
      currency = if type(spend.used.currency) == "string"
        then spend.used.currency else "USD",
      exponent = num(spend.used.exponent, 2),
      percent = math.round(num(spend.percent, 0)),
      disabledReason = spend.disabled_reason,
    }
  end

  if type(extra) ~= "table" then return nil end

  local exponent = num(extra.decimal_places, 2)
  local factor = 10 ^ exponent
  return {
    enabled = not not extra.is_enabled,
    everEnabled = not not extra.credits_ever_enabled,
    usedMinor = math.round(num(extra.used_credits, 0) * factor),
    limitMinor = math.round(num(extra.monthly_limit, 0)),
    currency = if type(extra.currency) == "string" then extra.currency else "USD",
    exponent = exponent,
    percent = math.round(num(extra.utilization, 0)),
    disabledReason = extra.disabled_reason,
  }
end

function M.normalizeUsage(payload: {[string]: any}?, source: string,
                          fetchedAtMs: number?): {[string]: any}
  local result = { limits = {}, extraUsage = nil, source = source,
                   fetchedAt = fetchedAtMs }
  if type(payload) ~= "table" then return result end

  local raw = payload.limits
  if type(raw) == "table" and #raw > 0 then
    for _, item in raw do
      local scopeName = scopeNameOf(item)
      table.insert(result.limits, {
        key = limitKey(item.kind, scopeName),
        label = M.limitLabel(item.kind, scopeName),
        percent = math.round(num(item.percent, 0)),
        severity = if type(item.severity) == "string" then item.severity else "normal",
        resetsAt = M.parseIsoMs(item.resets_at),
        scope = scopeName,
        primary = isPrimaryKind(item.kind),
      })
    end
  else
    -- Sin limits[], los objetos sueltos son la única fuente. No traen
    -- severidad, así que el estado de aviso lo decide el umbral local.
    local legacy = {
      { kind = "session", data = payload.five_hour },
      { kind = "weekly_all", data = payload.seven_day },
    }
    for _, entry in legacy do
      if type(entry.data) ~= "table" then continue end
      table.insert(result.limits, {
        key = entry.kind,
        label = M.limitLabel(entry.kind, nil),
        percent = math.round(num(entry.data.utilization, 0)),
        severity = "normal",
        resetsAt = M.parseIsoMs(entry.data.resets_at),
        scope = nil,
        primary = true,
      })
    end
  end

  result.extraUsage = normalizeExtraUsage(payload)
  return result
end

return M

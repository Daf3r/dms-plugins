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
  -- Anotado explícitamente: inicializar `extraUsage = nil` en el constructor
  -- haría que Luau infiriese el campo como `nil` y rechazase la asignación
  -- real del final.
  local result: {[string]: any} = { limits = {}, source = source,
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

-- Definición única de "estar cerca del límite". La usan el color del widget,
-- el glifo indicador, la cadencia de alerta y la notificación.
function M.isWarning(limit: {[string]: any}?, threshold: number): boolean
  if type(limit) ~= "table" then return false end
  return limit.severity ~= "normal" or limit.percent >= threshold
end

-- Comparador de table.sort: devuelve `true` si `a` va ANTES que `b`.
--
-- El tercer criterio (key) no está en el original y es OBLIGATORIO aquí. En
-- JS, dos elementos con la misma severidad y el mismo porcentaje devolvían 0
-- y Array.sort, siendo estable, conservaba su orden. table.sort de Luau NO es
-- estable, y además valida el comparador: uno que diga `true` en ambos
-- sentidos para el mismo par lanza "invalid order function for sorting". Con
-- el desempate por key el orden es total, determinista e irreflexivo.
function M.byCriticality(a: {[string]: any}, b: {[string]: any}): boolean
  local ra, rb = M.severityRank(a.severity), M.severityRank(b.severity)
  if ra ~= rb then return ra > rb end
  if a.percent ~= b.percent then return a.percent > b.percent end
  return a.key < b.key
end

-- El widget solo puede codificar dos glifos, así que solo compite entre los
-- límites primarios. Los sublímites por modelo se señalan con el glifo
-- indicador (ver hasHiddenWarning).
function M.pickPrimary(limits: {any}): any?
  if type(limits) ~= "table" then return nil end
  local primaries = {}
  for _, l in limits do
    if type(l) == "table" and l.primary then table.insert(primaries, l) end
  end
  if #primaries == 0 then return nil end
  table.sort(primaries, M.byCriticality) -- copia local: no muta la entrada
  return primaries[1]
end

function M.sortForPanel(limits: {any}, primaryKey: string?): {any}
  if type(limits) ~= "table" then return {} end
  local rest = {}
  for _, l in limits do
    if type(l) == "table" and l.key ~= primaryKey then table.insert(rest, l) end
  end
  table.sort(rest, M.byCriticality)
  return rest
end

function M.hasHiddenWarning(limits: {any}, primaryKey: string?,
                            threshold: number): boolean
  if type(limits) ~= "table" then return false end
  for _, l in limits do
    if type(l) == "table" and l.key ~= primaryKey and M.isWarning(l, threshold) then
      return true
    end
  end
  return false
end

-- 1-based para casar con os.date("*t").wday, donde 1 = domingo.
M.WEEKDAYS = { "domingo", "lunes", "martes", "miércoles", "jueves",
               "viernes", "sábado" }
M.CURRENCY_SYMBOLS = { USD = "$", EUR = "€" }

local function pad2(n: number): string
  return if n < 10 then `0{n}` else tostring(n)
end

-- Las fechas se leen con os.date("*t"), que es hora LOCAL, y se vuelven a
-- componer con os.time, que en Luau es UTC. La asimetría no importa aquí
-- porque las dos medianoches se transforman igual y solo se usa su diferencia.
local function startOfDaySec(sec: number): number
  local t = os.date("*t", sec) :: any
  return os.time({ year = t.year, month = t.month, day = t.day,
                   hour = 0, min = 0, sec = 0 })
end

function M.formatRelative(resetsAtMs: number?, nowMs: number): string
  if type(resetsAtMs) ~= "number" then return "" end

  local delta = resetsAtMs - nowMs
  if delta <= 0 then return "reiniciando…" end

  local minutes = math.floor(delta / 60000)
  if minutes < 60 then return `en {minutes} min` end

  local hours = math.floor(minutes / 60)
  local restMinutes = minutes % 60
  if hours < 24 then
    return if restMinutes > 0 then `en {hours} h {restMinutes} min`
           else `en {hours} h`
  end

  local days = math.floor(hours / 24)
  local restHours = hours % 24
  return if restHours > 0 then `en {days} d {restHours} h` else `en {days} d`
end

function M.formatAbsolute(resetsAtMs: number?, nowMs: number): string
  if type(resetsAtMs) ~= "number" then return "" end

  local sec = math.floor(resetsAtMs / 1000)
  local t = os.date("*t", sec) :: any
  local clock = `a las {pad2(t.hour)}:{pad2(t.min)}`

  local dayDiff = math.round(
    (startOfDaySec(sec) - startOfDaySec(math.floor(nowMs / 1000))) / 86400)

  if dayDiff < 0 then return "" end
  if dayDiff == 0 then return clock end
  if dayDiff == 1 then return `mañana {clock}` end
  if dayDiff < 7 then return `el {M.WEEKDAYS[t.wday]} {clock}` end
  return `el {t.day}/{t.month} {clock}`
end

function M.formatMoney(amountMinor: number?, exponent: number?,
                       currency: string?): string
  -- Un exponente fraccionario pasa las demás guardas y da un importe raro
  -- (blindaje pedido por el ledger de la Task 5 de Caelestia): ISO 4217 es
  -- siempre entero.
  local exp = if type(exponent) == "number" and exponent == exponent
                 and exponent >= 0 and exponent <= 100 and exponent % 1 == 0
              then exponent else 2

  local value = (if type(amountMinor) == "number" then amountMinor else 0) / (10 ^ exp)
  local symbol = (if currency then M.CURRENCY_SYMBOLS[currency] else nil)
                 or currency or "USD"
  local text = string.format(`%.{exp}f`, value)
  return `{(string.gsub(text, "%.", ","))} {symbol}`
end

-- Techo del backoff (dobles por fallo), NO de la base que elige el usuario:
-- idleInterval/alertInterval pueden superarlo (spec §10). El propio backoff
-- nunca sondea por debajo de la base.
M.MAX_INTERVAL = 1800
M.MIN_INTERVAL = 15
M.DEFAULT_IDLE_INTERVAL = 300
M.DEFAULT_ALERT_INTERVAL = 60

-- Un valor solo es utilizable como intervalo si es un number finito y
-- estrictamente positivo. Cualquier otra cosa (nil, NaN, cadenas, 0,
-- negativos) es entrada basura y cae al default del spec, no al suelo: caer
-- al suelo sería el sondeo más agresivo posible por culpa de un ajuste roto.
local function usableInterval(value: any, fallback: number): number
  if type(value) ~= "number" then return fallback end
  if value ~= value then return fallback end          -- NaN
  if value == math.huge or value == -math.huge then return fallback end
  return if value > 0 then value else fallback
end

function M.nextInterval(state: {[string]: any}): number
  local base = if state.warning
    then usableInterval(state.alertInterval, M.DEFAULT_ALERT_INTERVAL)
    else usableInterval(state.idleInterval, M.DEFAULT_IDLE_INTERVAL)

  local failures = if type(state.failures) == "number" then state.failures else 0

  if failures > 0 then
    local doubled = base * (2 ^ failures)
    -- Dobla hasta el techo, pero nunca por debajo de la base: si la base ya
    -- supera el techo (p. ej. idleInterval 3600), un fallo no debe hacer el
    -- sondeo MÁS frecuente que en condiciones normales.
    return math.max(M.MIN_INTERVAL, base, math.min(doubled, M.MAX_INTERVAL))
  end

  return math.max(M.MIN_INTERVAL, base)
end

-- El host trabaja en milisegundos y todo lo de arriba en segundos. Esta es
-- la ÚNICA conversión del proyecto: si aparece otra, es un bug.
function M.toMilliseconds(seconds: number): number
  return seconds * 1000
end

return M

--!nonstrict
--!nolint FunctionUnused
-- `update` y `onIpc` son globals que llama el host, no código muerto:
-- noctalia.d.luau no las declara a propósito, así que el linter no puede
-- saberlo.
--
-- [[service]] headless: el único que toca red, ficheros, temporizador y
-- notificaciones. Publica un objeto YA CALCULADO en noctalia.state; el widget
-- y el panel solo pintan. Spec §4.
--
-- Es headless a propósito: quitar el widget de la barra no debe apagar los
-- avisos.

-- CON extensión, y no es un descuido. Noctalia y el intérprete `luau` suelto
-- exigen formas OPUESTAS: el host rechaza la ruta sin `.luau` ("require path
-- must be relative and end in .luau") y el CLI rechaza la ruta con ella
-- ("could not resolve child component"). Este fichero solo lo carga el host;
-- los de tests/ solo el CLI, y por eso allí van sin extensión.
local Logic = require("./logic.luau")

local ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
local CREDENTIALS = "~/.claude/.credentials.json"
local CACHE = "~/.claude.json"

local failures = 0
local inFlight = false
local notifyState = {}
local lastModel = nil

-- ── Estado persistido del antirrebote ────────────────────────────────────────
local function stateFilePath(): string?
  local dir = noctalia.pluginDataDir()
  if not dir then return nil end
  noctalia.mkdirAll(dir)
  return `{dir}/state.json`
end

local function loadNotifyState()
  local path = stateFilePath()
  if not path then return end
  local text = noctalia.readFile(path)
  if not text then return end
  local ok, decoded = pcall(noctalia.json.decode, text)
  if ok and type(decoded) == "table" then notifyState = decoded end
end

local function saveNotifyState(next)
  local path = stateFilePath()
  if not path then return end
  -- Solo se escribe si el contenido cambia: el ledger de la Task 10 de
  -- Caelestia observó una reescritura por sondeo aunque nada cambiara.
  local encoded = noctalia.json.encode(next)
  -- encode devuelve (string?, string?): si falla, no hay nada que escribir y
  -- writeFile(path, nil) reventaría.
  if not encoded then return end
  if encoded == noctalia.json.encode(notifyState) then return end
  noctalia.writeFile(path, encoded)
end

-- ── Publicación ──────────────────────────────────────────────────────────────
local function publish(status: string, model, source: string?, fetchedAt: number?)
  local threshold = noctalia.getConfig("warn_threshold") or Logic.DEFAULT_WARN_THRESHOLD
  local showRemaining = noctalia.getConfig("show_remaining") == true

  if not model then
    noctalia.state.set("usage", { status = status, primary = nil, others = {} })
    return
  end

  local primary = Logic.pickPrimary(model.limits)
  local nowMs = noctalia.nowMs()

  local function decorate(l)
    if not l then return nil end
    local shown = if showRemaining then 100 - l.percent else l.percent
    return {
      key = l.key, label = l.label, percent = shown,
      warning = Logic.isWarning(l, threshold),
      glyph = if l.key == "session" then "hourglass" else "calendar",
      resetsRel = Logic.formatRelative(l.resetsAt, nowMs),
      resetsAbs = Logic.formatAbsolute(l.resetsAt, nowMs),
    }
  end

  local others = {}
  for _, l in Logic.sortForPanel(model.limits, primary and primary.key or nil) do
    table.insert(others, decorate(l))
  end

  noctalia.state.set("usage", {
    status = status,
    source = source,
    primary = decorate(primary),
    others = others,
    hiddenWarning = Logic.hasHiddenWarning(
      model.limits, primary and primary.key or nil, threshold),
    extraUsage = model.extraUsage,
    -- formatAge, no formatRelative: fetchedAt está en el pasado y
    -- formatRelative devolvería "reiniciando…" siempre.
    fetchedAtLabel = if fetchedAt
      then noctalia.tr("panel.updatedAgo", { age = Logic.formatAge(fetchedAt, nowMs) })
      else nil,
  })
end

-- ── Cadencia ─────────────────────────────────────────────────────────────────
local function applyCadence(warning: boolean)
  local seconds = Logic.nextInterval({
    warning = warning,
    failures = failures,
    idleInterval = noctalia.getConfig("idle_interval"),
    alertInterval = noctalia.getConfig("alert_interval"),
  })
  noctalia.setUpdateInterval(Logic.toMilliseconds(seconds))
end

-- ── Respaldo por caché ───────────────────────────────────────────────────────
-- Solo se lee y parsea cuando la API falla (spec §3.2). Nunca notifica: el
-- ledger de la Task 10 observó un aviso disparado por un dato de una hora
-- antes.
local function fallbackToCache()
  -- El valor bueno en memoria manda sobre la caché de disco. El spec §9 los
  -- distingue en dos filas — "API caída, hay último valor bueno" frente a
  -- "API caída, SIN valor, hay caché" — y el orden importa de verdad: la
  -- caché puede ser de hace días, mientras que lastModel es de este arranque.
  -- Leer el disco primero enseñaba un dato de cuatro horas teniendo uno de
  -- treinta segundos.
  --
  -- lastModel ya lleva dentro su propio source y fetchedAt (los pone
  -- normalizeUsage), así que la procedencia se conserva y el panel puede decir
  -- "Sin conexión · hace 8 min" en vez de una antigüedad a secas.
  if lastModel then
    publish("stale", lastModel, lastModel.source, lastModel.fetchedAt)
    return
  end

  local text = noctalia.readFile(CACHE)
  if not text then
    -- Ni memoria ni caché: publish() con model nil hace que la UI diga
    -- "Sin conexión" en vez de pintar una píldora al 0 %.
    publish("stale", lastModel)
    return
  end
  local ok, doc = pcall(noctalia.json.decode, text)
  local cached = if ok then Logic.extractCache(doc) else nil
  if not cached then
    publish("stale", lastModel)
    return
  end
  local model = Logic.normalizeUsage(cached.payload, "cache", cached.fetchedAt)
  lastModel = model
  publish("stale", model, "cache", cached.fetchedAt)
end

-- ── Sondeo ───────────────────────────────────────────────────────────────────
local function poll()
  if inFlight then return end

  local credText = noctalia.readFile(CREDENTIALS)
  if not credText then
    publish("missing", nil)
    return
  end

  local ok, doc = pcall(noctalia.json.decode, credText)
  local creds = Logic.parseCredentials(if ok then doc else nil, noctalia.nowMs())

  if creds.status == "expired" then
    publish("expired", lastModel)
    return
  end
  if creds.status ~= "ok" then
    publish("missing", nil)
    return
  end

  inFlight = true
  -- El token viaja SOLO aquí. Nunca a noctalia.log, ni a la UI, ni a un
  -- mensaje de error (spec §12).
  local started = noctalia.http({
    url = ENDPOINT,
    headers = {
      `Authorization: Bearer {creds.token}`,
      "anthropic-beta: oauth-2025-04-20",
    },
  }, function(res)
    inFlight = false

    if not res.ok or res.status >= 500 or res.status == 429 then
      -- Noctalia no expone cabeceras de respuesta, así que Retry-After es
      -- ilegible incluso en un 429: se usa el backoff propio (spec §8).
      failures += 1
      fallbackToCache()
      applyCadence(false)
      return
    end

    if res.status == 401 or res.status == 403 then
      publish("expired", lastModel)
      applyCadence(false)
      return
    end

    local parsedOk, payload = pcall(noctalia.json.decode, res.body)
    if not parsedOk or type(payload) ~= "table" then
      failures += 1
      fallbackToCache()
      applyCadence(false)
      return
    end

    failures = 0
    local nowMs = noctalia.nowMs()
    local model = Logic.normalizeUsage(payload, "api", nowMs)
    lastModel = model
    publish("ok", model, "api", nowMs)

    local threshold = noctalia.getConfig("warn_threshold") or Logic.DEFAULT_WARN_THRESHOLD
    local primary = Logic.pickPrimary(model.limits)
    local warning = Logic.isWarning(primary, threshold)
       or Logic.hasHiddenWarning(model.limits, nil, threshold)

    local result = Logic.notificationsFor(model.limits, threshold, notifyState, nowMs)
    for _, n in result.notifications do
      noctalia.notify(n.summary, n.body)
    end
    saveNotifyState(result.nextState)
    notifyState = result.nextState

    applyCadence(warning)
  end)

  if not started then
    inFlight = false
    failures += 1
    fallbackToCache()
    applyCadence(false)
  end
end

-- ── Arranque e IPC ───────────────────────────────────────────────────────────
loadNotifyState()
noctalia.state.set("usage", { status = "loading", primary = nil, others = {} })
applyCadence(false)

function update()
  poll()
end

-- Refresco bajo demanda desde el widget o el panel. El ledger de la Task 10
-- avisó de que dos refrescos seguidos colapsaban en uno: la guarda inFlight
-- hace que el segundo sea un no-op explícito, no un silencio.
function onIpc(event: string, _payload: string?)
  if event == "refresh" then poll() end
end

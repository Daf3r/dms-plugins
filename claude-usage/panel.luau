--!nonstrict
-- [[panel]]: el desglose. Layout P2 del spec §6 — la ventana crítica manda,
-- el resto en lista fina. Todo el texto llega ya formateado del servicio.

local Logic = require("./logic")
local usage = noctalia.state.get("usage")

-- El refresco se pide al servicio por IPC: el panel no toca la red.
--
-- `runAsync` toma la línea de comando como UNA cadena, no como un array de
-- argumentos. No hay API de plugin a plugin en noctalia.d.luau, así que el
-- camino es el propio binario de Noctalia.
local function requestRefresh()
  noctalia.runAsync("noctalia msg plugin daf3r/claude-usage:poller refresh")
end

local function render()
  local u = usage

  if not u or u.status == "loading" then
    panel.render(ui.column({ gap = 8, padding = 16 }, {
      ui.label({ text = noctalia.tr("state.loading") }),
    }))
    return
  end

  if u.status == "expired" then
    panel.render(ui.column({ gap = 8, padding = 16 }, {
      ui.glyph({ name = "key-off", size = 24, color = "error" }),
      ui.label({ text = noctalia.tr("state.expired") }),
    }))
    return
  end

  if not u.primary then
    panel.render(ui.column({ gap = 8, padding = 16 }, {
      ui.label({ text = noctalia.tr("state.offline") }),
      ui.button({ label = noctalia.tr("panel.refresh"), onClick = requestRefresh }),
    }))
    return
  end

  local rows = {}

  -- 1. Tarjeta destacada.
  local p = u.primary
  table.insert(rows, ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = p.glyph, size = 16,
               color = if p.warning then "error" else "primary" }),
    ui.label({ text = p.label, fontWeight = "bold" }),
    ui.spacer({}),
    ui.label({ text = `{p.percent} %`, fontWeight = "bold",
               color = if p.warning then "error" else nil }),
  }))
  table.insert(rows, ui.progress({
    value = p.percent / 100,
    color = if p.warning then "error" else "primary",
  }))
  if p.resetsAbs ~= "" then
    table.insert(rows, ui.label({
      text = `{p.resetsAbs} · {p.resetsRel}`, color = "onSurfaceVariant" }))
  else
    table.insert(rows, ui.label({ text = p.resetsRel, color = "onSurfaceVariant" }))
  end

  -- 2. Resto de límites.
  if noctalia.getConfig("show_scoped_limits") ~= false and #u.others > 0 then
    table.insert(rows, ui.separator({}))
    for _, o in u.others do
      table.insert(rows, ui.row({ gap = 8 }, {
        ui.label({ text = o.label }),
        ui.spacer({}),
        ui.label({ text = `{o.percent} %`,
                   color = if o.warning then "error" else nil }),
      }))
    end
  end

  -- 3. Créditos extra.
  local extra = u.extraUsage
  if noctalia.getConfig("show_extra_usage") ~= false and extra
     and (extra.enabled or extra.everEnabled) then
    table.insert(rows, ui.separator({}))
    table.insert(rows, ui.row({ gap = 8 }, {
      ui.label({ text = noctalia.tr("panel.extraCredits") }),
      ui.spacer({}),
      ui.label({ text = `{Logic.formatMoney(extra.usedMinor, extra.exponent, extra.currency)} / {Logic.formatMoney(extra.limitMinor, extra.exponent, extra.currency)}` }),
    }))
  end

  -- 4. Pie.
  table.insert(rows, ui.separator({}))
  table.insert(rows, ui.row({ gap = 8, align = "center" }, {
    ui.label({
      text = if u.source == "cache"
        then `{noctalia.tr("state.cache")} · {u.fetchedAtLabel or ""}`
        else (u.fetchedAtLabel or ""),
      color = "onSurfaceVariant",
    }),
    ui.spacer({}),
    ui.button({ label = noctalia.tr("panel.refresh"), glyph = "refresh",
                variant = "ghost", onClick = requestRefresh }),
  }))

  panel.render(ui.scroll({}, { ui.column({ gap = 8, padding = 16 }, rows) }))
end

noctalia.state.watch("usage", function(value)
  usage = value
  render()
end)

-- Refresco inmediato al abrir (spec §7).
requestRefresh()
render()

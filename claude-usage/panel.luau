--!nonstrict
-- [[panel]]: el desglose. Layout P2 del spec §6 — la ventana crítica manda,
-- el resto en lista fina. Todo el texto llega ya formateado del servicio.

-- Con extensión: la exige el host. Ver la nota larga en service.luau — el CLI
-- de luau exige justo lo contrario, y por eso los tests van sin ella.
local Logic = require("./logic.luau")
local usage = noctalia.state.get("usage")

-- El refresco se pide al servicio por IPC: el panel no toca la red.
--
-- `runAsync` toma la línea de comando como UNA cadena, no como un array de
-- argumentos. No hay API de plugin a plugin en noctalia.d.luau, así que el
-- camino es el propio binario de Noctalia.
--
-- La firma es `plugin <author/plugin:entry> <target[:bar-name]> <event>`: el
-- `all` de en medio es obligatorio y es lo que usan los servicios oficiales
-- (ver el README de bitwarden). Sin él, `refresh` se lee como target y el
-- evento se queda sin poner.
local function requestRefresh()
  noctalia.runAsync("noctalia msg plugin daf3r/claude-usage:poller all refresh")
end

-- Barra de progreso a mano, con dos cajas en una fila y `flexGrow`.
--
-- `ui.progress` existe y está declarado en noctalia.d.luau, pero en esta build
-- ignora `value`, `percent` y `color`: se comprobó pintando cinco variantes a
-- la vez y las cinco salieron idénticas, llenas y blancas. Sin `height` no
-- aparece siquiera. El plan ya preveía este desenlace y prescribía justamente
-- ui.box con `fill`.
--
-- flexGrow en vez de anchos en píxeles porque el panel no sabe cuánto mide:
-- las dos cajas se reparten la fila en proporción y el relleno sale exacto sin
-- medir nada.
local function bar(percent: number, role: string)
  local filled = math.clamp(percent, 0, 100)
  return ui.row({ gap = 0 }, {
    ui.box({ flexGrow = filled, height = 6, radius = 3, fill = role }),
    ui.box({ flexGrow = 100 - filled, height = 6, radius = 3,
             fill = "surface_variant" }),
  })
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
      -- `text`, no `label`: ui.button ignora `label` y sale una cápsula vacía.
      ui.button({ text = noctalia.tr("panel.refresh"), onClick = requestRefresh }),
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
  table.insert(rows, bar(p.percent, if p.warning then "error" else "primary"))

  -- Los roles de color van en snake_case. "onSurfaceVariant" no lo reconoce
  -- nadie y cae al color por defecto, que es el mismo blanco del texto normal:
  -- el atenuado desaparece sin que nada falle.
  if p.resetsAbs ~= "" then
    table.insert(rows, ui.label({
      text = `{p.resetsAbs} · {p.resetsRel}`, color = "on_surface_variant" }))
  else
    table.insert(rows, ui.label({ text = p.resetsRel, color = "on_surface_variant" }))
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

  -- 4. Pie: procedencia Y antigüedad.
  --
  -- El spec §9 pide "Sin conexión · dato de hace 8 min" y "Caché local · hace
  -- 4 días": con dato viejo hay que decir POR QUÉ es viejo, no solo cuánto.
  -- Antes solo se marcaba la caché, así que un dato en memoria servido con la
  -- API caída se pintaba idéntico a uno fresco salvo por la antigüedad.
  local marker = ""
  if u.status == "stale" then
    marker = if u.source == "cache" then noctalia.tr("state.cache")
             else noctalia.tr("state.offline")
  end
  local age = u.fetchedAtLabel or ""
  local footer = if marker ~= "" and age ~= "" then `{marker} · {age}`
                 elseif marker ~= "" then marker
                 else age

  table.insert(rows, ui.separator({}))
  table.insert(rows, ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = footer, color = "on_surface_variant" }),
    ui.spacer({}),
    ui.button({ text = noctalia.tr("panel.refresh"), glyph = "refresh",
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

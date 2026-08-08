--!nonstrict
--!nolint FunctionUnused
-- `onClick` y `update` son globals que llama el host; noctalia.d.luau no las
-- declara a propósito, así que el linter las lee como código muerto.
--
-- [[widget]]: la píldora de barra. Solo pinta lo que el servicio ya decidió
-- (spec §5). Sin lógica de severidad, sin formateo de fechas.
--
-- El anillo del diseño de Caelestia NO es portable: ui.* no tiene arco ni
-- canvas. La ventana se codifica por GLIFO y la severidad por color, que
-- mantiene la propiedad que el anillo protegía — los dos canales separados,
-- así que ambas ventanas siguen distinguiéndose cuando las dos están en rojo.

local usage = noctalia.state.get("usage")

local function container()
  return if barWidget.isVertical() then ui.column else ui.row
end

-- Los estados sin número son un árbol de un solo glifo, NO setGlyph.
--
-- Mezclar las dos APIs no funciona y falla en silencio para el usuario: en
-- cuanto el widget ha pintado un render(), el host ignora setText/setGlyph y lo
-- avisa solo en el log ("have no visible effect while a render() tree is
-- active"). Como la píldora normal usa render(), el token vencido se quedaba
-- enseñando la píldora anterior en vez del candado — un dato viejo presentado
-- como bueno, que es justo lo que el spec §9 prohíbe.
local function glyphOnly(name: string, tooltip: string)
  barWidget.render(container()({ gap = 4, align = "center", paddingH = 6 }, {
    ui.glyph({ name = name, size = 14, color = "secondary" }),
  }))
  barWidget.setTooltip(tooltip)
end

local function render()
  local u = usage

  -- Ocultarse es setVisible(false), no render(nil): barWidget.render espera un
  -- árbol, y pasarle nil no es "sin contenido", es un tipo equivocado. Como el
  -- estado es pegajoso, todos los demás caminos tienen que volver a mostrarlo.
  if not u or u.status == "missing" then
    barWidget.setVisible(false) -- se oculta por completo (spec §9)
    return
  end
  barWidget.setVisible(true)

  if u.status == "loading" then
    glyphOnly("gauge", noctalia.tr("state.loading"))
    return
  end

  if u.status == "expired" then
    glyphOnly("key-off", noctalia.tr("state.expired"))
    return
  end

  -- stale con primary nulo = sin conexión y sin dato. Se dice, no se pinta un
  -- cero (carry-forward de las Tasks 11-13 de Caelestia).
  if not u.primary then
    glyphOnly("cloud-off", noctalia.tr("state.offline"))
    return
  end

  local p = u.primary

  -- "Píldora atenuada" del spec §9 cuando el dato no viene de un sondeo bueno.
  -- Sin esto, un número servido con la API caída se pinta idéntico a uno
  -- fresco, que es justo lo que el spec prohíbe: "ningún error deja el widget
  -- mostrando un número sin marcar su procedencia".
  --
  -- El atenuado es SUFIJO ALFA sobre el mismo rol, no un rol distinto. Bajo el
  -- esquema m3-monochrome, on_surface_variant y secondary dan los dos #C6C6C6
  -- exactos: atenuar cambiando de rol no pintaba nada. Es propio de los
  -- esquemas monocromos —  varios roles Material colapsan en el mismo gris —
  -- y no se puede saber de antemano qué pareja colapsa en el esquema del que
  -- lo instale. El alfa baja del rol que toque sea cual sea el esquema, y deja
  -- el hue libre para la severidad: las dos señales siguen siendo ortogonales
  -- cuando el dato es viejo Y hay aviso.
  --
  -- 0.7 y no menos: sobre el fondo de la barra da #949494, que es ~5:1 y pasa
  -- AA. 0.55 ya se queda en 3.6:1, ilegible de reojo para un número pequeño.
  --
  -- Los roles van en snake_case. Un nombre que el host no conoce NO cae al
  -- color normal: cae a negro, y lo avisa con "unknown color" en el log.
  local stale = u.status == "stale"
  local role = if p.warning then "error" else "secondary"
  if stale then
    role ..= "/0.7"
  end
  local children = {
    ui.glyph({ name = p.glyph, size = 14, color = role }),
    ui.label({ text = tostring(p.percent), color = role, fontWeight = "bold" }),
  }

  -- El equivalente al punto de 4 px del original: la única forma de que un
  -- sublímite por modelo al 95 % no pase desapercibido, dado que el glifo
  -- solo puede representar dos ventanas.
  if u.hiddenWarning then
    table.insert(children, ui.glyph({ name = "alert-circle", size = 9, color = "error" }))
  end

  barWidget.render(container()({
    gap = 4,
    align = "center",
    fill = if p.warning then "error/0.25" else nil,
    radius = 8,
    paddingH = 6,
  }, children))

  barWidget.setTooltip(`{p.label} · {p.percent} % · {p.resetsRel}`)
end

noctalia.state.watch("usage", function(value)
  usage = value
  render()
end)

-- Un clic alterna el panel. El refresco NO se dispara aquí: lo pide el propio
-- panel al montarse (spec §5), así que abrir refresca y cerrar no, sin que el
-- widget tenga que saber en qué estado quedó el panel.
function onClick()
  noctalia.togglePanel("daf3r/claude-usage:detail")
end

function update()
  render()
end

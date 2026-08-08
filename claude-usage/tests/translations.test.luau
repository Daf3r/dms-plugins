local h = require("./harness")

-- Todo lo que se lee del disco llega empaquetado (ver run.fish): el intérprete
-- no tiene `io` ni parsea JSON.
local T = require("./translations.fixture")
local M = require("./manifest.fixture")

local es, en = T.es, T.en

local function keysOf(t)
  local out = {}
  for k in t do table.insert(out, k) end
  table.sort(out)
  return out
end

h.describe("traducciones / paridad", function()
  h.test("los dos idiomas cargan y no están vacíos", function()
    h.truthy(es and next(es), "es.json vacío o ausente")
    h.truthy(en and next(en), "en.json vacío o ausente")
  end)

  -- Una clave presente en un idioma y no en el otro no revienta: el host cae al
  -- literal de la clave, así que el usuario ve "panel.refresh" en la interfaz.
  -- Es un fallo silencioso, y por eso hay test.
  h.test("los dos idiomas tienen exactamente las mismas claves", function()
    for _, k in keysOf(es) do
      h.truthy(en[k], `en.json no tiene "{k}"`)
    end
    for _, k in keysOf(en) do
      h.truthy(es[k], `es.json no tiene "{k}"`)
    end
  end)

  h.test("ninguna traducción está vacía", function()
    for _, k in keysOf(es) do
      h.truthy(type(es[k]) == "string" and es[k] ~= "", `es."{k}" vacía`)
      h.truthy(type(en[k]) == "string" and en[k] ~= "", `en."{k}" vacía`)
    end
  end)
end)

h.describe("traducciones / cobertura del manifiesto", function()
  -- El host resuelve label_key y description_key contra estos ficheros. Una
  -- clave que falte deja la etiqueta de un ajuste mostrando su propio id.
  h.test("cada label_key y description_key existe en ambos idiomas", function()
    local found = 0
    for _, pattern in { 'label_key = "([^"]+)"', 'description_key = "([^"]+)"' } do
      for key in string.gmatch(M.toml, pattern) do
        found += 1
        h.truthy(es[key], `plugin.toml usa "{key}", que no está en es.json`)
        h.truthy(en[key], `plugin.toml usa "{key}", que no está en en.json`)
      end
    end
    h.truthy(found >= 6, `solo {found} claves en el manifiesto, se esperaban >= 6`)
  end)
end)

h.describe("traducciones / cobertura de las entradas", function()
  -- Cierra el círculo por el otro lado: cada noctalia.tr("…") que aparece en
  -- service/widget/panel tiene que estar traducido. Sin esto, una clave mal
  -- escrita solo se descubre viéndola en pantalla.
  h.test("cada noctalia.tr() de las entradas está traducido", function()
    local found = 0
    for name, src in M.entries do
      for key in string.gmatch(src, 'noctalia%.tr%("([^"]+)"') do
        found += 1
        h.truthy(es[key], `{name}.luau usa tr("{key}"), que no está en es.json`)
        h.truthy(en[key], `{name}.luau usa tr("{key}"), que no está en en.json`)
      end
    end
    h.truthy(found >= 5, `solo {found} llamadas a tr(), se esperaban >= 5`)
  end)

  -- panel.updatedAgo existía sin que nadie la usara, y esa orfandad era el
  -- síntoma de un bug: el servicio formateaba fetchedAt con formatRelative,
  -- que mira hacia adelante y devolvía "reiniciando…" siempre. No volver a
  -- dejar claves huérfanas sin mirar por qué lo son.
  h.test("ninguna clave de panel.* queda sin usar", function()
    local used = {}
    for _, src in M.entries do
      for key in string.gmatch(src, 'noctalia%.tr%("([^"]+)"') do
        used[key] = true
      end
    end
    for _, k in keysOf(es) do
      if string.sub(k, 1, 6) == "panel." then
        h.truthy(used[k], `"{k}" está traducida pero no la usa ninguna entrada`)
      end
    end
  end)
end)

h.finish()

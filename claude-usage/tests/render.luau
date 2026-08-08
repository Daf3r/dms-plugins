-- Espejo de noctalia.tr para la suite. NO es un test: run.fish solo ejecuta
-- *.test.luau.
--
-- Desde que logic.luau devuelve descriptores en vez de texto, un test que solo
-- mirase la clave no vería el fallo que de verdad importa: un patrón de
-- traducción con el hueco mal escrito ("{modelo}" donde el código manda
-- `model`) deja la clave intacta y sale en pantalla. Resolviendo aquí igual que
-- el host, las pruebas siguen afirmando el TEXTO final — y ahora en los dos
-- idiomas, no solo en español.
--
-- Reproduce dos comportamientos del host, ambos observados en pantalla:
--   · sustitución de {hueco} por el valor;
--   · una clave ausente cae a su propio literal (así es como "panel.refresh"
--     acabó visible en la interfaz, según el ledger de translations.test).
local M = {}

local function substitute(pattern: string, params): string
  if not params then return pattern end
  return (string.gsub(pattern, "{(%w+)}", function(name)
    local value = params[name]
    -- Un hueco sin valor se deja intacto, que es lo que hace visible el error.
    return if value == nil then "{" .. name .. "}" else tostring(value)
  end))
end

function M.render(desc, catalogue): string
  if not desc then return "" end
  if desc.text then return desc.text end

  local params = desc.params
  if desc.weekday then
    params = if params then table.clone(params) else {}
    local key = `weekday.{desc.weekday}`
    params.weekday = catalogue[key] or key
  end

  local pattern = catalogue[desc.key]
  if not pattern then return desc.key end
  return substitute(pattern, params)
end

return M

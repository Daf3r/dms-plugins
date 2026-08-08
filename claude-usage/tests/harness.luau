--!strict
-- Arnés mínimo. No hay framework de test en Luau; esto es lo justo para
-- que la suite portada de Caelestia se lea igual que la original.
--
-- El CLI de luau no expone `os.exit` (su tabla `os` es solo clock/date/
-- difftime/time), así que el código de salida se comunica de la única forma
-- que queda: un error no capturado, que hace salir al intérprete con 1.
-- De ahí `finish()`, con la que cierra cada fichero de test.

local M = {}

local passed = 0
local failed = 0
local currentSuite = ""

function M.describe(name: string, fn: () -> ())
  currentSuite = name
  fn()
  currentSuite = ""
end

function M.test(name: string, fn: () -> ())
  local label = if currentSuite ~= "" then `{currentSuite} > {name}` else name
  local ok, err = pcall(fn)
  if ok then
    passed += 1
  else
    failed += 1
    print(`not ok - {label}`)
    print(`  {err}`)
  end
end

-- Comparación profunda: las tablas normalizadas se comparan enteras.
local function deepEq(a: any, b: any): boolean
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in a do
    if not deepEq(v, b[k]) then return false end
  end
  for k in b do
    if a[k] == nil then return false end
  end
  return true
end

function M.eq(actual: any, expected: any, msg: string?)
  if not deepEq(actual, expected) then
    error(`{msg or "eq"}: esperado {tostring(expected)}, recibido {tostring(actual)}`, 2)
  end
end

function M.truthy(v: any, msg: string?)
  if not v then error(`{msg or "truthy"}: valor falsy`, 2) end
end

function M.nilish(v: any, msg: string?)
  if v ~= nil then error(`{msg or "nilish"}: esperado nil, recibido {tostring(v)}`, 2) end
end

function M.report(): boolean
  print(`# pass {passed}`)
  print(`# fail {failed}`)
  return failed == 0
end

-- Cierre de cada fichero de test. Sustituye al `os.exit(...)` que no existe.
-- El nivel 0 en `error` evita que se anteponga "fichero:línea:" a un mensaje
-- que ya dice todo lo que hay que decir.
function M.finish()
  if not M.report() then
    error(`{failed} prueba(s) fallidas`, 0)
  end
end

return M

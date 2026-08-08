local h = require("./harness")
local Logic = require("../logic")

local function limit(key, percent, severity, primary)
  return { key = key, label = key, percent = percent, severity = severity,
           resetsAt = nil, scope = nil, primary = primary }
end

h.describe("isWarning", function()
  h.test("por severidad, aunque el porcentaje sea bajo", function()
    h.eq(Logic.isWarning(limit("a", 3, "warning", true), 90), true)
  end)
  h.test("por umbral, aunque la severidad sea normal", function()
    h.eq(Logic.isWarning(limit("a", 90, "normal", true), 90), true)
    h.eq(Logic.isWarning(limit("a", 89, "normal", true), 90), false)
  end)
  h.test("nil no es aviso y no lanza", function()
    h.eq(Logic.isWarning(nil, 90), false)
  end)
end)

h.describe("byCriticality", function()
  h.test("la severidad manda sobre el porcentaje", function()
    local a = limit("a", 10, "critical", true)
    local b = limit("b", 99, "normal", true)
    h.eq(Logic.byCriticality(a, b), true)
    h.eq(Logic.byCriticality(b, a), false)
  end)
  h.test("a igual severidad, mayor porcentaje primero", function()
    local a = limit("a", 80, "normal", true)
    local b = limit("b", 20, "normal", true)
    h.eq(Logic.byCriticality(a, b), true)
  end)
  -- EL CASO QUE EL ORIGINAL NO TENÍA
  h.test("empate total desempata por key, de forma determinista", function()
    local a = limit("aaa", 50, "normal", true)
    local b = limit("bbb", 50, "normal", true)
    h.eq(Logic.byCriticality(a, b), true)
    h.eq(Logic.byCriticality(b, a), false)
    -- irreflexivo: table.sort lanza si comp(x, x) es true
    h.eq(Logic.byCriticality(a, a), false)
  end)
  h.test("ordenar una lista con empates totales no lanza y es estable", function()
    local list = {
      limit("ccc", 50, "normal", true), limit("aaa", 50, "normal", true),
      limit("bbb", 50, "normal", true), limit("ddd", 50, "normal", true),
    }
    table.sort(list, Logic.byCriticality)
    h.eq(list[1].key, "aaa")
    h.eq(list[4].key, "ddd")
  end)
end)

h.describe("pickPrimary", function()
  -- La sesión gana aunque la semanal vaya más alta Y más grave: es la ventana
  -- que se recupera esperando, y por eso es la que vive en la barra.
  h.test("la sesión de 5 h manda sobre la semanal", function()
    local limits = {
      limit("weekly_scoped:Opus", 99, "critical", false),
      limit("session", 42, "normal", true),
      limit("weekly_all", 88, "warning", true),
    }
    h.eq(Logic.pickPrimary(limits).key, "session")
  end)
  -- Si la API deja de mandar la ventana de sesión, se cae al primario más
  -- grave; el sublímite por modelo sigue sin competir, que es lo de siempre.
  h.test("sin sesión, cae al primario más grave", function()
    local limits = {
      limit("weekly_scoped:Opus", 99, "critical", false),
      limit("weekly_all", 88, "warning", true),
    }
    h.eq(Logic.pickPrimary(limits).key, "weekly_all")
  end)
  -- Con la sesión fija en la barra, el punto de aviso es la única señal de una
  -- semanal en rojo. Si esto se rompe, la semanal se vuelve invisible.
  h.test("una semanal en aviso deja punto aunque la primaria sea la sesión", function()
    local limits = {
      limit("session", 10, "normal", true),
      limit("weekly_all", 95, "warning", true),
    }
    local primary = Logic.pickPrimary(limits)
    h.eq(primary.key, "session")
    h.eq(Logic.hasHiddenWarning(limits, primary.key, 90), true)
  end)
  h.test("sin primarios devuelve nil", function()
    h.nilish(Logic.pickPrimary({ limit("x", 99, "critical", false) }))
  end)
  h.test("lista vacía devuelve nil", function()
    h.nilish(Logic.pickPrimary({}))
  end)
  h.test("no muta el array de entrada", function()
    local limits = { limit("session", 10, "normal", true),
                     limit("weekly_all", 90, "normal", true) }
    Logic.pickPrimary(limits)
    h.eq(limits[1].key, "session")
  end)
end)

h.describe("sortForPanel", function()
  h.test("excluye el primario y ordena el resto", function()
    local limits = {
      limit("session", 42, "normal", true),
      limit("weekly_all", 88, "warning", true),
      limit("weekly_scoped:Opus", 60, "normal", false),
    }
    local rest = Logic.sortForPanel(limits, "weekly_all")
    h.eq(#rest, 2)
    h.eq(rest[1].key, "weekly_scoped:Opus")
    h.eq(rest[2].key, "session")
  end)
  h.test("primaryKey nil devuelve todos", function()
    h.eq(#Logic.sortForPanel({ limit("a", 1, "normal", true) }, nil), 1)
  end)
end)

h.describe("hasHiddenWarning", function()
  h.test("detecta un sublímite en aviso fuera del primario", function()
    local limits = {
      limit("weekly_all", 10, "normal", true),
      limit("weekly_scoped:Opus", 95, "normal", false),
    }
    h.eq(Logic.hasHiddenWarning(limits, "weekly_all", 90), true)
  end)
  h.test("ignora el propio primario", function()
    local limits = { limit("weekly_all", 95, "normal", true) }
    h.eq(Logic.hasHiddenWarning(limits, "weekly_all", 90), false)
  end)
end)

h.finish()

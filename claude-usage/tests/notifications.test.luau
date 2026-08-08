local h = require("./harness")
local Logic = require("../logic")
local R = require("./render")
local T = require("./translations.fixture")

-- Horas de pared locales: el cuerpo esperado de la notificación las lleva
-- escritas. Ver h.localMs para por qué no vale os.time a secas.
local NOW = h.localMs(2026, 8, 7, 9, 0)
local RESET = h.localMs(2026, 8, 8, 7, 0)

local function limit(key, percent, severity, resetsAt)
  return { key = key, label = { key = "limit.weeklyAll" }, percent = percent,
           severity = severity, resetsAt = resetsAt, scope = nil, primary = true }
end

-- notificationsFor ya no devuelve el cuerpo montado: devuelve las piezas y es
-- el servicio quien las pasa por tr. Esto reproduce esa composición para poder
-- seguir afirmando el texto que de verdad llega a la notificación.
local function body(n, cat): string
  local key = if n.reset then "notify.bodyWithReset" else "notify.body"
  return R.render({
    key = key,
    params = {
      percent = n.percent,
      limit = R.render(n.label, cat),
      reset = R.render(n.reset, cat),
    },
  }, cat)
end

h.describe("notificationsFor", function()
  h.test("notifica al cruzar el umbral", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 90, "normal", RESET) },
                                     90, {}, NOW)
    h.eq(#r.notifications, 1)
    h.eq(body(r.notifications[1], T.es),
         "90 % de Semana consumido · se reinicia mañana a las 07:00")
    h.eq(body(r.notifications[1], T.en),
         "90 % of Week used · resets tomorrow at 07:00")
    h.eq(r.nextState["weekly_all"].notified, true)
  end)

  h.test("no vuelve a notificar dentro de la misma ventana", function()
    local first = Logic.notificationsFor({ limit("weekly_all", 90, "normal", RESET) },
                                         90, {}, NOW)
    local second = Logic.notificationsFor({ limit("weekly_all", 95, "normal", RESET) },
                                          90, first.nextState, NOW)
    h.eq(#second.notifications, 0)
  end)

  h.test("una ventana nueva rearma el aviso", function()
    local first = Logic.notificationsFor({ limit("weekly_all", 90, "normal", RESET) },
                                         90, {}, NOW)
    local newReset = RESET + 7 * 24 * 3600000
    local second = Logic.notificationsFor({ limit("weekly_all", 91, "normal", newReset) },
                                          90, first.nextState, NOW)
    h.eq(#second.notifications, 1)
  end)

  -- Rama dip-and-rise: el ledger de la Task 8 la dejó SIN test. Aquí sí.
  h.test("bajar y volver a subir en la misma ventana no re-notifica", function()
    local a = Logic.notificationsFor({ limit("weekly_all", 91, "normal", RESET) },
                                     90, {}, NOW)
    local b = Logic.notificationsFor({ limit("weekly_all", 85, "normal", RESET) },
                                     90, a.nextState, NOW)
    local c = Logic.notificationsFor({ limit("weekly_all", 92, "normal", RESET) },
                                     90, b.nextState, NOW)
    h.eq(#c.notifications, 0)
  end)

  h.test("por debajo del umbral no notifica pero conserva la ventana", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 10, "normal", RESET) },
                                     90, {}, NOW)
    h.eq(#r.notifications, 0)
    h.eq(r.nextState["weekly_all"].notified, false)
  end)

  h.test("un threshold inválido cae al default, no a cero", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 50, "normal", RESET) },
                                     nil, {}, NOW)
    h.eq(#r.notifications, 0) -- 50 < 90; con threshold 0 habría notificado
  end)

  -- Sin cláusula la clave cambia entera (notify.body, no bodyWithReset): son
  -- dos frases distintas y no una con un trozo pegado, porque dónde encaja el
  -- "se reinicia …" lo decide la lengua.
  h.test("sin resetsAt válido omite la cláusula entera", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 95, "normal", nil) },
                                     90, {}, NOW)
    h.eq(r.notifications[1].reset, nil)
    h.eq(body(r.notifications[1], T.es), "95 % de Semana consumido")
    h.eq(body(r.notifications[1], T.en), "95 % of Week used")
  end)

  h.test("sin un now válido omite la cláusula entera", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 95, "normal", RESET) },
                                     90, {}, nil)
    h.eq(r.notifications[1].reset, nil)
    h.eq(body(r.notifications[1], T.es), "95 % de Semana consumido")
  end)

  h.test("limits que no es tabla devuelve vacío sin lanzar", function()
    local r = Logic.notificationsFor(nil :: any, 90, {}, NOW)
    h.eq(#r.notifications, 0)
  end)

  -- El plan escribía `{ nil, limit(...) }`, pero un nil en un constructor deja
  -- un hueco que la iteración se salta: la guarda `type(limit) ~= "table"`
  -- quedaba sin ejercitar. Con valores reales sí se recorre.
  h.test("una entrada que no es tabla se salta sin lanzar", function()
    local r = Logic.notificationsFor(
      { false, "basura", 42, limit("weekly_all", 95, "normal", RESET) } :: any,
      90, {}, NOW)
    h.eq(#r.notifications, 1)
    h.eq(r.notifications[1].key, "weekly_all")
  end)

  h.test("prevState que no es tabla se trata como vacío", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 95, "normal", RESET) },
                                     90, "basura" :: any, NOW)
    h.eq(#r.notifications, 1)
  end)
end)

h.finish()

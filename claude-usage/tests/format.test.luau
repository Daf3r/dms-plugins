local h = require("./harness")
local Logic = require("../logic")
local R = require("./render")
local T = require("./translations.fixture")

-- Cada formato se afirma en los DOS idiomas. Antes solo se miraba el español,
-- que era justo el que estaba incrustado en el código: el inglés se quedaba sin
-- comprobar y así es como el panel acabó mezclando lenguas en pantalla.
local function es(desc): string return R.render(desc, T.es) end
local function en(desc): string return R.render(desc, T.en) end

-- Ancla fija en Europe/Madrid (TZ la pone run.fish): 2026-08-07 09:00 local.
-- El porqué de no usar os.time directamente está en h.localMs.
local ms = h.localMs
local NOW = ms(2026, 8, 7, 9, 0)

h.describe("entorno", function()
  -- Sin TZ fija, formatAbsolute no es determinista. Si esto falla, el fichero
  -- se está ejecutando fuera de run.fish.
  h.test("el lanzador fija TZ=Europe/Madrid", function()
    local t = os.date("*t", NOW // 1000) :: any
    h.eq(t.hour, 9, "hora local del ancla")
    h.eq(t.day, 7, "día local del ancla")
  end)
end)

h.describe("describeRelative", function()
  h.test("menos de una hora", function()
    h.eq(es(Logic.describeRelative(NOW + 34 * 60000, NOW)), "en 34 min")
    h.eq(en(Logic.describeRelative(NOW + 34 * 60000, NOW)), "in 34 min")
  end)
  h.test("menos de un día, con y sin minutos sueltos", function()
    h.eq(es(Logic.describeRelative(NOW + (10 * 60 + 34) * 60000, NOW)), "en 10 h 34 min")
    h.eq(es(Logic.describeRelative(NOW + 10 * 3600000, NOW)), "en 10 h")
  end)
  h.test("más de un día, con y sin horas sueltas", function()
    h.eq(es(Logic.describeRelative(NOW + (2 * 24 + 4) * 3600000, NOW)), "en 2 d 4 h")
    h.eq(es(Logic.describeRelative(NOW + 2 * 24 * 3600000, NOW)), "en 2 d")
  end)
  h.test("ya vencido", function()
    h.eq(es(Logic.describeRelative(NOW - 1000, NOW)), "reiniciando…")
    h.eq(es(Logic.describeRelative(NOW, NOW)), "reiniciando…")
    h.eq(en(Logic.describeRelative(NOW, NOW)), "resetting…")
  end)
  -- nil, no cadena vacía: el descriptor ausente es lo que le dice al servicio
  -- que no hay nada que pintar, y render() lo convierte en "".
  h.test("sin fecha no hay descriptor", function()
    h.eq(Logic.describeRelative(nil, NOW), nil)
    h.eq(es(Logic.describeRelative(nil, NOW)), "")
  end)
end)

h.describe("describeAbsolute", function()
  h.test("hoy es solo la hora", function()
    h.eq(es(Logic.describeAbsolute(ms(2026, 8, 7, 19, 30), NOW)), "a las 19:30")
    h.eq(en(Logic.describeAbsolute(ms(2026, 8, 7, 19, 30), NOW)), "at 19:30")
  end)
  h.test("mañana lleva prefijo", function()
    h.eq(es(Logic.describeAbsolute(ms(2026, 8, 8, 7, 0), NOW)), "mañana a las 07:00")
    h.eq(en(Logic.describeAbsolute(ms(2026, 8, 8, 7, 0), NOW)), "tomorrow at 07:00")
  end)
  h.test("dentro de la semana usa el día", function()
    -- 2026-08-10 es lunes
    h.eq(es(Logic.describeAbsolute(ms(2026, 8, 10, 7, 0), NOW)), "el lunes a las 07:00")
    h.eq(en(Logic.describeAbsolute(ms(2026, 8, 10, 7, 0), NOW)), "on Monday at 07:00")
  end)
  -- El orden día/mes es de la lengua, y por eso viajan sueltos: el mismo
  -- descriptor da "20/8" en español y "8/20" en inglés.
  h.test("más allá de una semana usa la fecha, en el orden de cada lengua", function()
    h.eq(es(Logic.describeAbsolute(ms(2026, 8, 20, 7, 0), NOW)), "el 20/8 a las 07:00")
    h.eq(en(Logic.describeAbsolute(ms(2026, 8, 20, 7, 0), NOW)), "on 8/20 at 07:00")
  end)
  h.test("una fecha pasada no tiene descriptor", function()
    h.eq(Logic.describeAbsolute(ms(2026, 8, 6, 7, 0), NOW), nil)
  end)
  h.test("sin fecha no hay descriptor", function()
    h.eq(Logic.describeAbsolute(nil, NOW), nil)
  end)
end)

h.describe("formatAge", function()
  h.test("por debajo del minuto, en segundos", function()
    h.eq(Logic.formatAge(NOW - 3000, NOW), "3 s")
    h.eq(Logic.formatAge(NOW, NOW), "0 s")
    h.eq(Logic.formatAge(NOW - 59000, NOW), "59 s")
  end)
  h.test("minutos, horas y días", function()
    h.eq(Logic.formatAge(NOW - 12 * 60000, NOW), "12 min")
    h.eq(Logic.formatAge(NOW - (2 * 60 + 5) * 60000, NOW), "2 h 5 min")
    h.eq(Logic.formatAge(NOW - 3 * 3600000, NOW), "3 h")
    h.eq(Logic.formatAge(NOW - (2 * 24 + 4) * 3600000, NOW), "2 d 4 h")
    h.eq(Logic.formatAge(NOW - 2 * 24 * 3600000, NOW), "2 d")
  end)
  -- El reloj puede ir hacia atrás (NTP, suspensión). Un pie que diga
  -- "hace -4 min" es peor que uno que diga "hace 0 s".
  h.test("un instante futuro no pinta negativos", function()
    h.eq(Logic.formatAge(NOW + 60000, NOW), "0 s")
  end)
  h.test("sin fecha devuelve cadena vacía", function()
    h.eq(Logic.formatAge(nil, NOW), "")
  end)
  -- La confusión que motivó esta función: describeRelative mira hacia adelante.
  h.test("describeRelative NO sirve para un instante pasado", function()
    h.eq(es(Logic.describeRelative(NOW - 3 * 60000, NOW)), "reiniciando…")
  end)
end)

h.describe("describeMoney", function()
  -- El importe se monta con format.decimal y format.money, así que el MISMO
  -- descriptor sale "2,40 $" en español y "$2.40" en inglés.
  local function amount(m, cat): string
    local text = if m.cents then `{m.whole}{cat["format.decimal"]}{m.cents}` else m.whole
    return (string.gsub(string.gsub(cat["format.money"], "{amount}", text),
                        "{symbol}", m.symbol))
  end

  h.test("el separador y el lado del símbolo son de la lengua", function()
    h.eq(amount(Logic.describeMoney(240, 2, "USD"), T.es), "2,40 $")
    h.eq(amount(Logic.describeMoney(240, 2, "USD"), T.en), "$2.40")
    h.eq(amount(Logic.describeMoney(3000, 2, "EUR"), T.es), "30,00 €")
  end)
  h.test("las piezas salen partidas", function()
    local m = Logic.describeMoney(240, 2, "USD")
    h.eq(m.whole, "2")
    h.eq(m.cents, "40")
    h.eq(m.symbol, "$")
  end)
  h.test("una divisa desconocida usa su propio código", function()
    h.eq(amount(Logic.describeMoney(100, 2, "GBP"), T.es), "1,00 GBP")
  end)
  h.test("un exponente inválido cae a 2", function()
    h.eq(amount(Logic.describeMoney(240, nil, "USD"), T.es), "2,40 $")
    h.eq(amount(Logic.describeMoney(240, -1, "USD"), T.es), "2,40 $")
    h.eq(amount(Logic.describeMoney(240, 2.5, "USD"), T.es), "2,40 $") -- blindaje del ledger
  end)
  -- Con exponente 0 no hay punto que partir: sin céntimos y sin separador
  -- colgando (el yen y el franco CFA son así).
  h.test("un exponente 0 no deja separador suelto", function()
    local m = Logic.describeMoney(1200, 0, "JPY")
    h.eq(m.whole, "1200")
    h.eq(m.cents, nil)
    h.eq(amount(m, T.es), "1200 JPY")
  end)
  h.test("importe ausente es cero", function()
    h.eq(amount(Logic.describeMoney(nil, 2, "USD"), T.es), "0,00 $")
  end)
end)

h.finish()

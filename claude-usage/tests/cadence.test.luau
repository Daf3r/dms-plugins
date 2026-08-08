local h = require("./harness")
local Logic = require("../logic")

h.describe("nextInterval", function()
  h.test("reposo y alerta usan sus bases", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 0,
      idleInterval = 300, alertInterval = 60 }), 300)
    h.eq(Logic.nextInterval({ warning = true, failures = 0,
      idleInterval = 300, alertInterval = 60 }), 60)
  end)

  h.test("el backoff dobla por fallo hasta el techo", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 1,
      idleInterval = 300, alertInterval = 60 }), 600)
    h.eq(Logic.nextInterval({ warning = false, failures = 2,
      idleInterval = 300, alertInterval = 60 }), 1200)
    h.eq(Logic.nextInterval({ warning = false, failures = 3,
      idleInterval = 300, alertInterval = 60 }), 1800) -- techo
    h.eq(Logic.nextInterval({ warning = false, failures = 9,
      idleInterval = 300, alertInterval = 60 }), 1800)
  end)

  -- La corrección que costó la Task 9b de Caelestia. No reintroducir.
  h.test("un fallo NUNCA sondea más rápido que la base del usuario", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 1,
      idleInterval = 3600, alertInterval = 60 }), 3600)
  end)

  h.test("la base del usuario se respeta aunque supere el techo", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 0,
      idleInterval = 3600, alertInterval = 60 }), 3600)
  end)

  -- El ajuste ausente va aparte: un `nil` dentro de un constructor de tabla
  -- deja un hueco que la iteración generalizada se salta, así que en la lista
  -- de abajo nunca se probaría.
  h.test("un intervalo ausente cae al default del spec", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 0,
      alertInterval = 60 }), 300)
    h.eq(Logic.nextInterval({ warning = true, failures = 0,
      idleInterval = 300 }), 60)
  end)

  h.test("entrada basura cae al default del spec, no al suelo", function()
    for _, bad in { 0, -5, 0 / 0, math.huge, "300", {}, true } :: any do
      h.eq(Logic.nextInterval({ warning = false, failures = 0,
        idleInterval = bad, alertInterval = 60 }), 300, `idleInterval={tostring(bad)}`)
    end
  end)

  h.test("el suelo protege de una base minúscula", function()
    h.eq(Logic.nextInterval({ warning = true, failures = 0,
      idleInterval = 300, alertInterval = 1 }), 15)
  end)
end)

h.describe("toMilliseconds", function()
  h.test("convierte segundos a la unidad del host", function()
    h.eq(Logic.toMilliseconds(300), 300000)
  end)
end)

h.finish()

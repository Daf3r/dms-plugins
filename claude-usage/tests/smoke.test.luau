local h = require("./harness")
local Logic = require("../logic")

h.describe("arnés", function()
  h.test("logic.luau se puede importar y expone SEVERITY_RANK", function()
    h.eq(Logic.SEVERITY_RANK.critical, 2)
  end)
end)

h.finish()

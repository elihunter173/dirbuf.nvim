local function test(mod)
  describe(mod, require(mod).test)
end

describe("", function()
  test "dirbuf"
  test "dirbuf.planner"
end)

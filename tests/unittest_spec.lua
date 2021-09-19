local function test(mod)
  describe(mod, require(mod).test)
end

test "dirbuf.parser"
test "dirbuf.planner"

local function test(mod)
  describe(mod, require(mod).test)
end

test "dirbuf"
test "dirbuf.planner"

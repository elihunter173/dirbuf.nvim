local fs = require("dirbuf.fs")

local M = {}

-- Given the current state of the directory, `old_state`, and the desired new
-- state of the directory, `new_state`, determine the most efficient series of
-- actions necessary to reach the desired state.
--
-- old_state: Map from file hash to current state of file
-- new_state: Map from file hash to list of new associated fstate
function M.determine_plan(fstates, transformations)
  local plan = {}

  for hash, dst_fstates in pairs(transformations) do
    if hash == "" then
      -- New hash, so it's a new file
      for _, fstate in ipairs(dst_fstates) do
        table.insert(plan, {type = "create", fstate = fstate})
      end

    elseif next(dst_fstates) == nil then
      -- Graph goes nowhere
      table.insert(plan, {type = "delete", fstate = fstates[hash]})

    else
      -- We just use fname because we can move across
      local current_fname = fstates[hash].fname
      -- Try to find the current fname in the list of new_fnames. If it's
      -- there, then we can do nothing. If it's not there, then we copy the
      -- file n - 1 times and then move for the last file.
      local one_unchanged = false
      for _, dst_fstate in ipairs(dst_fstates) do
        if current_fname == dst_fstate.fname then
          one_unchanged = true
          break
        end
      end

      if one_unchanged then
        for _, dst_fstate in ipairs(dst_fstates) do
          if current_fname ~= dst_fstate.fname then
            table.insert(plan, {
              type = "copy",
              old_fname = current_fname,
              new_fname = dst_fstate.fname,
            })
          end
        end

      else
        local first = true
        local move_to
        for _, dst_fstate in ipairs(dst_fstates) do
          -- The first fstate gets special treatment as a move
          if first then
            move_to = dst_fstate
            first = false
          else
            table.insert(plan, {
              type = "copy",
              old_fname = current_fname,
              new_fname = dst_fstate.fname,
            })
          end
        end
        table.insert(plan, {
          type = "move",
          old_fname = current_fname,
          new_fname = move_to.fname,
        })
      end
    end
  end

  return plan
end

function M.execute_plan(plan)
  -- TODO: Make this async
  -- TODO: Check that all actions are valid before taking any action?
  -- determine_plan should only generate valid plans
  for _, action in ipairs(plan) do
    fs[action.type](action)
  end
end

function M.test()
  local fst = fs.FState.from_dispname

  describe("determine_plan", function()
    it("no changes", function()
      local fstates = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("a")}, b = {fst("b")}}
      assert.same({}, M.determine_plan(fstates, changes))
    end)

    it("rename one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("c")}, b = {fst("b")}}
      local correct_plan = {{type = "move", old_fname = "a", new_fname = "c"}}
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("delete one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {}, b = {fst("b")}}
      local correct_plan = {{type = "delete", fstate = fst("a")}}
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("copy one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("a"), fst("c")}, b = {fst("b")}}
      local correct_plan = {{type = "copy", old_fname = "a", new_fname = "c"}}
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("dependent renames", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("b")}, b = {fst("c")}}
      local correct_plan = {
        {type = "move", old_fname = "b", new_fname = "c"},
        {type = "move", old_fname = "a", new_fname = "b"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("difficult example", function()
      local identities = {a = fst("a"), b = fst("b"), c = fst("c")}
      local changes = {a = {fst("b"), fst("d")}, b = {fst("c")}, c = {fst("a")}}
      local correct_plan = {
        {type = "move", old_fname = "a", new_fname = "d"},
        {type = "move", old_fname = "c", new_fname = "a"},
        {type = "move", old_fname = "b", new_fname = "c"},
        {type = "copy", old_fname = "d", new_fname = "c"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)
  end)
end

return M

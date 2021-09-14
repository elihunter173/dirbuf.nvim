local fs = require("dirbuf.fs")

local M = {}

-- Given the current state of the directory, `changes`, and a map describing
-- the changes, `changes`, determine the most efficient series of actions
-- necessary to reach the desired state.
--
-- fstates: Map from FState hash to current FState of file.
-- new_state: Map from FState hash to list of new associated FStates. Empty
-- hash means new lit
function M.determine_plan(fstates, changes)
  local plan = {}

  for hash, dst_fstates in pairs(changes) do
    if hash == "" then
      -- New hash, so it's a new file
      for _, fstate in ipairs(dst_fstates) do
        table.insert(plan, {type = "create", fstate = fstate})
      end

    elseif next(dst_fstates) == nil then
      -- Graph goes nowhere
      table.insert(plan, {type = "delete", fstate = fstates[hash]})

    else
      -- Graph goes 1 to many places

      local current_path = fstates[hash].path
      -- Try to find the current path in the list of destinaton fstates
      -- (dst_fstates). If it's there, then we can do nothing. If it's not
      -- there, then we copy the file n - 1 times and then move for the last
      -- file.
      local one_unchanged = false
      for _, dst_fstate in ipairs(dst_fstates) do
        if current_path == dst_fstate.path then
          one_unchanged = true
          break
        end
      end

      if one_unchanged then
        for _, dst_fstate in ipairs(dst_fstates) do
          if current_path ~= dst_fstate.path then
            table.insert(plan, {
              type = "copy",
              old_path = current_path,
              new_path = dst_fstate.path,
            })
          end
        end

      else
        -- All names have changed
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
              old_path = current_path,
              new_path = dst_fstate.path,
            })
          end
        end
        table.insert(plan, {
          type = "move",
          old_path = current_path,
          new_path = move_to.path,
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
    fs.actions[action.type](action)
  end
end

function M.test()
  local fst = fs.FState.from_dispname

  describe("determine_plan", function()
    it("no changes", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("a")}, b = {fst("b")}}
      assert.same({}, M.determine_plan(identities, changes))
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

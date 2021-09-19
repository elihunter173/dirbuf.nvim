local api = vim.api

local parse_line = require("dirbuf.parser").parse_line
local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

local CURRENT_BUFFER = 0

-- TODO: Make this so it just works off of a previous dirbuf and a new lines?
function M.build_changes(buf)
  -- Parse the dirbuf into
  local fstates = api.nvim_buf_get_var(buf, "dirbuf")
  local dir = api.nvim_buf_get_name(buf)

  -- Map from hash to fnames associated with that hash
  local transition_graph = {}
  transition_graph[""] = {}
  for hash, _ in pairs(fstates) do
    transition_graph[hash] = {}
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  for lnum, line in ipairs(api.nvim_buf_get_lines(CURRENT_BUFFER, 0, -1, true)) do
    local err, dispname, hash = parse_line(line)
    if err ~= nil then
      return string.format("line %d: %s", dir, lnum, err)
    end
    local new_fstate = FState.from_dispname(dispname, dir)

    if used_fnames[new_fstate.fname] ~= nil then
      return string.format("line %d: duplicate name '%s'", lnum, dispname)
    end
    if hash ~= nil and fstates[hash].ftype ~= new_fstate.ftype then
      return string.format("line %d: cannot change ftype %s -> %s", lnum,
                           fstates[hash].ftype, new_fstate.ftype)
    end

    if hash == nil then
      table.insert(transition_graph[""], new_fstate)
    else
      table.insert(transition_graph[hash], new_fstate)
    end
    used_fnames[new_fstate.fname] = true
  end

  return nil, fstates, transition_graph
end

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
    local err = fs.actions[action.type](action)
    if err ~= nil then
      return err
    end
  end
  return nil
end

function M.test()
  local function fst(dispname)
    return fs.FState.from_dispname(dispname, "")
  end

  describe("determine_plan", function()
    it("no changes", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("a")}, b = {fst("b")}}
      assert.same({}, M.determine_plan(identities, changes))
    end)

    it("rename one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("c")}, b = {fst("b")}}
      local correct_plan = {{type = "move", old_path = "/a", new_path = "/c"}}
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
      local correct_plan = {{type = "copy", old_path = "/a", new_path = "/c"}}
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("dependent renames", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("b")}, b = {fst("c")}}
      local correct_plan = {
        {type = "move", old_path = "/b", new_path = "/c"},
        {type = "move", old_path = "/a", new_path = "/b"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("difficult example", function()
      local identities = {a = fst("a"), b = fst("b"), c = fst("c")}
      local changes = {a = {fst("b"), fst("d")}, b = {fst("c")}, c = {fst("a")}}
      local correct_plan = {
        {type = "move", old_path = "/a", new_path = "/d"},
        {type = "move", old_path = "/c", new_path = "/a"},
        {type = "move", old_path = "/b", new_path = "/c"},
        {type = "copy", old_path = "/d", new_path = "/c"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)
  end)
end

return M

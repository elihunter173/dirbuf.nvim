local api = vim.api

local parse_line = require("dirbuf.parser").parse_line
local fs = require("dirbuf.fs")
local FState = fs.FState
local create, copy, delete, move = fs.plan.create, fs.plan.copy, fs.plan.delete,
                                   fs.plan.move

local M = {}

local CURRENT_BUFFER = 0

-- Type definitions --
-- I wish teal had better language server support but alas
--[[
local Changes = {
  new_files = {FState},
  change_map = {string: Change},
}
local record Change
   -- dst_fstates
   {FState}
   current_fstate: FState
   stays: bool
   progress: Progress
end
local enum Progress
  "unhandled"
  "handling"
  "handled"
end
--]]

-- TODO: Make this so it just works off of a previous dirbuf and a dst lines?
function M.build_changes(buf)
  -- Parse the dirbuf into
  local dirbuf = api.nvim_buf_get_var(buf, "dirbuf")
  local dir = api.nvim_buf_get_name(buf)

  local new_files = {}
  local change_map = {}
  for _, fstate in pairs(dirbuf) do
    change_map[fstate.fname] = {
      current_fstate = fstate,
      stays = false,
      handled = false,
    }
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  -- Go through every line and build changes
  for lnum, line in ipairs(api.nvim_buf_get_lines(CURRENT_BUFFER, 0, -1, true)) do
    local err, dispname, hash = parse_line(line)
    if err ~= nil then
      return string.format("Line %d: %s", dir, lnum, err)
    end
    local dst_fstate = FState.from_dispname(dispname, dir)

    if used_fnames[dst_fstate.fname] ~= nil then
      return string.format("Line %d: Duplicate name '%s'", lnum, dispname)
    end

    if hash == nil then
      table.insert(new_files, dst_fstate)

    else
      local current_fstate = dirbuf[hash]
      if current_fstate.ftype ~= dst_fstate.ftype then
        return string.format("line %d: cannot change ftype %s -> %s", lnum,
                             current_fstate.ftype, dst_fstate.ftype)
      end

      if current_fstate.fname == dst_fstate.fname then
        change_map[current_fstate.fname].stays = true
      else
        table.insert(change_map[current_fstate.fname], dst_fstate)
      end
    end
    used_fnames[dst_fstate.fname] = true
  end

  return nil, {change_map = change_map, new_files = new_files}
end

local function resolve_change(plan, change_map, change)
  if change.progress == "handled" then
    return
  elseif change.progress == "handling" then
    error("unhandled cycle detected")
  end

  change.progress = "handling"

  local current_path = change.current_fstate.path

  -- TODO: Maybe it would be simpler to handle a few trivial cases first?

  -- If there's a cycle, we need to "unstick" it by moving one file to a
  -- temporary location. However, we need to remember to move that temporary
  -- file back to where we want after everything else in the cycle has been
  -- resolved.
  --
  -- It's not obvious that we can get away with only returning one action.
  -- However, due to our guarantee that the `Changes` we're given only use each
  -- `fname` once (i.e. the max in-degree of the graph of filename changes is
  -- 1), we know that we can only ever have one cycle from any given starting
  -- point.
  local post_resolution_action = nil

  -- If the file doesn't stay, we prevent an extra copy by moving the file
  -- as the last change. We arbitrarily pick the first file to move it after
  -- everything
  local move_to = nil
  local stuck_fstate = nil
  for _, dst in ipairs(change) do
    local dependent_change = change_map[dst.fname]
    if dependent_change ~= nil then
      if dependent_change.progress == "handling" then
        -- We have a cycle, we need to unstick it
        if stuck_fstate ~= nil then
          error("my assumption about `stuck_change` was wrong")
        end
        -- We handle this later
        stuck_fstate = dst
        goto continue

      else
        -- We can handle the dependent_change directly
        -- Double check that my assumption holds
        local rtn = resolve_change(plan, change_map, dependent_change)
        if rtn ~= nil and post_resolution_action ~= nil then
          error("my assumption about `post_resolution_action` was wrong")
        end
        post_resolution_action = rtn
      end
    end

    if not change.stays and move_to == nil then
      move_to = dst
    else
      table.insert(plan, copy(current_path, dst.path))
    end

    ::continue::
  end

  local gone = false
  if move_to ~= nil then
    table.insert(plan, move(current_path, move_to.path))
    gone = true
  end

  if stuck_fstate ~= nil then
    if move_to ~= nil then
      -- We have a safe place to copy from
      post_resolution_action = copy(move_to.path, stuck_fstate.path)

    elseif change.stays then
      -- We have a safe place to copy from
      post_resolution_action = copy(current_path, stuck_fstate.path)

    else
      -- We have NO safe place to copy from and we don't stay, so move to a
      -- temporary and then move again
      local temppath = fs.temppath()
      table.insert(plan, move(current_path, temppath))
      post_resolution_action = move(temppath, stuck_fstate.path)
      gone = true
    end
  end

  -- The file gets deleted and we never moved it, so we have to directly delete
  -- it
  if not change.stays and not gone then
    table.insert(plan, delete(change.current_fstate))
  end

  change.progress = "handled"
  return post_resolution_action
end

-- Given the set of `changes` we have, which is described as a map from
-- `current_fname`s to `Change`s, determine the most efficient series of
-- actions necessary to reach the desired progress.
function M.determine_plan(changes)
  local plan = {}

  for current_fname, change in pairs(changes.change_map) do
    -- Empty fname means new file. We handle creating files later.
    if current_fname ~= "" then
      local extra_action = resolve_change(plan, changes.change_map, change)
      if extra_action ~= nil then
        table.insert(plan, extra_action)
      end
    end
  end

  -- Create all the new files
  for _, fstate in ipairs(changes.new_files) do
    table.insert(plan, create(fstate))
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
    return FState.from_dispname(dispname, "")
  end

  -- Monkeypatch fs.temppath for testing
  local TEMP = "$TEMP"
  fs.temppath = function()
    return TEMP
  end

  local function apply_plan(fake_fs, plan)
    for _, action in ipairs(plan) do
      if action.type == "create" then
        fake_fs[action.fstate.path] = ""
      elseif action.type == "copy" then
        fake_fs[action.dst_path] = fake_fs[action.src_path]
      elseif action.type == "delete" then
        fake_fs[action.fstate.path] = nil
      elseif action.type == "move" then
        fake_fs[action.dst_path] = fake_fs[action.src_path]
        fake_fs[action.src_path] = nil
      end
    end
  end

  local function opcount(plan, op)
    local count = 0
    for _, action in ipairs(plan) do
      if action.type == op then
        count = count + 1
      end
    end
    return count
  end

  describe("determine_plan", function()
    it("no changes", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {current_fstate = fst("a"), stays = true, progress = "unhandled"},
          b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/a"] = "a", ["/b"] = "b"}, fake_fs)
      assert.same(0, #plan)
    end)

    it("move one", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {
            fst("c"),
            current_fstate = fst("a"),
            stays = false,
            progress = "unhandled",
          },
          b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/c"] = "a", ["/b"] = "b"}, fake_fs)
      assert.same(1, #plan)
    end)

    it("delete one", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {current_fstate = fst("a"), stays = false, progress = "unhandled"},
          b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/b"] = "b"}, fake_fs)
      assert.same(1, #plan)
    end)

    it("create one", function()
      local plan = M.determine_plan {
        new_files = {fst("a")},
        change_map = {
          b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
        },
      }

      local fake_fs = {["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/a"] = "", ["/b"] = "b"}, fake_fs)
      assert.same(1, #plan)
    end)

    it("copy one", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {
            fst("c"),
            current_fstate = fst("a"),
            stays = true,
            progress = "unhandled",
          },
          b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/a"] = "a", ["/b"] = "b", ["/c"] = "a"}, fake_fs)
      assert.same(1, #plan)
    end)

    it("dependent rename", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {
            fst("b"),
            current_fstate = fst("a"),
            stays = false,
            progress = "unhandled",
          },
          b = {
            fst("c"),
            current_fstate = fst("b"),
            stays = false,
            progress = "unhandled",
          },
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/b"] = "a", ["/c"] = "b"}, fake_fs)
      assert.same(2, #plan)
      assert.same(2, opcount(plan, "move"))
    end)

    it("simple cycle", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {
            fst("b"),
            current_fstate = fst("a"),
            stays = false,
            progress = "unhandled",
          },
          b = {
            fst("c"),
            current_fstate = fst("b"),
            stays = false,
            progress = "unhandled",
          },
          c = {
            fst("a"),
            current_fstate = fst("c"),
            stays = false,
            progress = "unhandled",
          },
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b", ["/c"] = "c"}
      apply_plan(fake_fs, plan)
      assert.same({["/a"] = "c", ["/b"] = "a", ["/c"] = "b"}, fake_fs)
      assert.same(4, #plan)
      assert.same(4, opcount(plan, "move"))
    end)

    -- TODO: We skip the "efficient breakpoint" tests because Dirbuf sometimes
    -- misses efficient breakpoints. Dirbuf's solutions are always correct but
    -- not always optimal.
    pending("swap with efficient breakpoint", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {
            fst("b"),
            current_fstate = fst("a"),
            stays = false,
            progress = "unhandled",
          },
          b = {
            fst("a"),
            fst("c"),
            current_fstate = fst("b"),
            stays = false,
            progress = "unhandled",
          },
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b"}
      apply_plan(fake_fs, plan)
      assert.same({["/a"] = "b", ["/b"] = "a", ["/c"] = "b"}, fake_fs)
      assert.same(3, #plan)
      assert.same(3, opcount(plan, "move"))
    end)

    pending("cycle with efficient breakpoint", function()
      local plan = M.determine_plan {
        new_files = {},
        change_map = {
          a = {
            fst("b"),
            current_fstate = fst("a"),
            stays = false,
            progress = "unhandled",
          },
          b = {
            fst("c"),
            fst("d"),
            current_fstate = fst("b"),
            stays = false,
            progress = "unhandled",
          },
          c = {
            fst("a"),
            current_fstate = fst("c"),
            stays = false,
            progress = "unhandled",
          },
        },
      }

      local fake_fs = {["/a"] = "a", ["/b"] = "b", ["/c"] = "c"}
      apply_plan(fake_fs, plan)
      assert.same({["/a"] = "c", ["/b"] = "a", ["/c"] = "b", ["/d"] = "b"},
                  fake_fs)
      assert.same(4, #plan)
      assert.same(3, opcount(plan, "move"))
      assert.same(1, opcount(plan, "copy"))
    end)

  end)
end

return M

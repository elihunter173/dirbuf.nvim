local uv = vim.loop

local M = {}

local function errorf(...)
  error(string.format(...))
end

-- Given the current state of the directory, `old_state`, and the desired new
-- state of the directory, `new_state`, determine the most efficient series of
-- actions necessary to reach the desired state.
--
-- old_state: Map from file hash to current state of file
-- new_state: Map from file hash to list of new associated fstate
function M.determine_plan(fstates, transformation_graph)
  -- TODO: Keep ftype around in plan. Or maybe entire fstates
  local plan = {}

  for hash, fnames in pairs(transformation_graph) do
    if hash == "" then
      -- New hash, so it's a new file
      for _, fstate in ipairs(fnames) do
        table.insert(plan, {type = "create", fstate = fstate})
      end

    elseif next(fnames) == nil then
      -- Graph goes nowhere
      table.insert(plan, {type = "delete", fname = fstates[hash].fname})

    else
      local current_fname = fstates[hash].fname
      -- Try to find the current fname in the list of new_fnames. If it's
      -- there, then we can do nothing. If it's not there, then we copy the
      -- file n - 1 times and then move for the last file.
      local one_unchanged = false
      for _, new_fname in ipairs(fnames) do
        if current_fname == new_fname then
          one_unchanged = true
          break
        end
      end

      if one_unchanged then
        for _, new_fname in ipairs(fnames) do
          if current_fname ~= new_fname then
            table.insert(plan, {
              type = "copy",
              old_fname = current_fname,
              new_fname = new_fname,
            })
          end
        end

      else
        -- TODO: This is gross as fuck
        local cursor, move_to = next(fnames)
        while true do
          local new_fname
          cursor, new_fname = next(fnames, cursor)
          if cursor == nil then
            break
          end
          table.insert(plan, {
            type = "copy",
            old_fname = current_fname,
            new_fname = new_fname,
          })
        end
        table.insert(plan, {
          type = "move",
          old_fname = current_fname,
          new_fname = move_to,
        })
      end
    end
  end

  return plan
end

local DEFAULT_MODE = tonumber("644", 8)

function M.execute_plan(plan)
  -- Apply those actions
  -- TODO: Make this async
  -- TODO: Check that all actions are valid before taking any action?
  -- determine_plan should only generate valid plans
  for _, action in ipairs(plan) do
    if action.type == "create" then
      local fstate = action.fstate
      -- TODO: Combine these
      if fstate.ftype == "file" then
        if uv.fs_access(fstate.fname, "W") then
          errorf("file at '%s' already exists", fstate.fname)
        end
        -- append instead of write to be non-destructive
        local ok = uv.fs_open(fstate.fname, "a", DEFAULT_MODE)
        if not ok then
          errorf("create failed: %s", fstate.fname)
        end
      elseif fstate.ftype == "directory" then
        if uv.fs_access(fstate.fname, "W") then
          errorf("directory at '%s' already exists", fstate.fname)
        end
        local ok = uv.fs_mkdir(fstate.fname, DEFAULT_MODE)
        if not ok then
          errorf("create failed: %s", fstate.fname)
        end
      else
        errorf("unsupported ftype: %s", fstate.ftype)
      end

    elseif action.type == "copy" then
      -- TODO: Support copying directories
      local ok = uv.fs_copyfile(action.old_fname, action.new_fname, nil)
      if not ok then
        errorf("copy failed: %s -> %s", action.old_fname, action.new_fname)
      end

    elseif action.type == "delete" then
      -- TODO: Support deleting directories
      local ok = uv.fs_unlink(action.fname)
      if not ok then
        errorf("delete failed: %s", action.fname)
      end

    elseif action.type == "move" then
      -- TODO: This is a TOCTOU
      if uv.fs_access(action.new_fname, "W") then
        errorf("file at '%s' already exists", action.new_fname)
      end
      local ok = uv.fs_rename(action.old_fname, action.new_fname)
      if not ok then
        errorf("move failed: %s -> %s", action.old_fname, action.new_fname)
      end

    else
      error("unknown action")
    end
  end
end

return M

local uv = vim.loop

local M = {}

local function errorf(...)
  error(string.format(...), 2)
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

  for hash, dst_fstates in pairs(transformation_graph) do
    if hash == "" then
      -- New hash, so it's a new file
      for _, fstate in ipairs(dst_fstates) do
        table.insert(plan, {type = "create", fstate = fstate})
      end

    elseif next(dst_fstates) == nil then
      -- Graph goes nowhere
      -- TODO: Switch on type of fstate
      table.insert(plan, {type = "delete", fstate = fstates[hash]})

    else
      -- TODO: Switch on type of fstate
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
        -- TODO: This is gross as fuck
        local first = true
        local move_to
        for _, dst_fstate in ipairs(dst_fstates) do
          if first then
            -- The first fstate gets special treatment as a move
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

local DEFAULT_MODE = tonumber("644", 8)

local function rmdir(dir)
  local handle = uv.fs_scandir(dir)
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    local path = dir .. "/" .. fname

    local ok
    if ftype == "directory" then
      ok = rmdir(path)
    elseif ftype == "file" then
      ok = uv.fs_unlink(path)
    else
      error("unsupported filetype")
    end
    if not ok then
      return ok
    end
  end
  return uv.fs_rmdir(dir)
end

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
        -- TODO: This is a TOCTOU
        if uv.fs_access(fstate.fname, "W") then
          errorf("file at '%s' already exists", fstate.fname)
        end
        -- append instead of write to be non-destructive
        local ok = uv.fs_open(fstate.fname, "a", DEFAULT_MODE)
        if not ok then
          errorf("create failed: %s", fstate.fname)
        end
      elseif fstate.ftype == "directory" then
        -- TODO: This is a TOCTOU
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
      -- TODO: Support copying directories. Needs keeping around fstates
      local ok = uv.fs_copyfile(action.old_fname, action.new_fname, nil)
      if not ok then
        errorf("copy failed: %s -> %s", action.old_fname, action.new_fname)
      end

    elseif action.type == "delete" then
      -- TODO: Print out error message
      if action.fstate.ftype == "file" then
        local ok = uv.fs_unlink(action.fname)
        if not ok then
          errorf("delete failed: %s", action.fname)
        end
      elseif action.fstate.ftype == "directory" then
        local ok = rmdir(action.fstate.fname)
        if not ok then
          errorf("delete failed: %s", action.fstate.fname)
        end
      else
        error("delete failed: unsupported ftype")
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

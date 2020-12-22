local uv = vim.loop

local M = {}

-- Given the current state of the directory, `old_state`, and the desired new
-- state of the directory, `new_state`, determine the most efficient series of
-- actions necessary to reach the desired state.
--
-- old_state: Map from file hash to current state of file
-- new_state: Map from file hash to list of new associated fstate
function M.determine_plan(identities, transformation_graph)
  local plan = {}

  for hash, fnames in pairs(transformation_graph) do
    if next(fnames) == nil then
      -- Graph goes nowhere
      table.insert(plan, {
        type = "delete",
        fname = identities[hash].fname,
      })

    else
      local current_fname = identities[hash].fname
      -- Try to find the current fname in the list of new_fnames. If it's
      -- there, then we can do nothing. If it's not there, then we copy the
      -- file n - 1 times and then move for the last file.
      local one_unchanged = false
      for _, new_fname in pairs(fnames) do
        if current_fname == new_fname then
          one_unchanged = true
          break
        end
      end

      if one_unchanged then
        for _, new_fname in pairs(fnames) do
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

function M.execute_plan(plan)
  -- Apply those actions
  -- TODO: Make this async
  -- TODO: Check that all actions are valid before taking any action?
  -- determine_plan should only generate valid plans
  for _, action in pairs(plan) do
    if action.type == "copy" then
      local ok = uv.fs_copyfile(action.old_fname, action.new_fname, nil)
      assert(ok)

    elseif action.type == "delete" then
      local ok = uv.fs_unlink(action.fname)
      assert(ok)

    elseif action.type == "move" then
      -- TODO: This is a TOCTOU
      if uv.fs_access(action.new_fname, "W") then
        error(string.format("file at '%s' already exists", action.new_fname))
      end
      local ok = uv.fs_rename(action.old_fname, action.new_fname)
      assert(ok)

    else
      error("unknown action")
    end
  end
end

return M

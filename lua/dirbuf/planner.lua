local buffer = require("dirbuf.buffer")
local fs = require("dirbuf.fs")

local FSEntry = fs.FSEntry
local create, copy, delete, move = fs.plan.create, fs.plan.copy, fs.plan.delete, fs.plan.move

local M = {}

--[[
local record Changes
  new_files: {FSEntry},
  change_map: {string: Change},
}
local record Change
   {FSEntry} -- dst_fs_entries
   current_fs_entry: FSEntry
   stays: bool
   progress: Progress
end
local enum Progress
  "unhandled"
  "handling"
  "handled"
end
--]]

-- `build_changes` creates a diff between the snapshotted state of the
-- directory buffer `dirbuf` and the updated state of the directory buffer
-- `lines`.
--
-- TODO: It's kinda gross that I just store `lines` because then I have to deal
-- with parsing here, but I'm not sure of a better way to do it
--
-- Returns: err, changes
function M.build_changes(dir, fs_entries, lines)
  local new_files = {}
  local change_map = {}
  for _, fs_entry in pairs(fs_entries) do
    change_map[fs_entry.fname] = {
      current_fs_entry = fs_entry,
      stays = false,
      handled = false,
    }
  end

  -- No duplicate fnames
  local used_fnames = {}
  for lnum, line in ipairs(lines) do
    local err, hash, fname, ftype = buffer.parse_line(line)
    if err ~= nil then
      return string.format("Line %d: %s", lnum, err)
    end
    if fname == nil then
      goto continue
    end

    if used_fnames[fname] ~= nil then
      return string.format("Line %d: Duplicate name '%s'", lnum, fname)
    end

    local dst_fs_entry = FSEntry.new(fname, dir, ftype)

    if hash == nil then
      table.insert(new_files, dst_fs_entry)
    else
      local current_fs_entry = fs_entries[hash]
      if current_fs_entry.ftype ~= dst_fs_entry.ftype then
        return string.format("line %d: cannot change %s -> %s", lnum, current_fs_entry.ftype, dst_fs_entry.ftype)
      end

      if current_fs_entry.fname == dst_fs_entry.fname then
        change_map[current_fs_entry.fname].stays = true
      else
        table.insert(change_map[current_fs_entry.fname], dst_fs_entry)
      end
    end
    used_fnames[dst_fs_entry.fname] = true

    ::continue::
  end

  return nil, { change_map = change_map, new_files = new_files }
end

-- TODO: Currently we don't always find the optimal unsticking point
-- Also, sorry this is hard to read...
local function resolve_change(plan, change_map, change)
  if change.progress == "handled" then
    return
  elseif change.progress == "handling" then
    error("unhandled cycle detected")
  end

  change.progress = "handling"

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
  local stuck_fs_entry = nil
  for _, dst_fs_entry in ipairs(change) do
    local dependent_change = change_map[dst_fs_entry.fname]
    if dependent_change ~= nil then
      if dependent_change.progress == "handling" then
        -- We have a cycle, we need to unstick it
        if stuck_fs_entry ~= nil then
          error("my assumption about `stuck_change` was wrong")
        end
        -- We handle this later
        stuck_fs_entry = dst_fs_entry
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
      move_to = dst_fs_entry
    else
      table.insert(plan, copy(change.current_fs_entry, dst_fs_entry))
    end

    ::continue::
  end

  local gone = false
  if move_to ~= nil then
    table.insert(plan, move(change.current_fs_entry, move_to))
    gone = true
  end

  if stuck_fs_entry ~= nil then
    if move_to ~= nil then
      -- We have a safe place to copy from
      post_resolution_action = copy(move_to, stuck_fs_entry)
    elseif change.stays then
      -- We have a safe place to copy from
      post_resolution_action = copy(change.current_fs_entry, stuck_fs_entry)
    else
      -- We have NO safe place to copy from and we don't stay, so move to a
      -- temporary and then move again
      local temp_fs_entry = FSEntry.temp(change.current_fs_entry.ftype)
      table.insert(plan, move(change.current_fs_entry, temp_fs_entry))
      post_resolution_action = move(temp_fs_entry, stuck_fs_entry)
      gone = true
    end
  end

  -- The file gets deleted and we never moved it, so we have to directly delete
  -- it
  if not change.stays and not gone then
    table.insert(plan, delete(change.current_fs_entry))
  end

  change.progress = "handled"
  return post_resolution_action
end

-- `determine_plan` finds the most efficient sequence of actions necessary to
-- apply the set of validated changes we have `changes`.
--
-- Returns: list of actions as in fs.plan
function M.determine_plan(changes)
  local plan = {}

  for _, change in pairs(changes.change_map) do
    local extra_action = resolve_change(plan, changes.change_map, change)
    if extra_action ~= nil then
      table.insert(plan, extra_action)
    end
  end

  for _, fs_entry in ipairs(changes.new_files) do
    table.insert(plan, create(fs_entry))
  end

  return plan
end

-- `execute_plan` executes the plan (i.e. sequence of actions) as created by
-- `determine_plan` using the `fs.actions` action handlers.
--
-- Returns: err
function M.execute_plan(plan)
  -- TODO: Make this async
  for _, action in ipairs(plan) do
    local err = fs.actions[action.type](action)
    if err ~= nil then
      return err
    end
  end
  return nil
end

return M

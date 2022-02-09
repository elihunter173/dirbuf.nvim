local buffer = require("dirbuf.buffer")
local fs = require("dirbuf.fs")

local FState = fs.FState
local create, copy, delete, move = fs.plan.create, fs.plan.copy, fs.plan.delete,
                                   fs.plan.move

local M = {}

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

-- TODO: I wish I didn't just store lines, but I'm not sure how to better do it
function M.build_changes(dirbuf, lines)
  local new_files = {}
  local change_map = {}
  for _, fstate in pairs(dirbuf.fstates) do
    change_map[fstate.fname] = {
      current_fstate = fstate,
      stays = false,
      handled = false,
    }
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  -- Go through every line and build changes
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

    local dst_fstate = FState.new(fname, dirbuf.dir, ftype)

    if hash == nil then
      table.insert(new_files, dst_fstate)

    else
      local current_fstate = dirbuf.fstates[hash]
      if current_fstate.ftype ~= dst_fstate.ftype then
        return string.format("line %d: cannot change %s -> %s", lnum,
                             current_fstate.ftype, dst_fstate.ftype)
      end

      if current_fstate.fname == dst_fstate.fname then
        change_map[current_fstate.fname].stays = true
      else
        table.insert(change_map[current_fstate.fname], dst_fstate)
      end
    end
    used_fnames[dst_fstate.fname] = true

    ::continue::
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
  for _, dst_fstate in ipairs(change) do
    local dependent_change = change_map[dst_fstate.fname]
    if dependent_change ~= nil then
      if dependent_change.progress == "handling" then
        -- We have a cycle, we need to unstick it
        if stuck_fstate ~= nil then
          error("my assumption about `stuck_change` was wrong")
        end
        -- We handle this later
        stuck_fstate = dst_fstate
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
      move_to = dst_fstate
    else
      table.insert(plan, copy(change.current_fstate, dst_fstate))
    end

    ::continue::
  end

  local gone = false
  if move_to ~= nil then
    table.insert(plan, move(change.current_fstate, move_to))
    gone = true
  end

  if stuck_fstate ~= nil then
    if move_to ~= nil then
      -- We have a safe place to copy from
      post_resolution_action = copy(move_to, stuck_fstate)

    elseif change.stays then
      -- We have a safe place to copy from
      post_resolution_action = copy(change.current_fstate, stuck_fstate)

    else
      -- We have NO safe place to copy from and we don't stay, so move to a
      -- temporary and then move again
      local temp_fstate = FState.temp(change.current_fstate.ftype)
      table.insert(plan, move(change.current_fstate, temp_fstate))
      post_resolution_action = move(temp_fstate, stuck_fstate)
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
  for _, action in ipairs(plan) do
    local err = fs.actions[action.type](action)
    if err ~= nil then
      return err
    end
  end
  return nil
end

return M

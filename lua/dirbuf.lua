local api = vim.api
local uv = vim.loop

local md5 = require("vendor.md5")

local M = {}

local log = {
  error = function(msg, ...)
    api.nvim_err_writeln(string.format(msg, ...))
  end,
}

local HASH_LEN = 7
local function parse_line(line)
  local fname, hash = line:match("^'([^']+)'%s*#(%x%x%x%x%x%x%x)$")
  return fname, hash
end

function M.debug()
  print(vim.inspect(vim.b.dirbuf))
end

function M.println(lineno)
  local line = vim.fn.getline(lineno)
  local _, hash = parse_line(line)
  print(hash .. " = " .. vim.inspect(vim.b.dirbuf.file_info[hash]))
end

-- TODO: I need to determine how to save the previous cdpath and restore it when the dirbuf is exited
-- TODO: Conditionally split based on whether bang is there or not. Or do I even want this?
-- TODO: Name the buffer after the directory
function M.open(dir)
  if dir == "" then
    dir = "."
  end

  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    log.error(err)
    return
  end

  local buf = api.nvim_create_buf(true, false)
  assert(buf ~= 0)

  -- Fill out buffer
  -- TODO: Maybe add a ../ at the top? Not sold in the idea
  local buf_lines = {}
  local file_info = {}
  local max_len = 0
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    -- TODO: Should I actually modify the fname like this?
    if ftype == "directory" then
      fname = fname .. "/"
    elseif ftype == "link" then
      fname = fname .. "@"
    end

    -- TODO: Maybe don't always quote like this?
    local line = vim.fn.shellescape(fname)
    local hash = md5.sumhexa(fname):sub(1, HASH_LEN)
    file_info[hash] = {
      fname = fname,
      ftype = ftype,
    }
    table.insert(buf_lines, {line, nil, "  #"..hash})
    if #line > max_len then
      max_len = #line
    end
  end
  for key, tuple in pairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[key] = table.concat(tuple)
  end
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)

  -- Add keymaps
  -- TODO: Should this be an ftplugin? Probably...
  api.nvim_buf_set_keymap(buf, "n", "<CR>", "<cmd>lua require('dirbuf').enter()<cr>", {noremap = true, silent = true})
  api.nvim_buf_set_keymap(buf, "n", "gd",   "<cmd>DirbufPrintln<cr>", {noremap = true, silent = true})

  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)

  api.nvim_buf_set_name(buf, "dirbuf://" .. vim.fn.fnamemodify(dir, ":p"))

  -- This needs to be after we iterate over the dirs
  api.nvim_command("silent cd " .. dir)

  -- Buffer is finished. Show it
  api.nvim_win_set_buf(0, buf)

  -- Has to be after we focus the buffer
  vim.b.dirbuf = {
    file_info = file_info,
  }
end

function M.enter()
  -- TODO: Is there a better way to do this?
  local line = vim.fn.getline(".")
  local fname, hash = parse_line(line)
  assert(vim.b.dirbuf.file_info[hash].ftype == "directory")
  M.open(fname)
end

local ACTION = {
  MOVE = 1,
  DELETE = 2,
}

-- Given the current state of the directory, `old_state`, and the desired new
-- state of the directory, `new_state`, determine the most efficient series of
-- actions necessary to reach the desired state.
--
-- old_state: Map from file hash to current state of file
-- new_state: Map from file hash to list of new associated fstate
local function determine_plan(current_state, desired_state)
  local plan = {}

  for hash, fstates in pairs(desired_state) do
    if #fstates == 0 then
      table.insert(plan, {
        type = ACTION.DELETE,
        fname = current_state[hash],
      })

    elseif #fstates == 1 then
      -- TODO: Generalize when we're renaming and copying multiple files
      local current_fname = current_state[hash].fname
      local new_fname = fstates[1]
      if current_fname ~= new_fname then
        table.insert(plan, {
          type = ACTION.MOVE,
          fname = new_fname,
        })
      end

    else
      log.error("not yet supported")
      return nil
    end
  end

  return plan
end

local function execute_plan(plan)
  -- Apply those actions
  -- TODO: Make this async
  -- TODO: Check that all actions are valid before taking any action
  for _, action in pairs(plan) do
    if action.type == ACTION.MOVE then
      if uv.fs_access(action.new_fname, "W") then
        log.error("file at '%s' already exists", action.new_fname)
        return
      end
      local ok = uv.fs_rename(action.old_fname, action.new_fname)
      assert(ok)

    elseif action.type == ACTION.DELETE then
      local ok = uv.fs_unlink(action.fname)
      assert(ok)

    else
      log.error("unknown action")
      return false
    end
  end
  return true
end

-- TODO: Figure out rules for how competing deletes, renames, and copies work.
-- Maybe need a temp directory to make them "atomic"?
function M.sync()
  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local current_state = vim.b.dirbuf.file_info

  -- Map from hash to fnames associated with that hash
  local desired_state = {}
  for hash, _ in pairs(current_state) do
    desired_state[hash] = {}
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  for _, line in pairs(api.nvim_buf_get_lines(0, 0, -1, true)) do
    local fname, hash = parse_line(line)

    if used_fnames[fname] ~= nil then
      log.error("duplicate filename '%s'", fname)
      return
    end

    table.insert(desired_state[hash], fname)
    used_fnames[fname] = true
  end

  local plan = determine_plan(current_state, desired_state)
  if plan == nil then
    return
  end
  local ok = execute_plan(plan)
  if not ok then
    return
  end

  -- TODO: Reload the buffer
  api.nvim_buf_set_option(0, "modified", false)
end

return M

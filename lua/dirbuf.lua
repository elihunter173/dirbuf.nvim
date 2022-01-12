local api = vim.api
local uv = vim.loop

local config = require("dirbuf.config")
local fs = require("dirbuf.fs")
local FState = fs.FState
local parser = require("dirbuf.parser")
local planner = require("dirbuf.planner")

local M = {}

local CURRENT_BUFFER = 0

-- fill_dirbuf fills buffer `buf` with the contents of its corresponding
-- directory. `buf` must have the name of a valid directory and its contents
-- must be a valid dirbuf.
--
-- If `on_dispname` is set, then the cursor will be put on the line
-- corresponding to `on_dispname`.
--
-- Returns: err
local function fill_dirbuf(buf, on_dispname)
  local dir = api.nvim_buf_get_name(buf)
  local show_hidden = api.nvim_buf_get_var(buf, "dirbuf_show_hidden")

  local err, dirbuf = parser.create_dirbuf(dir, show_hidden)
  if err ~= nil then
    return err
  end

  local buf_lines, max_len = parser.write_dirbuf(dirbuf)
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", dirbuf)
  api.nvim_buf_set_option(buf, "tabstop", max_len + config.get("hash_padding"))

  if on_dispname ~= nil then
    for lnum, line in ipairs(buf_lines) do
      if line:sub(1, #on_dispname) == on_dispname then
        api.nvim_win_set_cursor(0, {lnum, 0})
        break
      end
    end
  end

  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)

  return nil
end

function M.setup(opts)
  local err = config.update(opts)
  if err ~= nil then
    api.nvim_err_writeln("dirbuf.setup: " .. err)
  end
end

-- Convert a directory path to its absolute path and a non-directory path into
-- the absolute path of its parent directory
local function directify(path)
  if vim.fn.isdirectory(path) == 1 then
    return vim.fn.fnamemodify(path, ":p")
  else
    -- Return the path with the head (i.e. file) stripped off
    return vim.fn.fnamemodify(path, ":h:p")
  end
end

local function set_dirbuf_opts(buf)
  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  local ok, _ = pcall(api.nvim_buf_get_var, buf, "dirbuf_show_hidden")
  if not ok then
    api.nvim_buf_set_var(buf, "dirbuf_show_hidden", config.get("show_hidden"))
  end
end

-- This buffer must be the currently focused buffer
function M.edit_dirbuf(buf, name)
  local dir = directify(name)
  api.nvim_buf_set_name(buf, dir)

  set_dirbuf_opts(buf)
  fill_dirbuf(buf)
end

function M.open(path)
  if path == "" then
    path = "."
  end
  local dir = directify(path)

  -- Find dispname of current path
  local dispname = nil
  local current_path = vim.fn.expand("%")
  if current_path ~= "" then
    local stat, err = uv.fs_lstat(current_path)
    if stat == nil then
      api.nvim_err_writeln(err)
      return
    end

    local resolved_path
    resolved_path, err = uv.fs_realpath(current_path)
    local fname = vim.fn.fnamemodify(resolved_path, ":t")
    dispname = fs.fname_to_dispname(fname, stat.type)
  end

  local buf = vim.fn.bufnr("^" .. dir .. "$")
  if buf == -1 then
    buf = api.nvim_create_buf(true, false)
    if buf == 0 then
      api.nvim_err_writeln("Failed to create buffer")
      return
    end
    api.nvim_buf_set_name(buf, dir)
    set_dirbuf_opts(buf)
  end

  api.nvim_win_set_buf(0, buf)
  fill_dirbuf(buf, dispname)
end

function M.enter()
  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local line = api.nvim_get_current_line()
  local err, _, hash = parser.line(line)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  local fname = vim.b.dirbuf.fstates[hash].fname

  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    api.nvim_err_writeln(string.format(
                             "Cannot enter '%s'. Dirbuf must be saved first",
                             fname))
    return
  end

  -- We rely on the autocmd to open directories
  vim.cmd("silent edit " .. vim.fn.fnameescape(fs.join(dir, fname)))
end

-- Ensure that the directory has not changed since our last snapshot
local function check_dirbuf(buf)
  local dir = api.nvim_buf_get_name(buf)
  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    return err
  end

  local dirbuf = api.nvim_buf_get_var(buf, "dirbuf")
  local show_hidden = api.nvim_buf_get_var(buf, "dirbuf_show_hidden")
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if show_hidden and fname:sub(1, 1) == "." then
      goto continue
    end

    local fstate = FState.new(fname, dir, ftype)
    local snapshot = dirbuf.fstates[fstate:hash()]
    if snapshot == nil or snapshot.fname ~= fname or snapshot.ftype ~= ftype then
      return
          "Snapshot out of date with current directory. Run :edit! to refresh"
    end

    ::continue::
  end

  return nil
end

function M.sync()
  if not api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    return
  end

  local err = check_dirbuf(CURRENT_BUFFER)
  if err ~= nil then
    api.nvim_err_writeln("Cannot save dirbuf: " .. err)
    return
  end

  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local changes
  err, changes = planner.build_changes(CURRENT_BUFFER)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  local plan = planner.determine_plan(changes)
  err = planner.execute_plan(plan)
  if err ~= nil then
    api.nvim_err_writeln("Error making changes: " .. err)
    api.nvim_err_writeln(
        "WARNING: Dirbuf in inconsistent state. Run :edit! to refresh")
    return
  end

  -- We want to ensure that we are still hovering on the same line
  local dispname
  err, dispname, _ = parser.line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  fill_dirbuf(CURRENT_BUFFER, dispname)
end

function M.toggle_hide()
  vim.b.dirbuf_show_hidden = not vim.b.dirbuf_show_hidden
  -- We want to ensure that we are still hovering on the same line
  local err, dispname, _ = parser.line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  fill_dirbuf(CURRENT_BUFFER, dispname)
end

return M

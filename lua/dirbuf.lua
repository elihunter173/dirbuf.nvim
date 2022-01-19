local api = vim.api
local uv = vim.loop

local buffer = require("dirbuf.buffer")
local config = require("dirbuf.config")
local fs = require("dirbuf.fs")
local planner = require("dirbuf.planner")

local M = {}

local CURRENT_BUFFER = 0

-- fill_dirbuf fills buffer `buf` with the contents of its corresponding
-- directory. `buf` must have the name of a valid directory and its contents
-- must be a valid dirbuf.
--
-- If `on_fname` is set, then the cursor will be put on the line corresponding
-- to `on_fname`.
--
-- Returns: err
local function fill_dirbuf(buf, on_fname)
  local dir, err = uv.fs_realpath(api.nvim_buf_get_name(buf))
  if dir == nil then
    return err
  end

  local show_hidden = api.nvim_buf_get_var(buf, "dirbuf_show_hidden")

  local dirbuf
  err, dirbuf = buffer.create_dirbuf(dir, show_hidden)
  if err ~= nil then
    return err
  end

  local buf_lines, max_len, fname_line = buffer.write_dirbuf(dirbuf, on_fname)
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", dirbuf)
  api.nvim_buf_set_option(buf, "tabstop", max_len + config.get("hash_padding"))

  if fname_line ~= nil then
    api.nvim_win_set_cursor(0, {fname_line, 0})
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

local function set_dirbuf_opts(buf)
  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  local ok, _ = pcall(api.nvim_buf_get_var, buf, "dirbuf_show_hidden")
  if not ok then
    api.nvim_buf_set_var(buf, "dirbuf_show_hidden", config.get("show_hidden"))
  end
end

local function directify(path)
  if fs.is_directory(path) then
    return vim.fn.fnamemodify(path, ":p")
  else
    -- Return the path with the head (i.e. file) stripped off
    return vim.fn.fnamemodify(path, ":h:p")
  end
end

-- This buffer must be the currently focused buffer
function M.edit_dirbuf(buf, path)
  -- Vimscript hands us a string
  buf = tonumber(buf)
  local dir = directify(path)
  api.nvim_buf_set_name(buf, dir)

  set_dirbuf_opts(buf)
  fill_dirbuf(buf)
end

function M.open(path)
  if path == "" then
    path = "."
  end
  local dir = directify(path)

  -- Find fname of current path so we can position our cursor on it
  local current_path = vim.fn.expand("%")
  local current_fname
  if fs.is_directory(current_path) then
    -- Doing :t on a directory results in an empty string because of the
    -- trailing /, so we strip that off first with :h
    current_fname = vim.fn.fnamemodify(current_path, ":h:t")
  else
    current_fname = vim.fn.fnamemodify(current_path, ":t")
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
  fill_dirbuf(buf, current_fname)
end

function M.enter()
  local bufname = api.nvim_buf_get_name(CURRENT_BUFFER)
  local dir, err = uv.fs_realpath(bufname)
  if dir == nil then
    api.nvim_err_writeln(err)
    return
  end

  local line = api.nvim_get_current_line()
  local hash
  err, _, hash = buffer.parse_line(line)
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
  vim.cmd("silent edit " .. vim.fn.fnameescape(fs.join_paths(dir, fname)))
end

-- Ensure that the directory has not changed since our last snapshot
local function check_dirbuf(buf)
  local saved_dirbuf = api.nvim_buf_get_var(buf, "dirbuf")

  local dir, err = uv.fs_realpath(api.nvim_buf_get_name(buf))
  if dir == nil then
    return err
  end

  local show_hidden = api.nvim_buf_get_var(buf, "dirbuf_show_hidden")
  local current_dirbuf
  err, current_dirbuf = buffer.create_dirbuf(dir, show_hidden)
  if err ~= nil then
    return "Error while checking: " .. err
  end

  if not vim.deep_equal(saved_dirbuf, current_dirbuf) then
    return "Snapshot out of date with current directory. Run :edit! to refresh"
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
  local dirbuf = api.nvim_buf_get_var(CURRENT_BUFFER, "dirbuf")
  local lines = api.nvim_buf_get_lines(CURRENT_BUFFER, 0, -1, true)
  local changes
  err, changes = planner.build_changes(dirbuf, lines)
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
  err, dispname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  fill_dirbuf(CURRENT_BUFFER, fs.dispname_to_fname(dispname))
end

function M.toggle_hide()
  vim.b.dirbuf_show_hidden = not vim.b.dirbuf_show_hidden
  -- We want to ensure that we are still hovering on the same line
  local err, dispname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  fill_dirbuf(CURRENT_BUFFER, fs.dispname_to_fname(dispname))
end

return M

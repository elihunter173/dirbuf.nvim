local api = vim.api
local uv = vim.loop

local buffer = require("dirbuf.buffer")
local config = require("dirbuf.config")
local fs = require("dirbuf.fs")
local planner = require("dirbuf.planner")

local M = {}

local CURRENT_BUFFER = 0
local CURRENT_WINDOW = 0

function M.setup(opts)
  local err = config.update(opts)
  if err ~= nil then
    api.nvim_err_writeln("dirbuf.setup: " .. err)
  end
end

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
    api.nvim_win_set_cursor(CURRENT_WINDOW, {fname_line, 0})
  end

  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)

  return nil
end

local function set_dirbuf_opts(buf)
  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  local ok, _ = pcall(api.nvim_buf_get_var, buf, "dirbuf_show_hidden")
  if not ok then
    api.nvim_buf_set_var(buf, "dirbuf_show_hidden", config.get("show_hidden"))
  end
end

local function normalize_dir(path)
  path = vim.fn.simplify(path)
  -- On Windows, simplify keeps the path_separator on directories
  if path:sub(-1, -1) == fs.path_separator then
    return vim.fn.fnamemodify(path, ":h")
  end
  return path
end

local function path_in_dir(dir, path)
  return dir == vim.fn.fnamemodify(path, ":h")
end

function M.on_bufenter()
  local path = normalize_dir(api.nvim_buf_get_name(CURRENT_BUFFER))

  local should_update_dirbuf = not api.nvim_buf_get_option(CURRENT_BUFFER,
                                                           "modified") and
                                   fs.is_directory(path)
  if should_update_dirbuf then
    local altbuf = vim.fn.bufnr("#")

    api.nvim_buf_set_name(CURRENT_BUFFER, path)

    local cursor_fname = nil
    local last_path = vim.w.dirbuf_last_path
    if last_path ~= nil and path_in_dir(path, last_path) then
      cursor_fname = vim.fn.fnamemodify(last_path, ":t")
    end

    set_dirbuf_opts(CURRENT_BUFFER)
    if altbuf ~= -1 then
      vim.fn.setreg("#", altbuf)
    end
    local err = fill_dirbuf(CURRENT_BUFFER, cursor_fname)
    if err ~= nil then
      api.nvim_err_writeln(err)
      return
    end
  end

  api.nvim_win_set_var(CURRENT_WINDOW, "dirbuf_last_path", path)
end

local function directify(path)
  if fs.is_directory(path) then
    return vim.fn.fnamemodify(path, ":p")
  else
    -- Return the path with the head (i.e. file) stripped off
    return vim.fn.fnamemodify(path, ":h:p")
  end
end

function M.open(path)
  if path == "" then
    path = "."
  end
  path = normalize_dir(path)
  path = directify(path)

  local keepalt = ""
  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") == "dirbuf" then
    -- If we're leaving a dirbuf, keep our alternate buffer
    keepalt = "keepalt"
  end

  vim.cmd("silent " .. keepalt .. " edit " .. vim.fn.fnameescape(path))
  -- XXX: Neovim does not trigger our autocmd here so we manually execute it
  M.on_bufenter()
end

function M.enter()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end

  local dir = normalize_dir(api.nvim_buf_get_name(CURRENT_BUFFER))

  local line = api.nvim_get_current_line()
  local err, _, hash = buffer.parse_line(line)
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
  vim.cmd("silent keepalt edit " ..
              vim.fn.fnameescape(fs.join_paths(dir, fname)))
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

local function fmt_action(action)
  local function fmt_fstate(fstate)
    return vim.fn.shellescape(fs.FState.dispname(fstate))
  end

  if action.type == "create" then
    if action.fstate.ftype == "directory" then
      return "mkdir " .. fmt_fstate(action.fstate)
    else
      return "touch " .. fmt_fstate(action.fstate)
    end

  elseif action.type == "copy" then
    return "cp " .. fmt_fstate(action.src_fstate) .. " " ..
               fmt_fstate(action.dst_fstate)

  elseif action.type == "delete" then
    return "rm " .. fmt_fstate(action.fstate)

  elseif action.type == "move" then
    return "mv " .. fmt_fstate(action.src_fstate) .. " " ..
               fmt_fstate(action.dst_fstate)

  else
    error("Unrecognized action: " .. vim.inspect(action))
  end
end

function M.sync(opt)
  if opt == nil then
    opt = ""
  end

  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") ~= "dirbuf" then
    api.nvim_err_writeln(":DirbufSync only supports 'filetype=dirbuf'")
    return
  end

  if opt ~= "" and opt ~= "-dry-run" then
    api.nvim_err_writeln(":DirbufSync unrecognized option: " .. opt)
  end

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

  if opt == "-dry-run" then
    for _, action in ipairs(plan) do
      print(fmt_action(action))
    end

  else
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
    err = fill_dirbuf(CURRENT_BUFFER, fs.dispname_to_fname(dispname))
    if err ~= nil then
      api.nvim_err_writeln(err)
      return
    end
  end
end

function M.toggle_hide()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end

  vim.b.dirbuf_show_hidden = not vim.b.dirbuf_show_hidden
  -- We want to ensure that we are still hovering on the same line
  local err, dispname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  err = fill_dirbuf(CURRENT_BUFFER, fs.dispname_to_fname(dispname))
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
end

return M

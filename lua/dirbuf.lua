local api = vim.api

local buffer = require("dirbuf.buffer")
local config = require("dirbuf.config")
local fs = require("dirbuf.fs")
local planner = require("dirbuf.planner")

local M = {}

local CURRENT_BUFFER = 0
local CURRENT_WINDOW = 0

function M.setup(opts)
  local errors = config.update(opts)
  if #errors == 1 then
    api.nvim_err_writeln("dirbuf.setup: " .. errors[1])
  elseif #errors > 1 then
    api.nvim_err_writeln("dirbuf.setup:")
    for _, err in ipairs(errors) do
      api.nvim_err_writeln("    " .. err)
    end
  end
end

-- takes a path which could be a file, determines if the extension of the file
-- has been configured a handler in vim.b.dirbuf_file_handlers and returns the
-- handler if so, nil if no handler has been configured
local function get_file_handler(path)
  local extension = path:match("^.+%.(.+)$"):lower()
  local handler_config = config.get("file_handlers")
  if handler_config[extension] ~= nil then
    return tostring(handler_config[extension])
  end
  return nil
end

-- `normalize_path` takes a `path` entered by the user, potentially containing
-- duplicate path separators, "..", or trailing path separators, and ensures
-- that all duplicate path separators are removed, there is no trailing path
-- separator, and all ".."s are simplified. This does not resolve symlinks.
--
-- This exists to ensure that all paths are displayed in a consistent way and
-- to simplify path manipulation logic.
local function normalize_path(path)
  path = vim.fn.simplify(vim.fn.fnamemodify(path, ":p"))
  -- On Windows, simplify keeps the path_separator on directories
  if path:sub(-1, -1) == fs.path_separator then
    path = vim.fn.fnamemodify(path, ":h")
  end
  return path
end

-- `fill_dirbuf` fills the current buffer with the contents of its
-- corresponding directory. Note that the current buffer must have the name of
-- a valid directory.
--
-- If `on_fname` is set, then the cursor will be put on the line corresponding
-- to `on_fname`.
--
-- Returns: err
local function fill_dirbuf(on_fname)
  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local err, fs_entries = fs.get_fs_entries(dir, vim.b.dirbuf_show_hidden)
  if err ~= nil then
    return err
  end

  -- Before we set lines, we set undolevels to -1 so we delete the history when
  -- we set the lines. This prevents people going back to now-invalid hashes
  -- and potentially messing up their directory on accident
  local buf_lines, fname_line = buffer.write_fs_entries(fs_entries, on_fname)
  local undolevels = vim.bo.undolevels
  vim.bo.undolevels = -1
  api.nvim_buf_set_lines(CURRENT_BUFFER, 0, -1, true, buf_lines)
  vim.bo.undolevels = undolevels
  vim.b.dirbuf = fs_entries

  vim.bo.tabstop = #"#" + buffer.HASH_LEN + config.get("hash_padding")
  api.nvim_win_set_cursor(CURRENT_WINDOW, { fname_line or 1, #"#" + buffer.HASH_LEN + #"\t" })
  vim.bo.modified = false

  return nil
end

function M.init_dirbuf(history, history_index, update_history, from_path)
  -- Preserve altbuf
  local altbuf = vim.fn.bufnr("#")

  local path = normalize_path(vim.fn.expand("%"))
  api.nvim_buf_set_name(CURRENT_BUFFER, path)

  -- Determine where to place cursor
  -- We ignore errors in case the buffer is empty
  local _, _, cursor_fname, _ = buffer.parse_line(api.nvim_get_current_line())
  -- See if we're coming from a path below this dirbuf.
  if from_path ~= nil and vim.startswith(from_path, path) then
    -- Make sure we're clipping past the "/" in from_path
    local fname_start = #path + 1
    if path:sub(-1, -1) ~= fs.path_separator then
      fname_start = fname_start + 1
    end
    local last_path_separator = from_path:find(fs.path_separator, fname_start, true)
    if last_path_separator ~= nil then
      cursor_fname = from_path:sub(fname_start, last_path_separator - 1)
    else
      cursor_fname = from_path:sub(fname_start)
    end
  end

  -- Update history
  if history == nil then
    history = {}
    history_index = 0
  end
  if update_history then
    -- Clear old history
    while #history > history_index do
      table.remove(history)
    end
    -- We don't add to history if we're just refreshing the dirbuf
    if path ~= history[history_index] then
      table.insert(history, path)
      history_index = history_index + 1
    end
  end
  vim.b.dirbuf_history = history
  vim.b.dirbuf_history_index = history_index

  -- Set dirbuf options
  vim.bo.filetype = "dirbuf"
  vim.bo.buftype = "acwrite"
  vim.bo.bufhidden = "wipe"
  -- Normally unnecessary but sometimes other plugins make things unmodifiable,
  -- so we have to do this to prevent running into errors in fill_dirbuf
  vim.bo.modifiable = true

  -- Set "dirbuf_show_hidden" to default if it is unset
  if vim.b.dirbuf_show_hidden == nil then
    vim.b.dirbuf_show_hidden = config.get("show_hidden")
  end

  if altbuf ~= -1 then
    vim.fn.setreg("#", altbuf)
  end
  local err = fill_dirbuf(cursor_fname)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
end

function M.get_cursor_path()
  local err, _, fname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    error(err)
  end
  local dir = normalize_path(vim.fn.expand("%"))
  return fs.join_paths(dir, fname)
end

-- If `path` is a file, this returns the absolute path to its parent. Otherwise
-- it returns the absolute path of `path`.
local function directify(path)
  if fs.is_directory(path) then
    return vim.fn.fnamemodify(path, ":p")
  else
    return vim.fn.fnamemodify(path, ":h:p")
  end
end

function M.open(path)
  if path == "" then
    path = "."
  end
  path = normalize_path(directify(path))

  local from_path = normalize_path(vim.fn.expand("%"))
  if from_path == path then
    -- If we're not leaving, we want to keep the cursor on the same line
    local err, _, fname, _ = buffer.parse_line(api.nvim_get_current_line())
    if err ~= nil then
      api.nvim_err_writeln("Error placing cursor: " .. err)
      return
    end
    from_path = fs.join_paths(path, fname)
  end

  local keepalt = ""
  if vim.bo.filetype == "dirbuf" then
    -- If we're leaving a dirbuf, keep our alternate buffer
    keepalt = "keepalt"
  end
  local history, history_index = vim.b.dirbuf_history, vim.b.dirbuf_history_index
  vim.cmd(keepalt .. " noautocmd edit " .. vim.fn.fnameescape(path))
  M.init_dirbuf(history, history_index, true, from_path)
end

function M.enter(cmd)
  if cmd == nil then
    cmd = "edit"
  end

  if vim.bo.filetype ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end

  local err, _, fname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  if vim.bo.modified then
    api.nvim_err_writeln(string.format("Cannot enter '%s'. Dirbuf must be saved first", fname))
    return
  end

  local dir = normalize_path(vim.fn.expand("%"))
  local path = fs.join_paths(dir, fname)
  local noautocmd = ""
  if fs.is_directory(path) then
    noautocmd = "noautocmd"
  else
    local handler = get_file_handler(path)
    if handler ~= nil then
      cmd = handler
    end
  end
  local history, history_index = vim.b.dirbuf_history, vim.b.dirbuf_history_index
  vim.cmd("keepalt " .. noautocmd .. " " .. cmd .. " " .. vim.fn.fnameescape(path))
  if fs.is_directory(path) then
    M.init_dirbuf(history, history_index, true)
  end
end

function M.jump_history(n)
  if vim.bo.filetype ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end
  local history, history_index = vim.b.dirbuf_history, vim.b.dirbuf_history_index
  local next_index = math.max(1, math.min(#history, history_index + n))
  vim.cmd("keepalt noautocmd edit " .. vim.fn.fnameescape(history[next_index]))
  M.init_dirbuf(history, next_index, false, history[history_index])
end

function M.quit()
  if vim.bo.filetype ~= "dirbuf" then
    api.nvim_err_writeln(":DirbufQuit only supports 'filetype=dirbuf'")
    return
  end

  local altbuf = vim.fn.bufnr("#")
  if altbuf == -1 or altbuf == api.nvim_get_current_buf() then
    vim.cmd("bdelete")
  else
    api.nvim_set_current_buf(altbuf)
  end
end

-- Ensure that the directory has not changed since our last snapshot
local function check_dirbuf(buf)
  local dir = api.nvim_buf_get_name(buf)
  local err, current_fs_entries = fs.get_fs_entries(dir, vim.b.dirbuf_show_hidden)
  if err ~= nil then
    return "Error while checking: " .. err
  end

  if not vim.deep_equal(vim.b.dirbuf, current_fs_entries) then
    return "Snapshot out of date with current directory. Run :edit! to refresh"
  end

  return nil
end

-- print_plan() should only be called from dirbuf.sync()
local function print_plan(plan)
  local function fmt_fs_entry(fs_entry)
    return vim.fn.shellescape(buffer.display_fs_entry(fs_entry))
  end

  for _, action in ipairs(plan) do
    if action.type == "create" then
      if action.fs_entry.ftype == "directory" then
        print("mkdir " .. fmt_fs_entry(action.fs_entry))
      else
        print("touch " .. fmt_fs_entry(action.fs_entry))
      end
    elseif action.type == "copy" then
      print("cp " .. fmt_fs_entry(action.src_fs_entry) .. " " .. fmt_fs_entry(action.dst_fs_entry))
    elseif action.type == "delete" then
      print("rm " .. fmt_fs_entry(action.fs_entry))
    elseif action.type == "move" then
      print("mv " .. fmt_fs_entry(action.src_fs_entry) .. " " .. fmt_fs_entry(action.dst_fs_entry))
    else
      error("Unrecognized action: " .. vim.inspect(action))
    end
  end
end

-- do_plan() should only be called from dirbuf.sync()
local function do_plan(plan)
  local err = planner.execute_plan(plan)
  if err ~= nil then
    api.nvim_err_writeln("Error making changes: " .. err)
    api.nvim_err_writeln("WARNING: Dirbuf in inconsistent state. Run :edit! to refresh")
    return
  end

  -- Leave cursor on the same file
  local fname
  err, _, fname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  err = fill_dirbuf(fname)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
end

function M.sync(opt)
  if opt == nil then
    opt = ""
  end

  if vim.bo.filetype ~= "dirbuf" then
    api.nvim_err_writeln(":DirbufSync only supports 'filetype=dirbuf'")
    return
  end

  if opt ~= "" and opt ~= "-confirm" and opt ~= "-dry-run" then
    api.nvim_err_writeln(":DirbufSync unrecognized option: " .. opt)
  end

  if not vim.bo.modified then
    return
  end

  local err = check_dirbuf(CURRENT_BUFFER)
  if err ~= nil then
    api.nvim_err_writeln("Cannot save dirbuf: " .. err)
    return
  end

  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local lines = api.nvim_buf_get_lines(CURRENT_BUFFER, 0, -1, true)
  local changes
  err, changes = planner.build_changes(dir, vim.b.dirbuf, lines)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end

  local plan = planner.determine_plan(changes)

  if opt == "-confirm" then
    print_plan(plan)
    -- We pcall to make Ctrl-C work
    local ok, response = pcall(vim.fn.confirm, "Sync changes?", "&Yes\n&No", 2)
    if ok and response == 1 then
      do_plan(plan)
    end
  elseif opt == "-dry-run" then
    print_plan(plan)
  else
    do_plan(plan)
  end
end

function M.toggle_hide()
  if vim.bo.filetype ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end

  vim.b.dirbuf_show_hidden = not vim.b.dirbuf_show_hidden
  -- Leave cursor on the same file
  local err, _, fname, _ = buffer.parse_line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  err = fill_dirbuf(fname)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
end

return M

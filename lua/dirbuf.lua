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

-- `fill_dirbuf` fills the current buffer with the contents of its
-- corresponding directory. Note that the current buffer must have the name of
-- a valid directory.
--
-- If `on_fname` is set, then the cursor will be put on the line corresponding
-- to `on_fname`.
--
-- Returns: err
local function fill_dirbuf(on_fname)
  local dir, err = uv.fs_realpath(api.nvim_buf_get_name(CURRENT_BUFFER))
  if dir == nil then
    return err
  end

  local show_hidden = api.nvim_buf_get_var(CURRENT_BUFFER, "dirbuf_show_hidden")

  local dirbuf
  err, dirbuf = buffer.create_dirbuf(dir, show_hidden)
  if err ~= nil then
    return err
  end

  local hash_first = config.get("hash_first")
  local buf_lines, max_len, fname_line = buffer.write_dirbuf(dirbuf, { hash_first = hash_first }, on_fname)
  -- Before we set lines, we set undolevels to -1 so we delete the history when
  -- we set the lines. This prevents people going back to now-invalid hashes
  -- and potentially messing up their directory on accident
  local undolevels = api.nvim_buf_get_option(CURRENT_BUFFER, "undolevels")
  api.nvim_buf_set_option(CURRENT_BUFFER, "undolevels", -1)
  api.nvim_buf_set_lines(CURRENT_BUFFER, 0, -1, true, buf_lines)
  api.nvim_buf_set_option(CURRENT_BUFFER, "undolevels", undolevels)
  api.nvim_buf_set_var(CURRENT_BUFFER, "dirbuf", dirbuf)

  if hash_first then
    api.nvim_buf_set_option(CURRENT_BUFFER, "tabstop", #"#" + buffer.HASH_LEN + config.get("hash_padding"))
  else
    api.nvim_buf_set_option(CURRENT_BUFFER, "tabstop", max_len + config.get("hash_padding"))
  end

  local cursor_col = 0
  if hash_first then
    cursor_col = #"#" + buffer.HASH_LEN + #"\t"
  end
  api.nvim_win_set_cursor(CURRENT_WINDOW, { fname_line or 1, cursor_col })

  api.nvim_buf_set_option(CURRENT_BUFFER, "modified", false)

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
  path = vim.fn.simplify(path)
  -- On Windows, simplify keeps the path_separator on directories
  if path:sub(-1, -1) == fs.path_separator then
    path = vim.fn.fnamemodify(path, ":h")
  end
  return path
end

function M.init_dirbuf(from_path)
  local altbuf = vim.fn.bufnr("#")

  local path = normalize_path(api.nvim_buf_get_name(CURRENT_BUFFER))
  api.nvim_buf_set_name(CURRENT_BUFFER, path)

  -- Determine where to place cursor
  local cursor_fname = nil
  -- See if we're coming from a path below this dirbuf
  if from_path ~= nil and vim.startswith(from_path, path) then
    -- If path ends with path_separator, we don't need to clip past it
    local start
    if path:sub(-1, -1) == fs.path_separator then
      start = #path + 1
    else
      start = #path + 2
    end
    local last_path_separator = from_path:find(fs.path_separator, start, true)
    if last_path_separator ~= nil then
      cursor_fname = from_path:sub(start, last_path_separator - 1)
    else
      cursor_fname = from_path:sub(start)
    end
  end

  -- Set dirbuf options
  api.nvim_buf_set_option(CURRENT_BUFFER, "filetype", "dirbuf")
  api.nvim_buf_set_option(CURRENT_BUFFER, "buftype", "acwrite")
  api.nvim_buf_set_option(CURRENT_BUFFER, "bufhidden", "wipe")

  -- Set "dirbuf_show_hidden" to default if it is unset
  local ok, _ = pcall(api.nvim_buf_get_var, CURRENT_BUFFER, "dirbuf_show_hidden")
  if not ok then
    api.nvim_buf_set_var(CURRENT_BUFFER, "dirbuf_show_hidden", config.get("show_hidden"))
  end

  -- Re-init dirbuf preserving altbuf
  if altbuf ~= -1 then
    vim.fn.setreg("#", altbuf)
  end
  local err = fill_dirbuf(cursor_fname)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
end

local function get_cursor_fname()
  local err, _, fname, _ = buffer.parse_line(api.nvim_get_current_line(), {
    hash_first = config.get("hash_first"),
  })
  return err, fname
end

function M.get_cursor_path()
  local err, fname = get_cursor_fname()
  if err ~= nil then
    error(err)
  end
  local dir = normalize_path(api.nvim_buf_get_name(CURRENT_BUFFER))
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
  path = directify(normalize_path(path))

  local from_path = normalize_path(api.nvim_buf_get_name(CURRENT_BUFFER))
  if from_path == path then
    -- If we're not leaving, we want to keep the cursor on the same line
    local err, fname = get_cursor_fname()
    if err ~= nil then
      api.nvim_err_writeln("Error placing cursor: " .. err)
      return
    end
    from_path = fs.join_paths(path, fname)
  end

  local keepalt = ""
  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") == "dirbuf" then
    -- If we're leaving a dirbuf, keep our alternate buffer
    keepalt = "keepalt"
  end

  vim.cmd(keepalt .. " edit " .. vim.fn.fnameescape(path))
  M.init_dirbuf(from_path)
end

function M.enter(cmd)
  if cmd == nil then
    cmd = "edit"
  end

  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end

  local dir = normalize_path(api.nvim_buf_get_name(CURRENT_BUFFER))

  local err, fname = get_cursor_fname()
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    api.nvim_err_writeln(string.format("Cannot enter '%s'. Dirbuf must be saved first", fname))
    return
  end

  local path = fs.join_paths(dir, fname)
  vim.cmd("keepalt " .. cmd .. " " .. vim.fn.fnameescape(path))
  -- NOTE: Currently Neovim swallows errors in BufEnter autocmds, so this hack
  -- gets around that: https://github.com/neovim/neovim/issues/13711
  -- This code is also arguably correct outside of that issue since it means
  -- dirbuf.enter() on a directory will always open another dirbuf
  if fs.is_directory(path) then
    M.init_dirbuf()
  end
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

-- print_plan() should only be called from dirbuf.sync()
local function print_plan(plan)
  local function fmt_fstate(fstate)
    return vim.fn.shellescape(buffer.display_fstate(fstate))
  end

  for _, action in ipairs(plan) do
    if action.type == "create" then
      if action.fstate.ftype == "directory" then
        print("mkdir " .. fmt_fstate(action.fstate))
      else
        print("touch " .. fmt_fstate(action.fstate))
      end
    elseif action.type == "copy" then
      print("cp " .. fmt_fstate(action.src_fstate) .. " " .. fmt_fstate(action.dst_fstate))
    elseif action.type == "delete" then
      print("rm " .. fmt_fstate(action.fstate))
    elseif action.type == "move" then
      print("mv " .. fmt_fstate(action.src_fstate) .. " " .. fmt_fstate(action.dst_fstate))
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
  err, fname = get_cursor_fname()
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

  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") ~= "dirbuf" then
    api.nvim_err_writeln(":DirbufSync only supports 'filetype=dirbuf'")
    return
  end

  if opt ~= "" and opt ~= "-confirm" and opt ~= "-dry-run" then
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

  local dirbuf = api.nvim_buf_get_var(CURRENT_BUFFER, "dirbuf")
  local lines = api.nvim_buf_get_lines(CURRENT_BUFFER, 0, -1, true)
  local changes
  err, changes = planner.build_changes(dirbuf, lines, { hash_first = config.get("hash_first") })
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
  if api.nvim_buf_get_option(CURRENT_BUFFER, "filetype") ~= "dirbuf" then
    api.nvim_err_writeln("Operation only supports 'filetype=dirbuf'")
    return
  end

  vim.b.dirbuf_show_hidden = not vim.b.dirbuf_show_hidden
  -- Leave cursor on the same file
  local err, fname = get_cursor_fname()
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

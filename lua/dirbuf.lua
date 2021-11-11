local api = vim.api
local uv = vim.loop

local parser = require("dirbuf.parser")
local planner = require("dirbuf.planner")
local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

local CURRENT_BUFFER = 0

-- Default config settings
local config = {
  show_hidden = true,
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
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
  local dir = api.nvim_buf_get_name(buf)
  local show_hidden = api.nvim_buf_get_var(buf, "dirbuf_show_hidden")

  local move_cursor_to = nil

  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    return err
  end

  -- Fill out buffer
  -- Stores file info by hash
  local fstates = {}
  -- Stores (fname_esc, padding, hash) tuples which we will join into strings
  -- later to form the buffer's lines. We fill in the padding at the end to
  -- line up the hashes.
  local buf_lines = {}
  -- Used to we can make all the hashes line up
  local max_len = 0
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if not show_hidden and fname:sub(1, 1) == "." then
      goto continue
    end

    local fstate = FState.new(fname, dir, ftype)
    local hash = fstate:hash()
    if fstates[hash] ~= nil then
      -- This should never happen
      error(string.format("Colliding hashes '%s' with '%s' and '%s'", hash,
                          fstates[hash].path, fstate.path))
    end
    fstates[hash] = fstate

    local dispname = fstate:dispname()
    local dispname_esc = dispname:gsub("[ \\]", "\\%0"):gsub("\t", "\\t")
    if #dispname_esc > max_len then
      max_len = #dispname_esc
    end
    table.insert(buf_lines, {dispname_esc, nil, "  #" .. hash})

    if fstate.fname == on_fname then
      move_cursor_to = #buf_lines
    end

    ::continue::
  end
  -- Now fill in the padding in the (fname_esc, padding, hash) tuples with
  -- appropriate padding such that the hashes line up
  for idx, tuple in ipairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[idx] = table.concat(tuple)
  end
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", fstates)

  if move_cursor_to ~= nil then
    api.nvim_win_set_cursor(0, {move_cursor_to, 0})
  end

  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)

  return nil
end

local function normalize_dir(path)
  if vim.fn.isdirectory(path) == 1 then
    -- `dir .. "/"` fixes the issue where ".." appears in the filepath if you
    -- do dirbuf.open(".."), but it makes "/" become "//"
    if path ~= "/" then
      return vim.fn.fnamemodify(path .. "/", ":p")
    else
      return "/"
    end
  else
    -- Return the path with the head (i.e. file) stripped off
    return vim.fn.fnamemodify(path, ":h")
  end
end

local function set_dirbuf_opts(buf)
  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  local ok, _ = pcall(api.nvim_buf_get_var, buf, "dirbuf_show_hidden")
  if not ok then
    api.nvim_buf_set_var(buf, "dirbuf_show_hidden", config.show_hidden)
  end
end

-- This buffer must be the currently focused buffer
function M.edit_dirbuf(buf, name)
  local dir = normalize_dir(name)
  api.nvim_buf_set_name(buf, dir)

  set_dirbuf_opts(buf)
  fill_dirbuf(buf)
end

function M.open(path)
  if path == "" then
    path = "."
  end
  local dir = normalize_dir(path)

  -- This is really hard to understand. What I want is to get the current
  -- buffer's name and get the basepath of it. Ideally, expand("%:t") would
  -- work but if you are in a directory (ends with a /), then it returns
  -- nothing. Therefore, we have to do a hack to get the directory by looking
  -- at the parent, stripping the slash, and then getting the tail.
  local old_fname = vim.fn.expand("%:t")
  if old_fname == "" then
    old_fname = vim.fn.expand("%:p:h:t")
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
  fill_dirbuf(buf, old_fname)
end

function M.enter()
  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local line = api.nvim_get_current_line()
  local err, _, hash = parser.line(line)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  local fname = vim.b.dirbuf[hash].fname

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

  local fstates = api.nvim_buf_get_var(buf, "dirbuf")
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
    local snapshot = fstates[fstate:hash()]
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
  local fname = fs.dispname_to_fname(dispname)
  fill_dirbuf(CURRENT_BUFFER, fname)
end

function M.toggle_hide()
  vim.b.dirbuf_show_hidden = not vim.b.dirbuf_show_hidden
  -- We want to ensure that we are still hovering on the same line
  local err, dispname, _ = parser.line(api.nvim_get_current_line())
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  local fname = fs.dispname_to_fname(dispname)
  fill_dirbuf(CURRENT_BUFFER, fname)
end

return M

local api = vim.api
local uv = vim.loop

local md5 = require("vendor.md5")

local planner = require("dirbuf.planner")

local M = {}

local CURRENT_BUFFER = 0

-- TODO: Switch error handling to use error and pcall
local log = {
  error = function(...)
    api.nvim_err_writeln("Dirbuf: " .. string.format(...))
  end,
  warn = function(...)
    vim.cmd("echohl WarningMsg")
    vim.cmd("echom 'Dirbuf: " .. vim.fn.escape(string.format(...), "'") .. "'")
    vim.cmd("echohl None")
  end,
  debug = function(...)
    print(vim.inspect(...))
  end,
}

local function dbg(...)
  local local_names = {...}
  local name_idx = {}
  for idx, name in ipairs(local_names) do
    name_idx[name] = idx
  end

  local info = debug.getinfo(2)
  local prefix = string.format("%s:%d:", info.source:match("^.*/(.+)$"),
                               info.currentline)

  if #local_names > 1 then
    print(prefix)
    prefix = "  "
  end

  local lines = {}
  local index = 1
  while true do
    local var_name, var_value = debug.getlocal(2, index)
    if not var_name then
      break
    end
    if name_idx[var_name] ~= nil then
      lines[name_idx[var_name]] = vim.inspect(var_value)
    end
    index = index + 1
  end

  for idx, name in ipairs(local_names) do
    local valstr = lines[idx]
    if valstr == nil then
      print(prefix, "no such local `" .. name .. "`")
    else
      print(prefix, name, "=", valstr)
    end
  end
end

local HASH_LEN = 7
local function hash_fname(fname)
  return md5.sumhexa(fname):sub(1, HASH_LEN)
end
function M.parse_line(line)
  local string_builder = {}
  -- We store this in a local so we can skip characters
  local chars = line:gmatch(".")
  for c in chars do
    if c == " " then
      break

    elseif c == "\\" then
      local next_c = chars()
      if next_c == " " or next_c == "\\" then
        table.insert(string_builder, next_c)
      else
        error(string.format("invalid escape sequence '\\%s'", next_c))
      end

    else
      table.insert(string_builder, c)
    end
  end
  local fname = table.concat(string_builder)

  local hash = line:match("#(%x%x%x%x%x%x%x)$")
  return fname, hash
end

local function fill_dirbuf(buf)
  local dir = api.nvim_buf_get_name(buf)

  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    error(err)
  end
  -- Fill out buffer
  -- Stores file info by hash
  local file_info = {}
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

    -- Skip hidden files
    -- TODO: Make skipping hidden files more easily configurable
    if not vim.g.dirbuf_show_hidden and fname:match("^%.") then
      goto continue
    end

    -- TODO: Should I actually modify the fname like this?
    -- TODO: Do all classifiers from here
    -- https://unix.stackexchange.com/questions/82357/what-do-the-symbols-displayed-by-ls-f-mean#82358
    if ftype == "directory" then
      fname = fname .. "/"
    elseif ftype == "link" then
      fname = fname .. "@"
    end

    local hash = hash_fname(fname)
    assert(file_info[hash] == nil)
    file_info[hash] = {fname = fname, ftype = ftype}
    local fname_esc = vim.fn.fnameescape(fname)
    table.insert(buf_lines, {fname_esc, nil, "  #" .. hash})
    if #fname_esc > max_len then
      max_len = #fname_esc
    end

    ::continue::
  end
  -- Now fill in the padding in the (fname_esc, padding, hash) tuples with
  -- appropriate padding such that the hashes line up
  for key, tuple in pairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[key] = table.concat(tuple)
  end
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", file_info)

  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)
end

function M.open(dir)
  if dir == "" then
    dir = "."
  end
  -- XXX: `dir .. "/"` fixes issues with .. appearing in filepath if you do
  -- dirbuf.open(".."), but it makes '/' become '//'
  if dir ~= "/" then
    dir = vim.fn.fnamemodify(dir .. "/", ":p")
  end

  local old_buf = vim.fn.bufnr("^" .. dir .. "$")
  if old_buf ~= -1 then
    vim.cmd("buffer " .. old_buf)
    return
  end

  local buf = api.nvim_create_buf(true, false)
  assert(buf ~= 0)

  api.nvim_buf_set_name(buf, dir)

  fill_dirbuf(buf)

  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  -- We must first change buffers before we change the save the old directory
  -- and switch directories. That is because we use BufLeave to reset the
  -- current directory and we don't want to change the saved current directory
  -- when we go deeper into dirbufs. We cannot use api.nvim_win_set_buf(0, buf)
  -- because that doesn't trigger autocmds.
  vim.cmd("buffer " .. buf)
  local old_dir = uv.cwd()
  api.nvim_set_current_dir(dir)

  vim.cmd("augroup dirbuf_local")
  vim.cmd("  autocmd! * <buffer>")
  vim.cmd("  autocmd BufLeave <buffer> silent cd " ..
              vim.fn.fnameescape(old_dir))
  vim.cmd("  autocmd BufEnter <buffer> silent cd " .. vim.fn.fnameescape(dir))
  vim.cmd("  autocmd BufWriteCmd <buffer> lua require'dirbuf'.sync()")
  vim.cmd("augroup END")
end

function M.enter()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    log.error("dirbuf must be saved first")
    return
  end

  local line = api.nvim_get_current_line()
  local fname, hash = M.parse_line(line)
  local fstate = vim.b.dirbuf[hash]
  assert(fstate.fname == fname)
  if fstate.ftype == "directory" then
    M.open(fname)
  elseif fstate.ftype == "file" then
    vim.cmd("silent edit " .. vim.fn.fnameescape(fstate.fname))
  else
    error("currently unsupported filetype")
  end
end

function M.sync()
  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local current_state = vim.b.dirbuf

  -- Map from hash to fnames associated with that hash
  local transition_graph = {}
  for hash, _ in pairs(current_state) do
    transition_graph[hash] = {}
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  for lnum, line in pairs(api.nvim_buf_get_lines(0, 0, -1, true)) do
    local fname, hash = M.parse_line(line)
    if fname == nil then
      log.error("malformed line: %d", lnum)
      return
    end

    if used_fnames[fname] ~= nil then
      log.error("duplicate filename '%s'", fname)
      return
    end

    table.insert(transition_graph[hash], fname)
    used_fnames[fname] = true
  end

  local plan = planner.determine_plan(current_state, transition_graph)
  planner.execute_plan(plan)

  fill_dirbuf(CURRENT_BUFFER)
end

return M

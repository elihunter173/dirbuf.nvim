local api = vim.api
local uv = vim.loop

local md5 = require("dirbuf.md5")
local planner = require("dirbuf.planner")

local M = {}

local CURRENT_BUFFER = 0

local HASH_LEN = 7
local function hash_fname(fname)
  return md5.sumhexa(fname):sub(1, HASH_LEN)
end

-- The language of valid dirbuf lines is regular, so normally I would use a
-- regular expression. However, Lua doesn't have a proper regex engine, just
-- simpler patterns. These patterns can't parse dirbuf lines (b/c of escaping),
-- so I manually build the parser. It also gives nicer error messages.
function M.parse_line(line)
  local string_builder = {}
  -- We store this in a local so we can skip characters
  local chars = line:gmatch(".")

  -- Parse fname
  while true do
    local c = chars()
    if c == nil then
      -- Ended line in fname
      local fname = table.concat(string_builder)
      return fname, nil

    elseif c:match("%s") then
      break
    elseif c == "\\" then
      local next_c = chars()
      if next_c:match("%s") or next_c == "\\" then
        table.insert(string_builder, next_c)
      else
        error(string.format("invalid escape sequence '\\%s'", next_c))
      end
    else
      table.insert(string_builder, c)
    end
  end
  local fname = table.concat(string_builder)

  -- Skip to hash
  while true do
    local c = chars()
    if c == nil then
      error("unexpected end of line")
    elseif c == "#" then
      break
    elseif not c:match("%s") then
      error(string.format("unexpected character '%s'", c))
    end
  end

  -- Parse hash
  string_builder = {}
  for _ = 1, HASH_LEN do
    local c = chars()
    if c == nil then
      error("unexpected end of line")
    elseif not c:match("%x") then
      error(string.format("invalid hash character '%s'", c))
    else
      table.insert(string_builder, c)
    end
  end
  local hash = table.concat(string_builder)

  local c = chars()
  if c ~= nil then
    error(string.format("extra character '%s'", c))
  end

  return fname, hash
end

local function fill_dirbuf(buf)
  local dir = api.nvim_buf_get_name(buf)

  -- Used to preserve the ordering of lines. Each line is guaranteed to be used
  -- exactly once assuming the buffer contains no non-existent fnames.
  local fname_lnums = {}
  for lnum, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, true)) do
    local fname, _ = M.parse_line(line)
    fname_lnums[fname] = lnum
  end
  local tail = #fname_lnums + 1

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
    if file_info[hash] ~= nil then
      error(string.format("colliding hashes '%s'", hash))
    end
    file_info[hash] = {fname = fname, ftype = ftype}

    local fname_esc = vim.fn.fnameescape(fname)
    if #fname_esc > max_len then
      max_len = #fname_esc
    end
    local lnum = fname_lnums[fname]
    if lnum == nil then
      lnum = tail
      tail = tail + 1
    end
    buf_lines[lnum] = {fname_esc, nil, "  #" .. hash}

    ::continue::
  end
  -- Now fill in the padding in the (fname_esc, padding, hash) tuples with
  -- appropriate padding such that the hashes line up
  for idx, tuple in ipairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[idx] = table.concat(tuple)
  end
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", file_info)

  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)
end

local function clean_path(path)
  -- XXX: `dir .. "/"` fixes issues with .. appearing in filepath if you do
  -- dirbuf.open(".."), but it makes '/' become '//'
  if path ~= "/" then
    return vim.fn.fnamemodify(path .. "/", ":p")
  else
    return path
  end
end

-- This buffer must be the currently focused buffer
function M.init_dirbuf(buf)
  local dir = clean_path(api.nvim_buf_get_name(buf))
  api.nvim_buf_set_name(buf, dir)

  fill_dirbuf(buf)

  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

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

function M.open(dir)
  if dir == "" then
    dir = "."
  end
  dir = clean_path(dir)

  local old_buf = vim.fn.bufnr("^" .. dir .. "$")
  if old_buf ~= -1 then
    vim.cmd("buffer " .. old_buf)

  else
    local buf = api.nvim_create_buf(true, false)
    if buf == 0 then
      error("failed to create buffer")
    end
    api.nvim_buf_set_name(buf, dir)

    -- We must first change buffers before we change the save the old directory
    -- and switch directories. That is because we use BufLeave to reset the
    -- current directory and we don't want to change the saved current directory
    -- when we go deeper into dirbufs. We cannot use api.nvim_win_set_buf(0, buf)
    -- because that doesn't trigger autocmds.
    vim.cmd("buffer " .. buf)

    M.init_dirbuf(buf)
  end
end

function M.enter()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    error("dirbuf must be saved first")
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

local DEFAULT_MODE = tonumber("644", 8)

function M.sync()
  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local current_state = vim.b.dirbuf

  -- Map from hash to fnames associated with that hash
  local transition_graph = {}
  for hash, _ in pairs(current_state) do
    transition_graph[hash] = {}
  end

  -- TODO: Support directories as well
  local new_files = {}

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  for lnum, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, true)) do
    local fname, hash = M.parse_line(line)
    -- TODO: This is dead code. Use pcall
    if fname == nil then
      error(string.format("malformed line: %d", lnum))
    end

    if used_fnames[fname] ~= nil then
      error(string.format("duplicate name '%s'", fname))
    end

    if hash ~= nil then
      table.insert(transition_graph[hash], fname)
    else
      -- TODO: Determine ftype by ending of fname
      table.insert(new_files, fname)
    end
    used_fnames[fname] = true
  end

  local plan = planner.determine_plan(current_state, transition_graph)
  planner.execute_plan(plan)

  -- TODO: Maybe move this to planner?
  for _, fname in ipairs(new_files) do
    -- Just need to create it
    local ok = uv.fs_open(fname, "w", DEFAULT_MODE)
    if not ok then
      error(string.format("create failed: %s", fname))
    end
  end

  fill_dirbuf(CURRENT_BUFFER)
end

return M

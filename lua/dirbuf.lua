local api = vim.api
local uv = vim.loop

local errorf = require("dirbuf.utils").errorf
local planner = require("dirbuf.planner")
local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

local CURRENT_BUFFER = 0

-- TODO: Handle tabs in the string appropriately

-- TODO: Maybe move this to fs.lua?
-- TODO: Test filenames with escaped slashes in them
local function dispname_escape(dispname)
  return dispname:gsub("[ \\]", "\\%0")
end

-- The language of valid dirbuf lines is regular, so normally I would use a
-- regular expression. However, Lua doesn't have a proper regex engine, just
-- simpler patterns. These patterns can't parse dirbuf lines (b/c of escaping),
-- so I manually build the parser. It also gives nicer error messages.
--
-- Returns dispname, hash
local function parse_line(line)
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
      if next_c == " " or next_c == "\\" then
        table.insert(string_builder, next_c)
      else
        errorf("invalid escape sequence '\\%s'", next_c or "<EOF>")
      end
    else
      table.insert(string_builder, c)
    end
  end
  local dispname = table.concat(string_builder)

  -- Skip to hash
  while true do
    local c = chars()
    if c == nil then
      -- Ended line before hash
      return dispname, nil
    elseif c == "#" then
      break
    elseif not c:match("%s") then
      errorf("unexpected character '%s'", c)
    end
  end

  -- Parse hash
  string_builder = {}
  for _ = 1, fs.HASH_LEN do
    local c = chars()
    if c == nil then
      error("unexpected end of line")
    elseif not c:match("%x") then
      errorf("invalid hash character '%s'", c)
    else
      table.insert(string_builder, c)
    end
  end
  local hash = table.concat(string_builder)

  local c = chars()
  if c ~= nil then
    errorf("extra character '%s'", c)
  end

  return dispname, hash
end

-- fill_dirbuf fills buffer `buf` with the contents of its corresponding
-- directory. `buf` must have the name of a valid directory and its contents
-- must be a valid dirbuf.
--
-- If `preserve_order` is true, then the contents of `buf` are left untouched,
-- only deleting old lines and appending new lines to the end. `preserve_order`
-- defaults to false.
--
-- If `on_fname` is set, then the cursor will be put on the line corresponding
-- to `on_fname`.
local function fill_dirbuf(buf, preserve_order, on_fname)
  if preserve_order == nil then
    preserve_order = false
  end

  local dir = api.nvim_buf_get_name(buf)
  local hide_hidden = api.nvim_buf_get_var(buf, "dirbuf_hide_hidden")

  -- Used to preserve the ordering of lines. Each line is guaranteed to be used
  -- exactly once assuming the buffer contains no non-existent fnames.
  local dispname_lnums = {}
  local tail = #dispname_lnums + 1
  if preserve_order then
    for _, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, true)) do
      local fname, _ = parse_line(line)
      if hide_hidden and fname:sub(1, 1) == "." then
        goto continue
      end
      dispname_lnums[fname] = tail
      tail = tail + 1

      ::continue::
    end
  end

  local move_cursor_to = nil

  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    error(err)
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
    if hide_hidden and fname:sub(1, 1) == "." then
      goto continue
    end

    local fstate = FState.new(fname, dir, ftype)
    local hash = fstate:hash()
    if fstates[hash] ~= nil then
      errorf("colliding hashes '%s'", hash)
    end
    fstates[hash] = fstate

    local dispname = fstate:dispname()
    local dispname_esc = dispname_escape(dispname)
    if #dispname_esc > max_len then
      max_len = #dispname_esc
    end
    local lnum = dispname_lnums[dispname]
    if lnum == nil then
      lnum = tail
      tail = tail + 1
    end
    buf_lines[lnum] = {dispname_esc, nil, "  #" .. hash}

    if fstate.fname == on_fname then
      move_cursor_to = lnum
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
function M.init_dirbuf(buf, preserve_order, on_fname)
  local dir = clean_path(api.nvim_buf_get_name(buf))
  api.nvim_buf_set_name(buf, dir)

  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  -- TODO: Make the default mode configurable
  local ok, _ = pcall(api.nvim_buf_get_var, "dirbuf_hide_hidden")
  if not ok then
    api.nvim_buf_set_var(buf, "dirbuf_hide_hidden", false)
  end

  fill_dirbuf(buf, preserve_order, on_fname)
end

function M.open(dir)
  if dir == "" then
    dir = "."
  end
  dir = clean_path(dir)

  -- XXX: This is really hard to understand. What I want is to get the current
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
      error("failed to create buffer")
    end
    api.nvim_buf_set_name(buf, dir)
  end

  api.nvim_win_set_buf(0, buf)
  M.init_dirbuf(buf, false, old_fname)
end

function M.enter()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    error("dirbuf must be saved first")
  end

  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local line = api.nvim_get_current_line()
  local _, hash = parse_line(line)
  local fstate = vim.b.dirbuf[hash]
  -- We rely on the autocmd to open directories
  vim.cmd("silent edit " .. vim.fn.fnameescape(fs.join(dir, fstate.fname)))
end

function M.sync()
  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local fstates = vim.b.dirbuf
  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)

  -- Map from hash to fnames associated with that hash
  local transition_graph = {}
  transition_graph[""] = {}
  for hash, _ in pairs(fstates) do
    transition_graph[hash] = {}
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  for lnum, line in ipairs(api.nvim_buf_get_lines(CURRENT_BUFFER, 0, -1, true)) do
    local dispname, hash = parse_line(line)
    local new_fstate = FState.from_dispname(dispname, dir)

    if used_fnames[new_fstate.fname] ~= nil then
      errorf("line %d: duplicate name '%s'", lnum, dispname)
    end
    if hash ~= nil and fstates[hash].ftype ~= new_fstate.ftype then
      errorf("line %d: cannot change ftype %s -> %s", lnum, fstates[hash].ftype,
             new_fstate.ftype)
    end

    if hash == nil then
      table.insert(transition_graph[""], new_fstate)
    else
      table.insert(transition_graph[hash], new_fstate)
    end
    used_fnames[new_fstate.fname] = true
  end

  local plan = planner.determine_plan(fstates, transition_graph)
  planner.execute_plan(plan)

  fill_dirbuf(CURRENT_BUFFER, true)
end

function M.toggle_hide()
  vim.b.dirbuf_hide_hidden = not vim.b.dirbuf_hide_hidden
  -- We want to ensure that we are still hovering on the same line
  local dispname, _ = parse_line(vim.fn.getline("."))
  -- TODO: Should I have a function to do this directly?
  local fname = FState.from_dispname(dispname).fname
  -- TODO: Is it intuitive to have keep your cursor on the fname?
  fill_dirbuf(CURRENT_BUFFER, false, fname)
end

function M.test()
  describe("parse_line", function()
    it("simple line", function()
      local fname, hash = parse_line([[README.md  #deadbeef]])
      assert.equal(fname, "README.md")
      assert.equal(hash, "deadbeef")
    end)

    it("escaped spaces", function()
      local fname, hash = parse_line([[\ a\ b\ c\   #01234567]])
      assert.equal(fname, " a b c ")
      assert.equal(hash, "01234567")
    end)

    it("escaped backslashes", function()
      local fname, hash = parse_line([[before\\after  #01234567]])
      assert.equal(fname, [[before\after]])
      assert.equal(hash, "01234567")
    end)

    it("invalid escape sequence", function()
      assert.has_error(function()
        parse_line([[\a  #01234567]])
      end)
    end)

    it("only hash", function()
      local fname, hash = parse_line([[#01234567]])
      assert.equal(fname, "#01234567")
      assert.is_nil(hash)
    end)

    it("short hash", function()
      assert.has_error(function()
        parse_line([[foo #0123456]])
      end)
    end)
    it("long hash", function()
      assert.has_error(function()
        parse_line([[foo #012345678]])
      end)
    end)
    it("invalid hex character hash", function()
      assert.has_error(function()
        parse_line([[foo #0123456z]])
      end)
    end)

    it("leading space", function()
      assert.has_error(function()
        parse_line([[ foo #01234567]])
      end)
    end)

    it("trailing space, no hash", function()
      local fname, hash = parse_line([[foo ]])
      assert.equal(fname, [[foo]])
      assert.is_nil(hash)
    end)

    it("extra token", function()
      assert.has_error(function()
        parse_line([[foo bar #01234567]])
      end)
    end)

    it("non-ASCII fnames", function()
      local fname, hash = parse_line([[文档  #01234567]])
      assert.equal(fname, "文档")
      assert.equal(hash, "01234567")
    end)
  end)
end

return M

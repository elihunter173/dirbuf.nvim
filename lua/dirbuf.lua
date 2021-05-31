local api = vim.api
local uv = vim.loop

local errorf = require("dirbuf.utils").errorf
local planner = require("dirbuf.planner")
local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

local CURRENT_BUFFER = 0

-- TODO: Handle tabs in the string appropriately

local function dispname_escape(dispname)
  return dispname:gsub("[ \\]", "\\%0")
end

-- The language of valid dirbuf lines is regular, so normally I would use a
-- regular expression. However, Lua doesn't have a proper regex engine, just
-- simpler patterns. These patterns can't parse dirbuf lines (b/c of escaping),
-- so I manually build the parser. It also gives nicer error messages.
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
  local fname = table.concat(string_builder)

  -- Skip to hash
  while true do
    local c = chars()
    if c == nil then
      -- Ended line before hash
      return fname, nil
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

  return fname, hash
end

local function fill_dirbuf(buf)
  local dir = api.nvim_buf_get_name(buf)

  -- Used to preserve the ordering of lines. Each line is guaranteed to be used
  -- exactly once assuming the buffer contains no non-existent fnames.
  local dispname_lnums = {}
  for lnum, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, true)) do
    local dispname, _ = parse_line(line)
    dispname_lnums[dispname] = lnum
  end
  local tail = #dispname_lnums + 1

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

    local fstate = FState.new(fname, ftype)
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
  end
  -- Now fill in the padding in the (fname_esc, padding, hash) tuples with
  -- appropriate padding such that the hashes line up
  for idx, tuple in ipairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[idx] = table.concat(tuple)
  end
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", fstates)

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
  -- TODO: Should I stop with init_dirbuf if the buf already has `b:dirbuf`
  -- defined?
  local dir = clean_path(api.nvim_buf_get_name(buf))
  api.nvim_buf_set_name(buf, dir)

  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  fill_dirbuf(buf)

  api.nvim_buf_set_var(buf, "dirbuf_old_dir", uv.cwd())
  api.nvim_set_current_dir(dir)
end

function M.open(dir)
  if dir == "" then
    dir = "."
  end
  dir = clean_path(dir)

  local buf = vim.fn.bufnr("^" .. dir .. "$")
  if buf == -1 then
    buf = api.nvim_create_buf(true, false)
    if buf == 0 then
      error("failed to create buffer")
    end
    api.nvim_buf_set_name(buf, dir)
  end

  -- We must first change buffers before we save the old directory and switch
  -- directories. That is because we use BufLeave to reset the current
  -- directory and we don't want to change the saved current directory when we
  -- go deeper into dirbufs. We cannot use api.nvim_win_set_buf(0, buf) because
  -- that doesn't trigger autocmds.

  -- We rely on the autocmd to init the dirbuf.
  -- XXX: This doesn't work because of https://github.com/neovim/neovim/issues/13711
  -- vim.cmd("buffer " .. buf)

  -- HACK: To work around the BufEnter error swallowing, we emulate :buffer as
  -- best we can.
  vim.cmd("doautocmd BufLeave")
  api.nvim_win_set_buf(0, buf)
  M.init_dirbuf(buf)
end

function M.enter()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    error("dirbuf must be saved first")
  end

  local line = api.nvim_get_current_line()
  local _, hash = parse_line(line)
  local fstate = vim.b.dirbuf[hash]
  -- We rely on the autocmd to open directories
  vim.cmd("silent edit " .. vim.fn.fnameescape(fstate.fname))
end

function M.sync()
  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local fstates = vim.b.dirbuf

  -- Map from hash to fnames associated with that hash
  local transition_graph = {}
  transition_graph[""] = {}
  for hash, _ in pairs(fstates) do
    transition_graph[hash] = {}
  end

  -- Just to ensure we don't reuse fnames
  local used_fnames = {}
  for _, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, true)) do
    local dispname, hash = parse_line(line)
    local new_fstate = FState.from_dispname(dispname)

    if used_fnames[new_fstate.fname] ~= nil then
      errorf("duplicate name '%s'", dispname)
    end
    if hash ~= nil and fstates[hash].ftype ~= new_fstate.ftype then
      error("cannot change ftype")
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

  fill_dirbuf(CURRENT_BUFFER)
end

function M.test()
  describe("parse_line", function()
    it("simple line", function()
      local fname, hash = parse_line([[README.md  #dedbeef]])
      assert.equal(fname, "README.md")
      assert.equal(hash, "dedbeef")
    end)

    it("escaped spaces", function()
      local fname, hash = parse_line([[\ a\ b\ c\   #0123456]])
      assert.equal(fname, " a b c ")
      assert.equal(hash, "0123456")
    end)

    it("escaped backslashes", function()
      local fname, hash = parse_line([[before\\after  #0123456]])
      assert.equal(fname, [[before\after]])
      assert.equal(hash, "0123456")
    end)

    it("invalid escape sequence", function()
      assert.has_error(function()
        parse_line([[\a  #0123456]])
      end)
    end)

    it("only hash", function()
      local fname, hash = parse_line([[#0123456]])
      assert.equal(fname, "#0123456")
      assert.is_nil(hash)
    end)

    it("invalid hash", function()
      assert.has_error(function()
        parse_line([[foo #012345]])
      end)
      assert.has_error(function()
        parse_line([[foo #01234567]])
      end)
      assert.has_error(function()
        parse_line([[foo #012345z]])
      end)
    end)

    it("leading space", function()
      assert.has_error(function()
        parse_line([[ foo #0123456]])
      end)
    end)

    it("trailing space, no hash", function()
      local fname, hash = parse_line([[foo ]])
      assert.equal(fname, [[foo]])
      assert.is_nil(hash)
    end)

    it("extra token", function()
      assert.has_error(function()
        parse_line([[foo bar #0123456]])
      end)
    end)

    it("non-ASCII fnames", function()
      local fname, hash = parse_line([[文档  #0123456]])
      assert.equal(fname, "文档")
      assert.equal(hash, "0123456")
    end)
  end)
end

return M

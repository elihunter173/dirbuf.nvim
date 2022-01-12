local uv = vim.loop

local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

--[[
local record Dirbuf
  dir: string
  fstates: {string: FState}
end
--]]

-- The language of valid dirbuf lines is regular, so normally I would use a
-- regular expression. However, Lua doesn't have a proper regex engine, just
-- simpler patterns. These patterns can't parse dirbuf lines (b/c of escaping),
-- so I manually build the parser. It also gives nicer error messages.
--
-- Returns err, dispname, hash
function M.line(line)
  local string_builder = {}
  -- We store this in a local so we can skip characters
  local chars = line:gmatch(".")

  -- Parse fname
  while true do
    local c = chars()
    if c == nil then
      -- Ended line in fname
      if #string_builder > 0 then
        local fname = table.concat(string_builder)
        return nil, fname, nil
      else
        return nil, nil, nil
      end

    elseif c == "\t" then
      break
    elseif c == "\\" then
      local next_c = chars()
      if next_c == "/" or next_c == "\\" then
        table.insert(string_builder, next_c)
      elseif next_c == "t" then
        table.insert(string_builder, "\t")
      elseif next_c == nil then
        return "Cannot escape end of line"
      else
        return string.format("Invalid escape sequence '\\%s'", next_c)
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
      return nil, dispname, nil
    elseif c == "#" then
      break
    elseif not c:match("%s") then
      return string.format("Unexpected character '%s' after fname", c)
    end
  end

  -- Parse hash
  string_builder = {}
  for _ = 1, fs.HASH_LEN do
    local c = chars()
    if c == nil then
      return "Unexpected end of line in hash"
    elseif not c:match("%x") then
      return string.format("Invalid hash character '%s'", c)
    else
      table.insert(string_builder, c)
    end
  end
  local hash = table.concat(string_builder)

  -- Consume trailing whitespace
  while true do
    local c = chars()
    if c == nil then
      break
    elseif not c:match("%s") then
      return string.format("Unexpected character '%s' after hash", c)
    end
  end

  return nil, dispname, hash
end

function M.write_dirbuf(dirbuf)
  local buf_lines = {}
  local max_len = 0
  for hash, fstate in pairs(dirbuf.fstates) do
    local dispname = fstate:dispname()
    local dispname_esc = dispname:gsub("\\", "\\\\"):gsub("\t", "\\t")
    if #dispname_esc > max_len then
      max_len = #dispname_esc
    end
    table.insert(buf_lines, dispname_esc .. "\t#" .. hash)
  end
  table.sort(buf_lines)
  return buf_lines, max_len
end

function M.create_dirbuf(dir, show_hidden)
  local dirbuf = {
    dir = dir,
    fstates = {},
  }

  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    return err
  end

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
    if dirbuf.fstates[hash] ~= nil then
      -- This should never happen
      error(string.format("Colliding hashes '%s' with '%s' and '%s'", hash,
                          dirbuf.fstates[hash].path, fstate.path))
    end
    dirbuf.fstates[hash] = fstate

    ::continue::
  end

  return nil, dirbuf
end

function M.test()
  describe("line", function()
    it("simple line", function()
      local err, fname, hash = M.line("README.md\t#deadbeef")
      assert.is_nil(err)
      assert.equal(fname, "README.md")
      assert.equal(hash, "deadbeef")
    end)

    it("spaces", function()
      local err, fname, hash = M.line([[ a b c 	#01234567]])
      assert.is_nil(err)
      assert.equal(fname, " a b c ")
      assert.equal(hash, "01234567")
    end)

    it("escaped tab", function()
      local err, fname, hash = M.line([[before\tafter	#01234567]])
      assert.is_nil(err)
      assert.equal(fname, [[before	after]])
      assert.equal(hash, "01234567")
    end)

    it("escaped backslash", function()
      local err, fname, hash = M.line([[before\\after	#01234567]])
      assert.is_nil(err)
      assert.equal(fname, [[before\after]])
      assert.equal(hash, "01234567")
    end)

    it("unescaped tab", function()
      local err, fname, hash = M.line([[foo	bar	#01234567]])
      assert.is_not_nil(err)
      assert.is_nil(fname)
      assert.is_nil(hash)
    end)

    it("invalid escape sequence", function()
      local err, fname, hash = M.line([[\a  #01234567]])
      assert.is_not_nil(err)
      assert.is_nil(fname)
      assert.is_nil(hash)
    end)

    it("only hash", function()
      local err, fname, hash = M.line([[#01234567]])
      assert.is_nil(err)
      assert.equal(fname, "#01234567")
      assert.is_nil(hash)
    end)

    it("short hash", function()
      local err, fname, hash = M.line([[foo	#0123456]])
      assert.is_not_nil(err)
      assert.is_nil(fname)
      assert.is_nil(hash)
    end)

    it("long hash", function()
      local err, fname, hash = M.line([[foo	#012345678]])
      assert.is_not_nil(err)
      assert.is_nil(fname)
      assert.is_nil(hash)
    end)

    it("invalid hex character hash", function()
      local err, fname, hash = M.line([[foo	#0123456z]])
      assert.is_not_nil(err)
      assert.is_nil(fname)
      assert.is_nil(hash)
    end)

    it("trailing spaces after hash", function()
      local err, fname, hash = M.line([[foo	#01234567  ]])
      assert.is_nil(err)
      assert.equal(fname, "foo")
      assert.equal(hash, "01234567")
    end)

    it("trailing spaces no hash", function()
      local err, fname, hash = M.line([[foo  ]])
      assert.is_nil(err)
      assert.equal(fname, [[foo  ]])
      assert.is_nil(hash)
    end)

    it("non-ASCII fname", function()
      local err, fname, hash = M.line([[文档	#01234567]])
      assert.is_nil(err)
      assert.equal(fname, "文档")
      assert.equal(hash, "01234567")
    end)
  end)
end

return M

local errorf = require("dirbuf.utils").errorf
local fs = require("dirbuf.fs")

local M = {}

-- TODO: Handle tabs in the string appropriately

-- The language of valid dirbuf lines is regular, so normally I would use a
-- regular expression. However, Lua doesn't have a proper regex engine, just
-- simpler patterns. These patterns can't parse dirbuf lines (b/c of escaping),
-- so I manually build the parser. It also gives nicer error messages.
--
-- Returns dispname, hash
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
      error("unexpected end of line in hash")
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

function M.test()
  describe("parse_line", function()
    it("simple line", function()
      local fname, hash = M.parse_line([[README.md  #deadbeef]])
      assert.equal(fname, "README.md")
      assert.equal(hash, "deadbeef")
    end)

    it("escaped spaces", function()
      local fname, hash = M.parse_line([[\ a\ b\ c\   #01234567]])
      assert.equal(fname, " a b c ")
      assert.equal(hash, "01234567")
    end)

    it("escaped backslashes", function()
      local fname, hash = M.parse_line([[before\\after  #01234567]])
      assert.equal(fname, [[before\after]])
      assert.equal(hash, "01234567")
    end)

    it("invalid escape sequence", function()
      assert.has_error(function()
        M.parse_line([[\a  #01234567]])
      end)
    end)

    it("only hash", function()
      local fname, hash = M.parse_line([[#01234567]])
      assert.equal(fname, "#01234567")
      assert.is_nil(hash)
    end)

    it("short hash", function()
      assert.has_error(function()
        M.parse_line([[foo #0123456]])
      end)
    end)
    it("long hash", function()
      assert.has_error(function()
        M.parse_line([[foo #012345678]])
      end)
    end)
    it("invalid hex character hash", function()
      assert.has_error(function()
        M.parse_line([[foo #0123456z]])
      end)
    end)

    it("leading space", function()
      assert.has_error(function()
        M.parse_line([[ foo #01234567]])
      end)
    end)

    it("trailing space, no hash", function()
      local fname, hash = M.parse_line([[foo ]])
      assert.equal(fname, [[foo]])
      assert.is_nil(hash)
    end)

    it("extra token", function()
      assert.has_error(function()
        M.parse_line([[foo bar #01234567]])
      end)
    end)

    it("non-ASCII fnames", function()
      local fname, hash = M.parse_line([[文档  #01234567]])
      assert.equal(fname, "文档")
      assert.equal(hash, "01234567")
    end)
  end)
end

return M

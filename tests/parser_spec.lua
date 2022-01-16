local buffer = require("dirbuf.buffer")

local FState = require("dirbuf.fs").FState

local function fst(fname, ftype)
  return FState.new(fname, "", ftype)
end

describe("parse_line", function()
  it("simple", function()
    local err, fname, hash = buffer.parse_line("README.md\t#deadbeef")
    assert.is_nil(err)
    assert.equal(fname, "README.md")
    assert.equal(hash, "deadbeef")
  end)

  it("spaces", function()
    local err, fname, hash = buffer.parse_line([[ a b c 	#01234567]])
    assert.is_nil(err)
    assert.equal(fname, " a b c ")
    assert.equal(hash, "01234567")
  end)

  it("escaped tab", function()
    local err, fname, hash = buffer.parse_line([[before\tafter	#01234567]])
    assert.is_nil(err)
    assert.equal(fname, [[before	after]])
    assert.equal(hash, "01234567")
  end)

  it("escaped backslash", function()
    local err, fname, hash = buffer.parse_line([[before\\after	#01234567]])
    assert.is_nil(err)
    assert.equal(fname, [[before\after]])
    assert.equal(hash, "01234567")
  end)

  it("unescaped tab", function()
    local err, fname, hash = buffer.parse_line([[foo	bar	#01234567]])
    assert.is_not_nil(err)
    assert.is_nil(fname)
    assert.is_nil(hash)
  end)

  it("invalid escape sequence", function()
    local err, fname, hash = buffer.parse_line([[\a  #01234567]])
    assert.is_not_nil(err)
    assert.is_nil(fname)
    assert.is_nil(hash)
  end)

  it("only hash", function()
    local err, fname, hash = buffer.parse_line([[#01234567]])
    assert.is_nil(err)
    assert.equal(fname, "#01234567")
    assert.is_nil(hash)
  end)

  it("short hash", function()
    local err, fname, hash = buffer.parse_line([[foo	#0123456]])
    assert.is_not_nil(err)
    assert.is_nil(fname)
    assert.is_nil(hash)
  end)

  it("long hash", function()
    local err, fname, hash = buffer.parse_line([[foo	#012345678]])
    assert.is_not_nil(err)
    assert.is_nil(fname)
    assert.is_nil(hash)
  end)

  it("invalid hex character hash", function()
    local err, fname, hash = buffer.parse_line([[foo	#0123456z]])
    assert.is_not_nil(err)
    assert.is_nil(fname)
    assert.is_nil(hash)
  end)

  it("trailing spaces after hash", function()
    local err, fname, hash = buffer.parse_line([[foo	#01234567  ]])
    assert.is_nil(err)
    assert.equal(fname, "foo")
    assert.equal(hash, "01234567")
  end)

  it("trailing spaces no hash", function()
    local err, fname, hash = buffer.parse_line([[foo  ]])
    assert.is_nil(err)
    assert.equal(fname, [[foo  ]])
    assert.is_nil(hash)
  end)

  it("non-ASCII fname", function()
    local err, fname, hash = buffer.parse_line([[文档	#01234567]])
    assert.is_nil(err)
    assert.equal(fname, "文档")
    assert.equal(hash, "01234567")
  end)
end)

describe("write_dirbuf", function()
  it("types", function()
    local dirbuf = {
      dir = "",
      fstates = {
        ["00000000"] = fst("file", "file"),
        ["00000001"] = fst("directory", "directory"),
        ["00000002"] = fst("link", "link"),
        ["00000003"] = fst("fifo", "fifo"),
        ["00000004"] = fst("socket", "socket"),
        ["00000005"] = fst("char", "char"),
        ["00000006"] = fst("block", "block"),
      },
    }
    local buf_lines, max_len = buffer.write_dirbuf(dirbuf)
    assert.equal(max_len, #"directory/")
    -- LuaFormatter off
    assert.same(buf_lines, {
      "block#	#00000006",
      "char%	#00000005",
      "directory/	#00000001",
      "fifo|	#00000003",
      "file	#00000000",
      "link@	#00000002",
      "socket=	#00000004",
    })
    -- LuaFormatter on
  end)

  it("escape characters", function()
    local dirbuf = {dir = "", fstates = {["00000000"] = fst("a\\\t", "file")}}
    local buf_lines, max_len = buffer.write_dirbuf(dirbuf)
    assert.equal(max_len, #[[a\\\t]])
    assert.same(buf_lines, {[[a\\\t	#00000000]]})
  end)
end)

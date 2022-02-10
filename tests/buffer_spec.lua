local buffer = require("dirbuf.buffer")

local FState = require("dirbuf.fs").FState

local function fst(fname, ftype)
  return FState.new(fname, "", ftype)
end

describe("parse_line", function()
  local function test_suffix(expected_ftype, suffix)
    it("ftype " .. expected_ftype .. suffix, function()
      local line = "foo" .. suffix .. "\t#deadbeef"
      local err, hash, fname, ftype = buffer.parse_line(line)
      assert.is_nil(err)
      assert.equal(hash, "deadbeef")
      assert.equal(fname, "foo")
      assert.equal(ftype, expected_ftype)
    end)
  end

  test_suffix("file", "")
  test_suffix("directory", "/")
  test_suffix("directory", "\\")
  test_suffix("link", "@")
  test_suffix("fifo", "|")
  test_suffix("socket", "=")
  test_suffix("char", "%")
  test_suffix("block", "#")

  it("interior @", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo@bar	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, [[foo@bar]])
    assert.equal(ftype, "file")
  end)

  it("interior /", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo/bar	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, [[foo/bar]])
    assert.equal(ftype, "file")
  end)

  it("only fname", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo]])
    assert.is_nil(err)
    assert.is_nil(hash)
    assert.equal(fname, "foo")
    assert.equal(ftype, "file")
  end)

  it("only hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[#01234567]])
    assert.is_nil(err)
    assert.is_nil(hash)
    assert.equal(fname, "#01234567")
    assert.equal(ftype, "file")
  end)

  it("spaces", function()
    local err, hash, fname, ftype = buffer.parse_line([[ a b c 	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, " a b c ")
    assert.equal(ftype, "file")
  end)

  it("escaped tab", function()
    local err, hash, fname, ftype = buffer.parse_line([[before\tafter	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, [[before	after]])
    assert.equal(ftype, "file")
  end)

  it("escaped backslash", function()
    local err, hash, fname, ftype = buffer.parse_line([[before\\after	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, [[before\after]])
    assert.equal(ftype, "file")
  end)

  it("escaped backslash end", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo\\	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, [[foo\]])
    assert.equal(ftype, "file")
  end)

  it("unescaped tab", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo	bar	#01234567]])
    assert.is_not_nil(err)
    assert.is_nil(hash)
    assert.is_nil(fname)
    assert.is_nil(ftype)
  end)

  it("invalid escape sequence", function()
    local err, hash, fname, ftype = buffer.parse_line([[\a  #01234567]])
    assert.is_not_nil(err)
    assert.is_nil(hash)
    assert.is_nil(fname)
    assert.is_nil(ftype)
  end)

  it("short hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo	#0123456]])
    assert.is_not_nil(err)
    assert.is_nil(hash)
    assert.is_nil(fname)
    assert.is_nil(ftype)
  end)

  it("long hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo	#012345678]])
    assert.is_not_nil(err)
    assert.is_nil(hash)
    assert.is_nil(fname)
    assert.is_nil(ftype)
  end)

  it("invalid hex character hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo	#0123456z]])
    assert.is_not_nil(err)
    assert.is_nil(hash)
    assert.is_nil(fname)
    assert.is_nil(ftype)
  end)

  it("trailing spaces after hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo	#01234567  ]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, "foo")
    assert.equal(ftype, "file")
  end)

  it("trailing spaces no hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo  ]])
    assert.is_nil(err)
    assert.is_nil(hash)
    assert.equal(fname, [[foo  ]])
    assert.equal(ftype, "file")
  end)

  it("non-ASCII fname", function()
    local err, hash, fname, ftype = buffer.parse_line([[文档	#01234567]])
    assert.is_nil(err)
    assert.equal(hash, "01234567")
    assert.equal(fname, "文档")
    assert.equal(ftype, "file")
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
    local dirbuf = { dir = "", fstates = { ["00000000"] = fst("a\\\t", "file") } }
    local buf_lines, max_len = buffer.write_dirbuf(dirbuf)
    assert.equal(max_len, #[[a\\\t]])
    assert.same(buf_lines, { [[a\\\t	#00000000]] })
  end)
end)

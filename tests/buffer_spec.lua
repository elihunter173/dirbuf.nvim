local buffer = require("dirbuf.buffer")
local fs = require("dirbuf.fs")

local function entry(fname, ftype)
  return fs.FSEntry.new(fname, "", ftype or "file")
end

local function mkhash(n)
  return string.format("%08x", n)
end

describe("parse_line", function()
  local function expect_parse(hash_first_line, hash_last_line, expected)
    local err, hash, fname, ftype = buffer.parse_line(hash_first_line, { hash_first = true })
    if expected.err then
      assert.is_not_nil(err)
    else
      assert.is_nil(err)
    end
    assert.equal(expected.hash, hash, "hash first: hash")
    assert.equal(expected.fname, fname, "hash first: fname")
    assert.equal(expected.ftype, ftype, "hash first: ftype")

    err, hash, fname, ftype = buffer.parse_line(hash_last_line, { hash_first = false })
    if expected.err then
      assert.is_not_nil(err)
    else
      assert.is_nil(err)
    end
    assert.equal(expected.hash, hash, "hash last: hash")
    assert.equal(expected.fname, fname, "hash last: fname")
    assert.equal(expected.ftype, ftype, "hash last: ftype")
  end

  local function test_suffix(expected_ftype, suffix)
    it("ftype " .. expected_ftype .. suffix, function()
      local hash_first_line = "#0000000a\tfoo" .. suffix
      local hash_last_line = "foo" .. suffix .. "\t#0000000a"
      expect_parse(hash_first_line, hash_last_line, {
        err = false,
        hash = "0000000a",
        fname = "foo",
        ftype = expected_ftype,
      })
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
    expect_parse([[#0000000a	foo@bar]], [[foo@bar	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = "foo@bar",
      ftype = "file",
    })
  end)

  it("interior /", function()
    expect_parse([[#0000000a	foo/bar]], [[foo/bar	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = "foo/bar",
      ftype = "file",
    })
  end)

  it("fname is @", function()
    expect_parse([[@]], [[@]], {
      err = false,
      hash = nil,
      fname = "@",
      ftype = "file",
    })
  end)

  it("only fname", function()
    expect_parse([[foo]], [[foo]], {
      err = false,
      hash = nil,
      fname = "foo",
      ftype = "file",
    })
  end)

  it("only hash", function()
    expect_parse([[#0000000a]], [[#0000000a]], {
      err = false,
      hash = nil,
      fname = "#0000000a",
      ftype = "file",
    })
  end)

  it("spaces", function()
    expect_parse([[#0000000a	 a b c ]], [[ a b c 	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = " a b c ",
      ftype = "file",
    })
  end)

  it("escaped tab", function()
    expect_parse([[#0000000a	before\tafter]], [[before\tafter	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = [[before	after]],
      ftype = "file",
    })
  end)

  it("escaped backslash", function()
    expect_parse([[#0000000a	before\\after]], [[before\\after	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = [[before\after]],
      ftype = "file",
    })
  end)

  it("escaped backslash end", function()
    expect_parse([[#0000000a	foo\\]], [[foo\\	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = [[foo\]],
      ftype = "file",
    })
  end)

  it("unescaped tab", function()
    expect_parse([[#0000000a	foo	bar]], [[foo	bar	#0000000a]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("invalid escape sequence", function()
    expect_parse([[ #0000000a	\a]], [[\a  #0000000a]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("short hash", function()
    expect_parse([[#0123456	foo]], [[foo	#0123456]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("long hash", function()
    expect_parse([[#012345678	foo]], [[foo	#012345678]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("invalid hex character hash", function()
    expect_parse([[#0123456z	foo]], [[foo	#0123456z]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("trailing spaces after hash", function()
    local err, hash, fname, ftype = buffer.parse_line([[foo	#0000000a  ]], { hash_first = false })
    assert.is_nil(err)
    assert.equal("0000000a", hash)
    assert.equal("foo", fname)
    assert.equal("file", ftype)
  end)

  it("trailing spaces no hash", function()
    expect_parse([[foo  ]], [[foo  ]], {
      err = false,
      hash = nil,
      fname = "foo  ",
      ftype = "file",
    })
  end)

  it("non-ASCII fname", function()
    expect_parse([[#0000000a	文档]], [[文档	#0000000a]], {
      err = false,
      hash = "0000000a",
      fname = "文档",
      ftype = "file",
    })
  end)
end)

describe("write_fs_entries", function()
  it("types", function()
    local fs_entries = {
      [mkhash(1)] = entry("file", "file"),
      [mkhash(2)] = entry("directory", "directory"),
      [mkhash(3)] = entry("link", "link"),
      [mkhash(4)] = entry("fifo", "fifo"),
      [mkhash(5)] = entry("socket", "socket"),
      [mkhash(6)] = entry("char", "char"),
      [mkhash(7)] = entry("block", "block"),
    }

    local buf_lines, max_len = buffer.write_fs_entries(fs_entries, { hash_first = false })
    assert.equal(#"directory/", max_len)
    assert.same({
      "block#	#00000007",
      "char%	#00000006",
      "directory/	#00000002",
      "fifo|	#00000004",
      "file	#00000001",
      "link@	#00000003",
      "socket=	#00000005",
    }, buf_lines)

    buf_lines, _ = buffer.write_fs_entries(fs_entries, { hash_first = true })
    assert.same({
      "#00000007	block#",
      "#00000006	char%",
      "#00000002	directory/",
      "#00000004	fifo|",
      "#00000001	file",
      "#00000003	link@",
      "#00000005	socket=",
    }, buf_lines)
  end)

  it("escape characters", function()
    local fs_entries = { [mkhash(1)] = entry("a\\\t") }
    local buf_lines, max_len = buffer.write_fs_entries(fs_entries, { hash_first = false })
    assert.equal(#[[a\\\t]], max_len)
    assert.same({ [[a\\\t	#00000001]] }, buf_lines)
    buf_lines, _ = buffer.write_fs_entries(fs_entries, { hash_first = true })
    assert.same({ [[#00000001	a\\\t]] }, buf_lines)
  end)

  it("track_fname", function()
    local fs_entries = { [mkhash(1)] = entry("a"), [mkhash(2)] = entry("b"), [mkhash(3)] = entry("c") }
    local _, _, fname_line = buffer.write_fs_entries(fs_entries, { hash_first = true }, "b")
    assert.equal(2, fname_line)
    _, _, fname_line = buffer.write_fs_entries(fs_entries, { hash_first = false }, "b")
    assert.equal(2, fname_line)
  end)
end)

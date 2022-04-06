local buffer = require("dirbuf.buffer")
local fs = require("dirbuf.fs")

local function entry(fname, ftype)
  return fs.FSEntry.new(fname, "", ftype or "file")
end

describe("parse_line", function()
  local function expect_parse(hash_first_line, hash_last_line, expected)
    local err, hash, fname, ftype = buffer.parse_line(hash_first_line, { hash_first = true })
    if expected.err then
      assert.is_not_nil(err)
    else
      assert.is_nil(err)
    end
    assert.equal(expected.hash, hash)
    assert.equal(expected.fname, fname)
    assert.equal(expected.ftype, ftype)

    err, hash, fname, ftype = buffer.parse_line(hash_last_line, { hash_first = false })
    if expected.err then
      assert.is_not_nil(err)
    else
      assert.is_nil(err)
    end
    assert.equal(expected.hash, hash)
    assert.equal(expected.fname, fname)
    assert.equal(expected.ftype, ftype)
  end

  local function test_suffix(expected_ftype, suffix)
    it("ftype " .. expected_ftype .. suffix, function()
      local hash_first_line = "#0000000a\tfoo" .. suffix
      local hash_last_line = "foo" .. suffix .. "\t#0000000a"
      expect_parse(hash_first_line, hash_last_line, {
        err = false,
        hash = 10,
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
      hash = 10,
      fname = "foo@bar",
      ftype = "file",
    })
  end)

  it("interior /", function()
    expect_parse([[#0000000a	foo/bar]], [[foo/bar	#0000000a]], {
      err = false,
      hash = 10,
      fname = "foo/bar",
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
      hash = 10,
      fname = " a b c ",
      ftype = "file",
    })
  end)

  it("escaped tab", function()
    expect_parse([[#0000000a	before\tafter]], [[before\tafter	#0000000a]], {
      err = false,
      hash = 10,
      fname = [[before	after]],
      ftype = "file",
    })
  end)

  it("escaped backslash", function()
    expect_parse([[#0000000a	before\\after]], [[before\\after	#0000000a]], {
      err = false,
      hash = 10,
      fname = [[before\after]],
      ftype = "file",
    })
  end)

  it("escaped backslash end", function()
    expect_parse([[#0000000a	foo\\]], [[foo\\	#0000000a]], {
      err = false,
      hash = 10,
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
    assert.equal(10, hash)
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
      hash = 10,
      fname = "文档",
      ftype = "file",
    })
  end)
end)

describe("write_dirbuf", function()
  it("types", function()
    local dirbuf = {
      dir = "",
      fs_entries = {
        entry("file", "file"),
        entry("directory", "directory"),
        entry("link", "link"),
        entry("fifo", "fifo"),
        entry("socket", "socket"),
        entry("char", "char"),
        entry("block", "block"),
      },
    }

    local buf_lines, max_len = buffer.write_dirbuf(dirbuf, { hash_first = false })
    assert.equal(#"directory/", max_len)
    assert.same({
      "file	#00000001",
      "directory/	#00000002",
      "link@	#00000003",
      "fifo|	#00000004",
      "socket=	#00000005",
      "char%	#00000006",
      "block#	#00000007",
    }, buf_lines)

    buf_lines, _ = buffer.write_dirbuf(dirbuf, { hash_first = true })
    assert.same({
      "#00000001	file",
      "#00000002	directory/",
      "#00000003	link@",
      "#00000004	fifo|",
      "#00000005	socket=",
      "#00000006	char%",
      "#00000007	block#",
    }, buf_lines)
  end)

  it("escape characters", function()
    local dirbuf = { dir = "", fs_entries = { entry("a\\\t") } }
    local buf_lines, max_len = buffer.write_dirbuf(dirbuf, { hash_first = false })
    assert.equal(#[[a\\\t]], max_len)
    assert.same(buf_lines, { [[a\\\t	#00000001]] })
    buf_lines, _ = buffer.write_dirbuf(dirbuf, { hash_first = true })
    assert.same({ [[#00000001	a\\\t]] }, buf_lines)
  end)

  it("track_fname", function()
    local dirbuf = {
      dir = "",
      fs_entries = { entry("a"), entry("b"), entry("c") },
    }
    local _, _, fname_line = buffer.write_dirbuf(dirbuf, { hash_first = true }, "b")
    assert.equal(2, fname_line)
    _, _, fname_line = buffer.write_dirbuf(dirbuf, { hash_first = false }, "b")
    assert.equal(2, fname_line)
  end)
end)

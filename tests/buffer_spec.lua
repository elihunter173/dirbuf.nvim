local buffer = require("dirbuf.buffer")
local fs = require("dirbuf.fs")

local function entry(fname, ftype)
  return fs.FSEntry.new(fname, "", ftype or "file")
end

describe("parse_line", function()
  local function expect_parse(line, expected)
    local err, hash, fname, ftype = buffer.parse_line(line)
    if expected.err then
      assert.is_not_nil(err)
    else
      assert.is_nil(err)
    end
    assert.equal(expected.hash, hash, "hash")
    assert.equal(expected.fname, fname, "fname")
    assert.equal(expected.ftype, ftype, "ftype")
  end

  local function test_suffix(expected_ftype, suffix)
    it("ftype " .. expected_ftype .. suffix, function()
      expect_parse("#0000000a\tfoo" .. suffix, {
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
    expect_parse([[#0000000a	foo@bar]], {
      err = false,
      hash = 10,
      fname = "foo@bar",
      ftype = "file",
    })
  end)

  it("interior /", function()
    expect_parse([[#0000000a	foo/bar]], {
      err = false,
      hash = 10,
      fname = "foo/bar",
      ftype = "file",
    })
  end)

  it("fname is @", function()
    expect_parse([[@]], {
      err = false,
      hash = nil,
      fname = "@",
      ftype = "file",
    })
  end)

  it("only fname", function()
    expect_parse([[foo]], {
      err = false,
      hash = nil,
      fname = "foo",
      ftype = "file",
    })
  end)

  it("only hash", function()
    expect_parse([[#0000000a]], {
      err = false,
      hash = nil,
      fname = "#0000000a",
      ftype = "file",
    })
  end)

  it("spaces", function()
    expect_parse([[#0000000a	 a b c ]], {
      err = false,
      hash = 10,
      fname = " a b c ",
      ftype = "file",
    })
  end)

  it("escaped tab", function()
    expect_parse([[#0000000a	before\tafter]], {
      err = false,
      hash = 10,
      fname = [[before	after]],
      ftype = "file",
    })
  end)

  it("escaped backslash", function()
    expect_parse([[#0000000a	before\\after]], {
      err = false,
      hash = 10,
      fname = [[before\after]],
      ftype = "file",
    })
  end)

  it("escaped backslash end", function()
    expect_parse([[#0000000a	foo\\]], {
      err = false,
      hash = 10,
      fname = [[foo\]],
      ftype = "file",
    })
  end)

  it("unescaped tab", function()
    expect_parse([[#0000000a	foo	bar]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("invalid escape sequence", function()
    expect_parse([[#0000000a	\y]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("short hash", function()
    expect_parse([[#0123456	foo]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("long hash", function()
    expect_parse([[#012345678	foo]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("invalid hex character hash", function()
    expect_parse([[#0123456z	foo]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("trailing spaces no hash", function()
    expect_parse([[foo  ]], {
      err = false,
      hash = nil,
      fname = "foo  ",
      ftype = "file",
    })
  end)

  it("non-ASCII fname", function()
    expect_parse([[#0000000a	文档]], {
      err = false,
      hash = 10,
      fname = "文档",
      ftype = "file",
    })
  end)
end)

describe("write_fs_entries", function()
  it("types", function()
    local fs_entries = {
      entry("file", "file"),
      entry("directory", "directory"),
      entry("link", "link"),
      entry("fifo", "fifo"),
      entry("socket", "socket"),
      entry("char", "char"),
      entry("block", "block"),
    }
    local buf_lines, _ = buffer.write_fs_entries(fs_entries)
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
    local fs_entries = { entry("a\\\t") }
    local buf_lines, _ = buffer.write_fs_entries(fs_entries)
    assert.same({ [[#00000001	a\\\t]] }, buf_lines)
  end)

  it("track_fname", function()
    local fs_entries = { entry("a"), entry("b"), entry("c") }
    local _, fname_line = buffer.write_fs_entries(fs_entries, "b")
    assert.equal(2, fname_line)
  end)
end)

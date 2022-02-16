local buffer = require("dirbuf.buffer")

local FState = require("dirbuf.fs").FState

local function fst(fname, ftype)
  return FState.new(fname, "", ftype)
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
      local hash_first_line = "#deadbeef\tfoo" .. suffix
      local hash_last_line = "foo" .. suffix .. "\t#deadbeef"
      expect_parse(hash_first_line, hash_last_line, {
        err = false,
        hash = "deadbeef",
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
    expect_parse([[#01234567	foo@bar]], [[foo@bar	#01234567]], {
      err = false,
      hash = "01234567",
      fname = "foo@bar",
      ftype = "file",
    })
  end)

  it("interior /", function()
    expect_parse([[#01234567	foo/bar]], [[foo/bar	#01234567]], {
      err = false,
      hash = "01234567",
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
    expect_parse([[#01234567]], [[#01234567]], {
      err = false,
      hash = nil,
      fname = "#01234567",
      ftype = "file",
    })
  end)

  it("spaces", function()
    expect_parse([[#01234567	 a b c ]], [[ a b c 	#01234567]], {
      err = false,
      hash = "01234567",
      fname = " a b c ",
      ftype = "file",
    })
  end)

  it("escaped tab", function()
    expect_parse([[#01234567	before\tafter]], [[before\tafter	#01234567]], {
      err = false,
      hash = "01234567",
      fname = [[before	after]],
      ftype = "file",
    })
  end)

  it("escaped backslash", function()
    expect_parse([[#01234567	before\\after]], [[before\\after	#01234567]], {
      err = false,
      hash = "01234567",
      fname = [[before\after]],
      ftype = "file",
    })
  end)

  it("escaped backslash end", function()
    expect_parse([[#01234567	foo\\]], [[foo\\	#01234567]], {
      err = false,
      hash = "01234567",
      fname = [[foo\]],
      ftype = "file",
    })
  end)

  it("unescaped tab", function()
    expect_parse([[#01234567	foo	bar]], [[foo	bar	#01234567]], {
      err = true,
      hash = nil,
      fname = nil,
      ftype = nil,
    })
  end)

  it("invalid escape sequence", function()
    expect_parse([[ #01234567	\a]], [[\a  #01234567]], {
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
    local err, hash, fname, ftype = buffer.parse_line([[foo	#01234567  ]], { hash_first = false })
    assert.is_nil(err)
    assert.equal("01234567", hash)
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
    expect_parse([[#01234567	文档]], [[文档	#01234567]], {
      err = false,
      hash = "01234567",
      fname = "文档",
      ftype = "file",
    })
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

    local buf_lines, max_len = buffer.write_dirbuf(dirbuf, { hash_first = false })
    assert.equal(#"directory/", max_len)
    assert.same({
      "block#	#00000006",
      "char%	#00000005",
      "directory/	#00000001",
      "fifo|	#00000003",
      "file	#00000000",
      "link@	#00000002",
      "socket=	#00000004",
    }, buf_lines)

    buf_lines, _ = buffer.write_dirbuf(dirbuf, { hash_first = true })
    assert.same({
      "#00000006	block#",
      "#00000005	char%",
      "#00000001	directory/",
      "#00000003	fifo|",
      "#00000000	file",
      "#00000002	link@",
      "#00000004	socket=",
    }, buf_lines)
  end)

  it("escape characters", function()
    local dirbuf = { dir = "", fstates = { ["00000000"] = fst("a\\\t", "file") } }
    local buf_lines, max_len = buffer.write_dirbuf(dirbuf, { hash_first = false })
    assert.equal(#[[a\\\t]], max_len)
    assert.same(buf_lines, { [[a\\\t	#00000000]] })
    buf_lines, _ = buffer.write_dirbuf(dirbuf, { hash_first = true })
    assert.same({ [[#00000000	a\\\t]] }, buf_lines)
  end)

  it("track_fname", function()
    local dirbuf = {
      dir = "",
      fstates = {
        ["00000000"] = fst("a", "file"),
        ["00000001"] = fst("b", "file"),
        ["00000002"] = fst("c", "file"),
      },
    }
    local _, _, fname_line = buffer.write_dirbuf(dirbuf, { hash_first = true }, "b")
    assert.equal(2, fname_line)
    _, _, fname_line = buffer.write_dirbuf(dirbuf, { hash_first = false }, "b")
    assert.equal(2, fname_line)
  end)
end)

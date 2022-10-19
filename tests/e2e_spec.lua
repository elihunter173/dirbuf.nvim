local api = vim.api
local uv = vim.loop

local function scan_directory(path)
  local directory = {}
  local handle = assert(uv.fs_scandir(path))
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    directory[fname] = ftype
  end
  return directory
end

local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, true)
end

local function expect_lines(expected)
  assert.same(expected, lines())
end

local function expect_directory(expected)
  local path = vim.api.nvim_buf_get_name(0)
  assert.same(expected, scan_directory(path))
end

local function open_dirbuf_of(directory)
  local path = assert(uv.fs_mkdtemp("/tmp/dirbuf-XXXXXX"))
  for fname, ftype in pairs(directory) do
    if ftype == "directory" then
      vim.fn.mkdir(path .. "/" .. fname)
    elseif ftype == "file" then
      vim.fn.writefile({ "file " .. fname }, path .. "/" .. fname)
    else
      error("unrecognized ftype: " .. ftype)
    end
  end
  vim.cmd("Dirbuf " .. vim.fn.fnameescape(path))
end

-- TODO: Use feed
local function feed(keys)
  vim.fn.feedkeys(keys, "x")
end

describe("end-to-end", function()
  it("edits", function()
    open_dirbuf_of({ a = "file", b = "file", c = "directory" })
    expect_lines({ "#00000001\ta", "#00000002\tb", "#00000003\tc/" })
    vim.cmd("g/b/d")
    vim.cmd("s/c/d/")
    api.nvim_put({ "new file" }, "l", "p", true)
    api.nvim_put({ "new directory/" }, "l", "p", true)
    expect_lines({ "#00000001\ta", "#00000003\td/", "new file", "new directory/" })
    expect_directory({ a = "file", b = "file", c = "directory" })
    vim.cmd("DirbufSync")
    expect_lines({ "#00000001\ta", "#00000002\td/", "#00000003\tnew directory/", "#00000004\tnew file" })
    expect_directory({ a = "file", d = "directory", ["new file"] = "file", ["new directory"] = "directory" })
  end)

  it("escape characters", function()
    open_dirbuf_of({ ["\\hello\n\t"] = "file", normal = "file" })
    expect_lines({ [[#00000001	\\hello\n\t]], [[#00000002	normal]] })
    vim.cmd("s/hello/goodbye/")
    vim.cmd("DirbufSync")
    expect_lines({ [[#00000001	\\goodbye\n\t]], [[#00000002	normal]] })
  end)

  it("jump_history()", function()
    open_dirbuf_of({ a = "directory", b = "file" })
    expect_lines({ [[#00000001	a/]], [[#00000002	b]] })
    require("dirbuf").enter()
    expect_lines({ "" })
    require("dirbuf").jump_history(-1)
    expect_lines({ [[#00000001	a/]], [[#00000002	b]] })
    require("dirbuf").jump_history(1)
    expect_lines({ "" })
  end)

  it(":DirbufSync -confirm smoke test", function()
    open_dirbuf_of({ a = "file", b = "file", c = "file" })
    expect_lines({ "#00000001\ta", "#00000002\tb", "#00000003\tc" })
    vim.cmd("g/b/d")
    expect_lines({ "#00000001\ta", "#00000003\tc" })
    expect_directory({ a = "file", b = "file", c = "file" })
    vim.cmd("DirbufSync -confirm")
  end)

  it(":DirbufSync unrecognized option", function()
    assert.errors(function()
      vim.cmd("Dirbuf")
      vim.cmd("DirbufSync -some-fake-option")
    end)
    vim.cmd("bdelete!")
  end)

  -- TODO: Figure out how to trigger
  -- https://github.com/elihunter173/dirbuf.nvim/issues/48 on commit e004455
  pending("works with autochdir", function()
    vim.opt.autochdir = true
    feed("-")
    assert.is_not.same({ "" }, lines())
    vim.opt.autochdir = false
  end)
end)

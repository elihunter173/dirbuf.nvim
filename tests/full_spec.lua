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

local path

local function expect_lines(expected)
  assert.same(expected, api.nvim_buf_get_lines(0, 0, -1, true))
end

local function expect_directory(expected)
  assert.same(expected, scan_directory(path))
end

local function open_dirbuf_of(directory)
  path = assert(uv.fs_mkdtemp("/tmp/dirbuf-XXXXXX"))
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

-- TODO: Figure out how to use feedkeys
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
  end)
end)

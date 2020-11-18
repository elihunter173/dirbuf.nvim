local md5 = require("vendor.md5")

local M = {}

local Dirbuf = {}

function Dirbuf:new(o)
  setmetatable(o, self)
  self.__index = self
  return o
end

local HASH_LEN = 7
local function parse_line(line)
  local fname, hash = line:match("^'([^']+)'%s*#(%x%x%x%x%x%x%x)$")
  return fname, hash
end

function M.debug()
  print(vim.inspect(vim.b.dirbuf))
end

function M.println(lineno)
  local line = vim.fn.getline(lineno)
  local fname, hash = parse_line(line)
  print(hash .. " = " .. vim.inspect(vim.b.dirbuf.file_info[hash]))
end

-- TODO: Conditionally split based on whether bang is there or not
function M.open(dir)
  if dir == "" then
    dir = "."
  end

  local handle, err, _ = vim.loop.fs_scandir(dir)
  if err ~= nil then
    vim.api.nvim_err_writeln(err)
    return
  end

  -- create a scratch buffer
  local buf = vim.api.nvim_create_buf(true, true)
  assert(buf ~= 0)

  -- Fill out buffer
  local buf_lines = {}
  local file_info = {}
  while true do
    local fname, ftype = vim.loop.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if ftype == "directory" then
      fname = fname .. "/"
    end

    local line = {"'", fname, "'"}
    local hash = md5.sumhexa(fname):sub(1, HASH_LEN)
    file_info[hash] = {
      fname = fname,
      ftype = ftype,
    }
    table.insert(line, "        #" .. hash)
    table.insert(buf_lines, table.concat(line))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)

  -- Add keymaps
  -- TODO: Should this be an ftplugin? Probably...
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<cmd>lua require('dirbuf').enter()<cr>", {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, "n", "gd",   "<cmd>DirbufPrintln<cr>", {noremap = true, silent = true})

  -- Buffer is finished. Show it
  vim.api.nvim_win_set_buf(0, buf)

  -- TODO: When should I do this?
  vim.api.nvim_command("cd " .. dir)

  -- Has to be after we focus the buffer
  -- TODO: Is there a better way to do this?
  vim.b.dirbuf = Dirbuf:new {
    file_info = file_info,
    buf = buf,
  }
end

function M.enter()
  -- TODO: Is there a better way to do this?
  local line = vim.fn.getline(".")
  local fname, hash = parse_line(line)
  assert(vim.b.dirbuf.file_info[hash].ftype == "directory")
  M.open(fname)
end

return M

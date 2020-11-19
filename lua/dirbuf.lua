local md5 = require("vendor.md5")

local M = {}

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

-- TODO: I need to determine how to save the previous cdpath and restore it when the dirbuf is exited
-- TODO: Conditionally split based on whether bang is there or not. Or do I even want this?
-- TODO: Name the buffer after the directory
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
  -- TODO: Maybe add a ../ at the top? Not sold in the idea
  local buf_lines = {}
  local file_info = {}
  local max_len = 0
  while true do
    local fname, ftype = vim.loop.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if ftype == "directory" then
      fname = fname .. "/"
    end

    -- TODO: Maybe don't always quote like this?
    local line = vim.fn.shellescape(fname)
    local hash = md5.sumhexa(fname):sub(1, HASH_LEN)
    file_info[hash] = {
      fname = fname,
      ftype = ftype,
    }
    table.insert(buf_lines, {line, nil, "  #"..hash})
    if #line > max_len then
      max_len = #line
    end
  end
  for key, tuple in pairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[key] = table.concat(tuple)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)

  -- Add keymaps
  -- TODO: Should this be an ftplugin? Probably...
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<cmd>lua require('dirbuf').enter()<cr>", {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, "n", "gd",   "<cmd>DirbufPrintln<cr>", {noremap = true, silent = true})

  vim.api.nvim_buf_set_option(buf, "filetype", "dirbuf")

  -- TODO: When should I do this? It needs to be after we iterate over the dirs
  vim.api.nvim_command("cd " .. dir)

  -- Buffer is finished. Show it
  vim.api.nvim_win_set_buf(0, buf)

  -- Has to be after we focus the buffer
  vim.b.dirbuf = {
    file_info = file_info,
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

--[[
Support for nvim-web-devicons
--]]


local M = {}

function M.has_devicons()
  local ok, has = pcall(require, "nvim-web-devicons")
  return ok
end

function M.get_icon(fname, ftype)
  local devicons = require('nvim-web-devicons')
  if ftype == "file" then
    local ext = vim.fn.fnamemodify(fname, ":e")
    return devicons.get_icon(fname, ext, {default = true})
  elseif ftype == "directory" then
    return ""
  else
    return devicons.get_icon(fname, "", {default = true})
  end
end

return M

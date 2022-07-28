--[[
Support for nvim-web-devicons
--]]

local devicons = require('nvim-web-devicons')

local M = {}

function M.has_devicons()
  return assert(devicons.has_loaded(), "Devicons not found for dirbuf.nvim")
end

function M.get_icon(fname, ftype)
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

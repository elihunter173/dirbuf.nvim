local M = {}

function M.errorf(...)
  error(string.format(...), 2)
end

return M

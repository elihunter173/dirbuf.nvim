local M = {}

-- Default config settings
local conf = {hash_padding = 2, show_hidden = true}

function M.update(opts)
  if opts.hash_padding ~= nil then
    local val = opts.hash_padding
    if type(val) ~= "number" or math.floor(val) ~= val or val < 1 then
      return "`hash_padding` must be an integer larger than 1"
    end
    conf.hash_padding = val
  end

  if opts.show_hidden ~= nil then
    local val = opts.show_hidden
    if type(val) ~= "boolean" then
      return "`show_hidden` must be boolean, received " .. type(val)
    end
    conf.show_hidden = opts.show_hidden
  end

  return nil
end

function M.get(opt)
  return conf[opt]
end

return M

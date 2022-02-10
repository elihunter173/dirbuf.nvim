local M = {}

local function sort_default(left, right)
  return left.fname:lower() < right.fname:lower()
end

local function sort_directories_first(left, right)
  if left.ftype ~= right.ftype then
    return left.ftype < right.ftype
  else
    return left.fname:lower() < right.fname:lower()
  end
end

-- Default config settings
local conf = { hash_padding = 2, show_hidden = true, sort_order = sort_default }

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
    conf.show_hidden = val
  end

  if opts.sort_order ~= nil then
    local val = opts.sort_order
    -- Preprocess string value
    if type(val) == "string" then
      if val == "default" then
        val = sort_default
      elseif val == "directories_first" then
        val = sort_directories_first
      else
        return "Unrecognized `sort_order` "
          .. vim.inspect(val)
          .. '. Expected "default", "directories_first", or function'
      end
    end
    if type(val) ~= "function" then
      return "`sort_order` must be function, received " .. type(val)
    end
    conf.sort_order = val
  end

  return nil
end

function M.get(opt)
  return conf[opt]
end

return M

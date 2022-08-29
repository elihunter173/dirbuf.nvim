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

local CONFIG_SPEC = {
  hash_padding = {
    default = 2,
    check = function(val)
      if type(val) ~= "number" or math.floor(val) ~= val or val < 1 then
        return "must be integer larger than 1"
      end
    end,
  },
  show_hidden = {
    default = true,
    check = function(val)
      if type(val) ~= "boolean" then
        return "must be boolean, received " .. type(val)
      end
    end,
  },
  sort_order = {
    default = sort_default,
    check = function(val)
      if val == "default" then
        return nil, sort_default
      elseif val == "directories_first" then
        return nil, sort_directories_first
      elseif type(val) == "function" then
        return nil, val
      else
        return 'must be one of "default", "directories_first", or function'
      end
    end,
  },
  write_cmd = {
    default = "DirbufSync",
    check = function(val)
      if type(val) ~= "string" then
        return "must be string, received " .. type(val)
      end
    end,
  },
  devicons = {
    default = false,
    check = function(val)
      if require('dirbuf.devicons').has_devicons() ~= true and val == true then
        return "nvim-web-devicons not installed"
      end
      if type(val) ~= "boolean" then
        return "must be boolean, received " .. type(val)
      end
    end,
  },
}

local user_config = {}

function M.update(opts)
  local errors = {}

  for option_name, spec in pairs(CONFIG_SPEC) do
    local val = opts[option_name]
    if val == nil then
      -- Don't check unset options
      user_config[option_name] = nil
    else
      local err, converted = spec.check(val)
      if err ~= nil then
        table.insert(errors, string.format("`%s` %s", option_name, err))
      elseif converted == nil then
        user_config[option_name] = val
      else
        user_config[option_name] = converted
      end
    end
  end

  local unknown_options = {}
  for key, _ in pairs(opts) do
    if CONFIG_SPEC[key] == nil then
      table.insert(unknown_options, "`" .. key .. "`")
    end
  end
  if #unknown_options > 0 then
    table.insert(errors, table.concat(unknown_options, ", ") .. " not recognized")
  end

  return errors
end

function M.get(opt)
  -- Ensure we don't typo options
  if CONFIG_SPEC[opt] == nil then
    error("Unrecognized option: " .. opt)
  end
  if user_config[opt] == nil then
    return CONFIG_SPEC[opt].default
  else
    return user_config[opt]
  end
end

return M

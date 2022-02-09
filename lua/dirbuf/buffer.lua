local uv = vim.loop

local config = require("dirbuf.config")
local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

--[[
local record Dirbuf
  dir: string
  fstates: {string: FState}
end
--]]

local function is_suffix(c)
  return
      c == "/" or c == "\\" or c == "@" or c == "|" or c == "=" or c == "%" or c ==
          "#"
end

-- These suffixes are taken from `ls --classify` and zsh's tab completion
local function suffix_to_ftype(suffix)
  if suffix == nil then
    return "file"
  elseif suffix == "/" or suffix == "\\" then
    return "directory"
  elseif suffix == "@" then
    return "link"
  elseif suffix == "|" then
    return "fifo"
  elseif suffix == "=" then
    return "socket"
  elseif suffix == "%" then
    return "char"
  elseif suffix == "#" then
    return "block"
  else
    error(string.format(
              "Unrecognized suffix %s. This should be impossible and is a bug in dirbuf.",
              vim.inspect(suffix)))
  end
end

local function ftype_to_suffix(ftype)
  if ftype == "file" then
    return ""
  elseif ftype == "directory" then
    return fs.path_separator
  elseif ftype == "link" then
    return "@"
  elseif ftype == "fifo" then
    return "|"
  elseif ftype == "socket" then
    return "="
  elseif ftype == "char" then
    return "%"
  elseif ftype == "block" then
    return "#"
  else
    error(string.format(
              "Unrecognized ftype %s. This should be impossible and is a bug in dirbuf",
              vim.inspect(ftype)))
  end
end

local function parse_fname(chars)
  local string_builder = {}

  local last_suffix = nil
  while true do
    local c = chars()
    if c == nil or c == "\t" then
      break
    end

    if last_suffix ~= nil then
      -- This suffix wasn't it :)
      table.insert(string_builder, last_suffix)
    end

    if c == "\\" then
      local next_c = chars()
      if next_c == nil or next_c == "\t" then
        -- `c` was a terminal backslash
        last_suffix = "\\"
        break
      end

      -- Convert escape sequence
      if next_c == "\\" then
        last_suffix = nil
        table.insert(string_builder, next_c)
      elseif next_c == "t" then
        last_suffix = nil
        table.insert(string_builder, "\t")
      else
        return string.format("Invalid escape sequence '\\%s'", next_c)
      end

    elseif is_suffix(c) then
      last_suffix = c

    else
      last_suffix = nil
      table.insert(string_builder, c)
    end
  end

  if #string_builder > 0 then
    local fname = table.concat(string_builder)
    local ftype = suffix_to_ftype(last_suffix)
    return nil, fname, ftype
  else
    return nil, nil, nil
  end
end

local function parse_hash(chars)
  local c = chars()
  if c == nil then
    -- Ended line before hash
    return nil, nil
  elseif c ~= "#" then
    return string.format("Unexpected character '%s' after fname", c)
  end

  local string_builder = {}
  for _ = 1, fs.HASH_LEN do
    c = chars()
    if c == nil then
      return "Unexpected end of line in hash"
    elseif not c:match("%x") then
      return string.format("Invalid hash character '%s'", c)
    else
      table.insert(string_builder, c)
    end
  end
  return nil, table.concat(string_builder)
end

-- The language of valid dirbuf lines is regular, so normally I would use a
-- regular expression. However, Lua doesn't have a proper regex engine, just
-- simpler patterns. These patterns can't parse dirbuf lines (b/c of escaping),
-- so I manually build the parser. It also gives nicer error messages.
--
-- Returns err, hash, fname, ftype
function M.parse_line(line)
  local chars = line:gmatch(".")

  local err, fname, ftype = parse_fname(chars)
  if err ~= nil then
    return err
  end

  local hash
  err, hash = parse_hash(chars)
  if err ~= nil then
    return err
  end

  -- Consume trailing whitespace
  while true do
    local c = chars()
    if c == nil then
      break
    elseif not c:match("%s") then
      return string.format("Unexpected character '%s' after hash", c)
    end
  end

  return nil, hash, fname, ftype
end

function M.display_fstate(fstate)
  local escaped = fstate.fname:gsub("\\", "\\\\"):gsub("\t", "\\t")
  return escaped .. ftype_to_suffix(fstate.ftype)
end

function M.write_dirbuf(dirbuf, track_fname)
  -- TODO: This would be cleaner if we stored dirbufs with an index instead of
  -- a key that was sorted in sort_order to begin with. This would also prevent
  -- the issue where hashes can collide
  local ir = {}
  for hash, fstate in pairs(dirbuf.fstates) do
    table.insert(ir, {fstate, hash})
  end
  local comp = config.get("sort_order")
  table.sort(ir, function(l, r)
    return comp(l[1], r[1])
  end)

  local fname_line = nil
  for lnum, fstate_hash in ipairs(ir) do
    if fstate_hash[1].fname == track_fname then
      fname_line = lnum
    end
  end

  local buf_lines = {}
  local max_len = 0
  for _, fstate_hash in ipairs(ir) do
    local fstate, hash = unpack(fstate_hash)
    local display = M.display_fstate(fstate)
    if #display > max_len then
      max_len = #display
    end
    table.insert(buf_lines, display .. "\t#" .. hash)
  end

  return buf_lines, max_len, fname_line
end

function M.create_dirbuf(dir, show_hidden)
  local dirbuf = {dir = dir, fstates = {}}

  local handle, err, _ = uv.fs_scandir(dir)
  if handle == nil then
    return err
  end

  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if not show_hidden and fs.is_hidden(fname) then
      goto continue
    end

    local fstate = FState.new(fname, dir, ftype)
    local hash = FState.hash(fstate)
    if dirbuf.fstates[hash] ~= nil then
      -- This should never happen
      error(string.format("Colliding hashes '%s' with '%s' and '%s'", hash,
                          dirbuf.fstates[hash].path, fstate.path))
    end
    dirbuf.fstates[hash] = fstate

    ::continue::
  end

  return nil, dirbuf
end

return M

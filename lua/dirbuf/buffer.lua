local uv = vim.loop

local config = require("dirbuf.config")
local fs = require("dirbuf.fs")
local index = require("dirbuf.index")
local FSEntry = fs.FSEntry

local M = {}

M.HASH_LEN = 8

--[[
local record Dirbuf
  dir: string
  fs_entries: {string: FSEntry}
end
--]]

local function is_suffix(c)
  return c == "/" or c == "\\" or c == "@" or c == "|" or c == "=" or c == "%" or c == "#"
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
    error(
      string.format("Unrecognized suffix %s. This should be impossible and is a bug in dirbuf.", vim.inspect(suffix))
    )
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
    error(string.format("Unrecognized ftype %s. This should be impossible and is a bug in dirbuf", vim.inspect(ftype)))
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
      last_suffix = nil
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
        return string.format("Invalid escape sequence %s", vim.inspect(c .. next_c))
      end
    elseif is_suffix(c) then
      last_suffix = c
    else
      table.insert(string_builder, c)
    end
  end

  if #string_builder == 0 and last_suffix ~= nil then
    table.insert(string_builder, last_suffix)
    last_suffix = nil
  end

  if #string_builder > 0 then
    local fname = table.concat(string_builder)
    local ftype = suffix_to_ftype(last_suffix)
    return nil, fname, ftype
  else
    return nil, nil, nil
  end
end

local function parse_id(chars)
  local c = chars()
  if c == nil then
    -- Ended line before hash
    return nil, nil
  elseif c ~= "#" then
    return string.format("Unexpected character %s after fname", vim.inspect(c))
  end

  local string_builder = {}
  for _ = 1, M.HASH_LEN do
    c = chars()
    if c == nil then
      return "Unexpected end of line in hash"
    elseif not c:match("%x") then
      return string.format("Invalid hash character %s", vim.inspect(c))
    else
      table.insert(string_builder, c)
    end
  end
  return nil, table.concat(string_builder)
end

-- The language of valid dirbuf lines is regular, so normally I would use
-- regex. However, Lua's patterns cannot parse dirbuf lines because of escaping
-- and I want better error messages, so I parse lines by hand.
--
-- Returns err, hash, fname, ftype
function M.parse_line(line, opts)
  local chars = line:gmatch(".")

  if opts.hash_first then
    -- We throw away the error because if there's an error in parsing the hash,
    -- we treat the whole thing as an fname
    local _, hash = parse_id(chars)
    if hash == nil or chars() ~= "\t" then
      hash = nil
      chars = line:gmatch(".")
    end

    local err, fname, ftype = parse_fname(chars)
    if err ~= nil then
      return err
    end

    -- Ensure that we parsed the whole line
    local c = chars()
    if c ~= nil then
      return string.format("Unexpected character %s after fname", vim.inspect(c))
    end

    return nil, hash, fname, ftype
  else
    local err, fname, ftype = parse_fname(chars)
    if err ~= nil then
      return err
    end

    local hash
    err, hash = parse_id(chars)
    if err ~= nil then
      return err
    end

    -- Consume trailing whitespace
    while true do
      local c = chars()
      if c == nil then
        break
      elseif not c:match("%s") then
        return string.format("Unexpected character %s after hash", vim.inspect(c))
      end
    end

    return nil, hash, fname, ftype
  end
end

function M.display_fs_entry(fs_entry)
  local escaped = fs_entry.fname:gsub("\\", "\\\\"):gsub("\t", "\\t")
  return escaped .. ftype_to_suffix(fs_entry.ftype)
end

function M.write_fs_entries(fs_entries, opts, track_fname)
  local ir = {}
  for id, fs_entry in pairs(fs_entries) do
    table.insert(ir, { id, fs_entry })
  end
  local comp = config.get("sort_order")
  table.sort(ir, function(l, r)
    return comp(l[2], r[2])
  end)

  local fname_line = nil
  for lnum, id_fs_entry in ipairs(ir) do
    if id_fs_entry[2].fname == track_fname then
      fname_line = lnum
      break
    end
  end

  local buf_lines = {}
  local max_len = 0
  for _, id_fs_entry in ipairs(ir) do
    local id = id_fs_entry[1]
    local display = M.display_fs_entry(id_fs_entry[2])
    if #display > max_len then
      max_len = #display
    end
    if opts.hash_first then
      table.insert(buf_lines, "#" .. id .. "\t" .. display)
    else
      table.insert(buf_lines, display .. "\t#" .. id)
    end
  end

  return buf_lines, max_len, fname_line
end

function M.get_fs_entries(dir, show_hidden)
  local fs_entries = {}

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

    local fs_entry = FSEntry.new(fname, dir, ftype)
    local id = index.path_ids[fs_entry.path]
    if id == nil then
      table.insert(index.fs_entries, fs_entry)
      id = #index.fs_entries
      index.path_ids[fs_entry.path] = id
    end
    local hash = string.format("%08x", id)
    fs_entries[hash] = fs_entry

    ::continue::
  end

  return nil, fs_entries
end

return M

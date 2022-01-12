local uv = vim.loop

local M = {}

local FNV_PRIME = 16777619
local FNV_OFFSET_BASIS = 2166136261

-- We use 4 byte hashes
M.HASH_LEN = 8
local HASH_MAX = 256 * 256 * 256 * 256

-- 32 bit FNV-1a hash that is cut to the least significant 4 bytes.
local function hash(str)
  local h = FNV_OFFSET_BASIS
  for c in str:gmatch(".") do
    h = bit.bxor(h, c:byte())
    h = h * FNV_PRIME
  end
  return string.format("%08x", h % HASH_MAX)
end

-- This was borrowed from util.lua in packer.nvim
if jit ~= nil then
  M.is_windows = jit.os == "Windows"
else
  M.is_windows = package.config:sub(1, 1) == "\\"
end
if M.is_windows then
  M.path_separator = "\\"
else
  M.path_separator = "/"
end

function M.join(...)
  local paths = {...}
  return table.concat(paths, M.path_separator)
end

function M.temppath()
  return vim.fn.tempname()
end

M.FState = {}
local FState = M.FState

function FState.new(fname, parent, ftype)
  local o = {fname = fname, path = M.join(parent, fname), ftype = ftype}
  setmetatable(o, {__index = FState})
  return o
end

-- FTypes are taken from
-- https://github.com/tbastos/luv/blob/2fed9454ebb870548cef1081a1f8a3dd879c1e70/src/fs.c#L420-L430
--[[
local enum FType
  "file"
  "directory"
  "link"
  "fifo"
  "socket"
  "char"
  "block"
end
--]]
function FState.from_dispname(dispname, parent)
  -- This is the last byte as a string, which is okay because all our
  -- classifiers are single characters
  local last_char = dispname:sub(-1, -1)
  if last_char == "/" then
    return FState.new(dispname:sub(0, -2), parent, "directory")
  elseif last_char == "@" then
    return FState.new(dispname:sub(0, -2), parent, "link")
  elseif last_char == "|" then
    return FState.new(dispname:sub(0, -2), parent, "fifo")
  elseif last_char == "=" then
    return FState.new(dispname:sub(0, -2), parent, "socket")
  elseif last_char == "%" then
    return FState.new(dispname:sub(0, -2), parent, "char")
  elseif last_char == "#" then
    return FState.new(dispname:sub(0, -2), parent, "block")
  else
    return FState.new(dispname, parent, "file")
  end
end

function M.fname_to_dispname(fname, ftype)
  if ftype == "file" then
    return fname
  elseif ftype == "directory" then
    return fname .. "/"
  elseif ftype == "link" then
    return fname .. "@"
  elseif ftype == "fifo" then
    return fname .. "|"
  elseif ftype == "socket" then
    return fname .. "="
  elseif ftype == "char" then
    return fname .. "%"
  elseif ftype == "block" then
    return fname .. "#"
  else
    error(string.format("Unrecognized ftype '%s'. This should be impossible",
                        vim.inspect(ftype)))
  end
end

-- Add the appropriate classifier for the given ftype. These classifiers are
-- taken from `ls --classify` and zsh's tab completion
function FState:dispname()
  return M.fname_to_dispname(self.fname, self.ftype)
end

function FState:hash()
  return hash(self.path)
end

M.plan = {}
M.actions = {}

function M.plan.create(fstate)
  return {type = "create", fstate = fstate}
end

local DEFAULT_FILE_MODE = tonumber("644", 8)
-- Directories have to be executable for you to chdir into them
local DEFAULT_DIR_MODE = tonumber("755", 8)
function M.actions.create(args)
  local fstate = args.fstate

  -- FIXME: This is a TOCTOU
  if uv.fs_access(fstate.path, "W") then
    return string.format("'%s' already exists", fstate.ftype, fstate.path)
  end

  local ok
  if fstate.ftype == "file" then
    -- append instead of write to be non-dstructive
    ok = uv.fs_open(fstate.path, "a", DEFAULT_FILE_MODE)
  elseif fstate.ftype == "directory" then
    ok = uv.fs_mkdir(fstate.path, DEFAULT_DIR_MODE)
  else
    return string.format("Cannot create %s", fstate.ftype)
  end

  if not ok then
    return string.format("Create failed for '%s'", fstate.path)
  end

  return nil
end

local function cp(src_path, dst_path, ftype)
  if ftype == "directory" then
    local ok, err, _ = uv.fs_mkdir(dst_path, DEFAULT_DIR_MODE)
    if not ok then
      return err
    end

    local handle = uv.fs_scandir(src_path)
    while true do
      local next_fname, next_ftype = uv.fs_scandir_next(handle)
      if next_fname == nil then
        break
      end
      err = cp(M.join(src_path, next_fname), M.join(dst_path, next_fname),
               next_ftype)
      if err ~= nil then
        return err
      end
    end

  else
    local ok, err, _ = uv.fs_copyfile(src_path, dst_path)
    if not ok then
      return err
    end
    return nil
  end
end

function M.plan.copy(src_fstate, dst_fstate)
  return {type = "copy", src_fstate = src_fstate, dst_fstate = dst_fstate}
end

function M.actions.copy(args)
  local src_fstate, dst_fstate = args.src_fstate, args.dst_fstate
  -- We have ensured that the fstates are the same in plan.copy
  return cp(src_fstate.path, dst_fstate.path, src_fstate.ftype)
end

local function rm(path, ftype)
  if ftype == "directory" then
    local handle = uv.fs_scandir(path)
    while true do
      local next_fname, next_ftype = uv.fs_scandir_next(handle)
      if next_fname == nil then
        break
      end
      local err = rm(M.join(path, next_fname), next_ftype)
      if err ~= nil then
        return err
      end
    end
    local ok, err, _ = uv.fs_rmdir(path)
    if not ok then
      return err
    end
    return nil

  else
    local ok, err, _ = uv.fs_unlink(path)
    if not ok then
      return err
    end
    return nil
  end
end

function M.plan.delete(fstate)
  return {type = "delete", fstate = fstate}
end

function M.actions.delete(args)
  local fstate = args.fstate
  return rm(fstate.path, fstate.ftype)
end

function M.plan.move(src_path, dst_path)
  return {type = "move", src_path = src_path, dst_path = dst_path}
end

function M.actions.move(args)
  local src_path, dst_path = args.src_path, args.dst_path
  -- FIXME: This is a TOCTOU
  if uv.fs_access(dst_path, "W") then
    return string.format("File at '%s' already exists", dst_path)
  end
  local ok, err, _ = uv.fs_rename(src_path, dst_path)
  if not ok then
    return
        string.format("Move failed for %s -> %s: %s", src_path, dst_path, err)
  end
end

return M

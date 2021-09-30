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

function M.join(...)
  local paths = {...}
  return table.concat(paths, "/")
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

-- TODO: Do all classifiers from here
-- https://unix.stackexchange.com/questions/82357/what-do-the-symbols-displayed-by-ls-f-mean#82358
-- with types from
-- https://github.com/tbastos/luv/blob/2fed9454ebb870548cef1081a1f8a3dd879c1e70/src/fs.c#L420-L430
function M.dispname_to_fname(dispname)
  local last_char = dispname:sub(-1, -1)
  if last_char == "/" then
    return dispname:sub(0, -2)
  elseif last_char == "@" then
    return dispname:sub(0, -2)
  elseif last_char == "=" then
    return dispname:sub(0, -2)
  elseif last_char == "|" then
    return dispname:sub(0, -2)
  else
    return dispname
  end
end

function FState.from_dispname(dispname, parent)
  -- This is the last byte as a string, which is okay because all our
  -- identifiers are single characters
  local last_char = dispname:sub(-1, -1)
  if last_char == "/" then
    return FState.new(dispname:sub(0, -2), parent, "directory")
  elseif last_char == "@" then
    return FState.new(dispname:sub(0, -2), parent, "link")
  elseif last_char == "=" then
    return FState.new(dispname:sub(0, -2), parent, "socket")
  elseif last_char == "|" then
    return FState.new(dispname:sub(0, -2), parent, "fifo")
  else
    return FState.new(dispname, parent, "file")
  end
end

function FState:dispname()
  if self.ftype == "file" then
    return self.fname
  elseif self.ftype == "directory" then
    return self.fname .. "/"
  elseif self.ftype == "link" then
    return self.fname .. "@"
  elseif self.ftype == "socket" then
    return self.fname .. "="
  elseif self.ftype == "fifo" then
    return self.fname .. "|"
  else
    -- Should I just assume it's a file??
    error(string.format("Unrecognized ftype '%s'. This should be impossible",
                        vim.inspect(self.ftype)))
  end
end

function FState:hash()
  return hash(self.path)
end

M.plan = {}
M.actions = {}

-- TODO: Create actions.{move, copy, create, delete} methods instead of relying
-- on tables in planner

function M.plan.create(fstate)
  return {type = "create", fstate = fstate}
end

local DEFAULT_FILE_MODE = tonumber("644", 8)
-- Directories have to be executable for you to chdir into them
local DEFAULT_DIR_MODE = tonumber("755", 8)
function M.actions.create(args)
  local fstate = args.fstate

  -- TODO: This is a TOCTOU
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
    return string.format("Unsupported ftype: %s", fstate.ftype)
  end

  if not ok then
    return string.format("Create failed for '%s'", fstate.path)
  end

  return nil
end

function M.plan.copy(src_path, dst_path)
  return {type = "copy", src_path = src_path, dst_path = dst_path}
end

function M.actions.copy(args)
  local src_path, dst_path = args.src_path, args.dst_path
  -- TODO: Support copying directories. Needs keeping around fstates
  local ok = uv.fs_copyfile(src_path, dst_path, nil)
  if not ok then
    return string.format("Copy failed for '%s' -> '%s'", src_path, dst_path)
  end

  return nil
end

local function rm(path, ftype)
  if ftype == "file" or ftype == "symlink" then
    local ok, err, _ = uv.fs_unlink(path)
    if ok then
      return nil
    else
      return err
    end

  elseif ftype == "directory" then
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
    if ok then
      return nil
    else
      return err
    end

  else
    return "Unrecognized ftype"
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
  -- TODO: This is a TOCTOU
  if uv.fs_access(dst_path, "W") then
    return string.format("File at '%s' already exists", dst_path)
  end
  local ok, err, _ = uv.fs_rename(src_path, dst_path)
  if not ok then
    return string.format("Move failed for %s -> %s: %s", src_path, dst_path, err)
  end
end

return M

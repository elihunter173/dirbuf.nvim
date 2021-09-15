local uv = vim.loop

local errorf = require("dirbuf.utils").errorf

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
    errorf("unrecognized ftype %s", vim.inspect(self.ftype))
  end
end

function FState:hash()
  return hash(self.path)
end

M.actions = {}

local DEFAULT_FILE_MODE = tonumber("644", 8)
-- Directories have to be executable for you to chdir into them
local DEFAULT_DIR_MODE = tonumber("755", 8)
function M.actions.create(args)
  local fstate = args.fstate

  -- TODO: This is a TOCTOU
  if uv.fs_access(fstate.path, "W") then
    errorf("%s at '%s' already exists", fstate.ftype, fstate.path)
  end

  local ok
  if fstate.ftype == "file" then
    -- append instead of write to be non-destructive
    ok = uv.fs_open(fstate.path, "a", DEFAULT_FILE_MODE)
  elseif fstate.ftype == "directory" then
    ok = uv.fs_mkdir(fstate.path, DEFAULT_DIR_MODE)
  else
    errorf("unsupported ftype: %s", fstate.ftype)
  end

  if not ok then
    errorf("create failed: %s", fstate.path)
  end
end

function M.actions.copy(args)
  local old_path, new_path = args.old_path, args.new_path
  -- TODO: Support copying directories. Needs keeping around fstates
  local ok = uv.fs_copyfile(old_path, new_path, nil)
  if not ok then
    errorf("copy failed: %s -> %s", old_path, new_path)
  end
end

-- TODO: Use err instead of return
local function rm(path, ftype)
  if ftype == "file" or ftype == "symlink" then
    return uv.fs_unlink(path)

  elseif ftype == "directory" then
    local handle = uv.fs_scandir(path)
    while true do
      local next_fname, next_ftype = uv.fs_scandir_next(handle)
      if next_fname == nil then
        break
      end
      local ok, err, name = rm(M.join(path, next_fname), next_ftype)
      if not ok then
        return ok, err, name
      end
    end
    return uv.fs_rmdir(path)

  else
    return false, "unrecognized ftype", "dirbuf_internal"
  end
end

function M.actions.delete(args)
  local fstate = args.fstate
  local ok, err, _ = rm(fstate.path, fstate.ftype)
  if not ok then
    errorf("delete failed: %s", err)
  end
end

function M.actions.move(args)
  local old_path, new_path = args.old_path, args.new_path
  -- TODO: This is a TOCTOU
  if uv.fs_access(new_path, "W") then
    errorf("file at '%s' already exists", new_path)
  end
  local ok = uv.fs_rename(old_path, new_path)
  if not ok then
    errorf("move failed: %s -> %s", old_path, new_path)
  end
end

return M

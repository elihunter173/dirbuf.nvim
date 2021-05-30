local uv = vim.loop

local errorf = require("dirbuf.utils").errorf
local md5 = require("dirbuf.md5")

local M = {}

M.FState = {}
local FState = M.FState

function FState.new(fname, ftype)
  local o = {fname = fname, ftype = ftype}
  setmetatable(o, FState)
  return o
end

function FState.from_dispname(dispname)
  -- This is the last byte as a string, which is okay because all our
  -- identifiers are single characters
  local last_char = dispname:sub(-1, -1)
  if last_char == "/" then
    return FState.new(dispname:sub(0, -2), "directory")
  elseif last_char == "@" then
    return FState.new(dispname:sub(0, -2), "link")
  else
    return FState.new(dispname, "file")
  end
end

function FState:dispname()
  -- TODO: Do all classifiers from here
  -- https://unix.stackexchange.com/questions/82357/what-do-the-symbols-displayed-by-ls-f-mean#82358
  -- with types from
  -- https://github.com/tbastos/luv/blob/2fed9454ebb870548cef1081a1f8a3dd879c1e70/src/fs.c#L420-L430
  if self.ftype == "file" then
    return self.fname
  elseif self.ftype == "directory" then
    return self.fname .. "/"
  elseif self.ftype == "link" then
    return self.fname .. "@"
  else
    -- Should I just assume it's a file??
    errorf("unrecognized ftype %s", vim.inspect(self.ftype))
  end
end

M.HASH_LEN = 7
function FState:hash()
  return md5.sumhexa(self.fname):sub(1, M.HASH_LEN)
end

-- Directories have to be executable for you to chdir into them
local DEFAULT_FILE_MODE = tonumber("644", 8)
local DEFAULT_DIR_MODE = tonumber("755", 8)
function M.create(args)
  local fstate = args.fstate

  -- TODO: This is a TOCTOU
  if uv.fs_access(fstate.fname, "W") then
    errorf("%s at '%s' already exists", fstate.ftype, fstate.fname)
  end

  local ok
  if fstate.ftype == "file" then
    -- append instead of write to be non-destructive
    ok = uv.fs_open(fstate.fname, "a", DEFAULT_FILE_MODE)
  elseif fstate.ftype == "directory" then
    ok = uv.fs_mkdir(fstate.fname, DEFAULT_DIR_MODE)
  else
    errorf("unsupported ftype: %s", fstate.ftype)
  end

  if not ok then
    errorf("create failed: %s", fstate.fname)
  end
end

function M.copy(args)
  local old_fname, new_fname = args.old_fname, args.new_fname
  -- TODO: Support copying directories. Needs keeping around fstates
  local ok = uv.fs_copyfile(old_fname, new_fname, nil)
  if not ok then
    errorf("copy failed: %s -> %s", old_fname, new_fname)
  end
end

-- TODO: Use err instead of return
local function rm(fname, ftype)
  if ftype == "file" or ftype == "symlink" then
    return uv.fs_unlink(fname)

  elseif ftype == "directory" then
    local handle = uv.fs_scandir(fname)
    while true do
      local new_fname, new_ftype = uv.fs_scandir_next(handle)
      if new_fname == nil then
        break
      end
      local ok, err, name = rm(fname .. "/" .. new_fname, new_ftype)
      if not ok then
        return ok, err, name
      end
    end
    return uv.fs_rmdir(fname)
  else
    return false, "unrecognized ftype", "dirbuf_internal"
  end
end

function M.delete(args)
  local fstate = args.fstate
  local ok, err, _ = rm(fstate.fname, fstate.ftype)
  if not ok then
    errorf("delete failed: %s", err)
  end
end

function M.move(args)
  local old_fname, new_fname = args.old_fname, args.new_fname
  -- TODO: This is a TOCTOU
  if uv.fs_access(new_fname, "W") then
    errorf("file at '%s' already exists", new_fname)
  end
  local ok = uv.fs_rename(old_fname, new_fname)
  if not ok then
    errorf("move failed: %s -> %s", old_fname, new_fname)
  end
end

return M

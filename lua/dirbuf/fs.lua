local api = vim.api
local uv = vim.loop

local M = {}

M.path_separator = package.config:sub(1, 1)

function M.is_hidden(fname)
  return fname:sub(1, 1) == "."
end

function M.join_paths(...)
  local string_builder = {}
  for _, path in ipairs({ ... }) do
    if path:sub(-1, -1) == M.path_separator then
      path = path:sub(0, -2)
    end
    table.insert(string_builder, path)
  end
  return table.concat(string_builder, M.path_separator)
end

function M.is_directory(path)
  return vim.fn.isdirectory(path) == 1
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
local record FState
  fname: string
  ftype: FType
  path: string
end
--]]

M.FState = {}
local FState = M.FState

function FState.new(fname, parent, ftype)
  return { fname = fname, path = M.join_paths(parent, fname), ftype = ftype }
end

function FState.temp(ftype)
  local temppath = vim.fn.tempname()
  return {
    -- XXX: This technically violates fname's assumption that it is always a
    -- simple name and not a path
    fname = temppath,
    path = temppath,
    ftype = ftype,
  }
end

M.plan = {}
M.actions = {}

function M.plan.create(fstate)
  return { type = "create", fstate = fstate }
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

  if fstate.ftype == "file" then
    local fd, err = uv.fs_open(fstate.path, "w", DEFAULT_FILE_MODE)
    if fd == nil then
      return err
    end
    local success
    success, err = uv.fs_close(fd)
    if not success then
      return err
    end
  elseif fstate.ftype == "directory" then
    local success, err = uv.fs_mkdir(fstate.path, DEFAULT_DIR_MODE)
    if not success then
      return err
    end
  else
    return string.format("Cannot create %s", fstate.ftype)
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
      err = cp(M.join_paths(src_path, next_fname), M.join_paths(dst_path, next_fname), next_ftype)
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
  return { type = "copy", src_fstate = src_fstate, dst_fstate = dst_fstate }
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
      local err = rm(M.join_paths(path, next_fname), next_ftype)
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
  return { type = "delete", fstate = fstate }
end

function M.actions.delete(args)
  local fstate = args.fstate
  return rm(fstate.path, fstate.ftype)
end

function M.plan.move(src_fstate, dst_fstate)
  return { type = "move", src_fstate = src_fstate, dst_fstate = dst_fstate }
end

local function rename_loaded_buffers(old_path, new_path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if not api.nvim_buf_is_loaded(buf) then
      goto continue
    end

    -- api.nvim_buf_get_name() returns absolute path so no post-processing
    local buf_name = api.nvim_buf_get_name(buf)
    local exact_match = buf_name == old_path
    local child_match = vim.startswith(buf_name, old_path .. M.path_separator)
    if exact_match or child_match then
      api.nvim_buf_set_name(buf, new_path .. buf_name:sub(#old_path + 1))

      -- We have to :write! normal files to avoid `E13: File exists (add ! to
      -- override)` error when manually calling :write
      if api.nvim_buf_get_option(buf, "buftype") == "" then
        api.nvim_buf_call(buf, function()
          vim.cmd("silent! write!")
        end)
      end
    end

    ::continue::
  end
end

function M.actions.move(args)
  local src_fstate, dst_fstate = args.src_fstate, args.dst_fstate
  -- FIXME: This is a TOCTOU
  if uv.fs_access(dst_fstate.path, "W") then
    return string.format("File at '%s' already exists", dst_fstate.path)
  end
  local ok, err, _ = uv.fs_rename(src_fstate.path, dst_fstate.path)
  if not ok then
    return string.format("Move failed for %s -> %s: %s", src_fstate.path, dst_fstate.path, err)
  end

  rename_loaded_buffers(src_fstate.path, dst_fstate.path)
end

return M

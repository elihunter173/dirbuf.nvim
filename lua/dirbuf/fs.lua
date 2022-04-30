local api = vim.api
local uv = vim.loop

local config = require("dirbuf.config")
local index = require("dirbuf.index")

local M = {}

M.path_separator = package.config:sub(1, 1)

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

function M.is_hidden(fname)
  return fname:sub(1, 1) == "."
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
local record FSEntry
  fname: string
  ftype: FType
  path: string
end
--]]

M.FSEntry = {}
local FSEntry = M.FSEntry

function FSEntry.new(fname, parent, ftype)
  return { fname = fname, path = M.join_paths(parent, fname), ftype = ftype }
end

function FSEntry.temp(ftype)
  local temppath = vim.fn.tempname()
  return {
    -- XXX: This technically violates fname's assumption that it is alwaies a
    -- simple name and not a path
    fname = temppath,
    path = temppath,
    ftype = ftype,
  }
end

M.plan = {}
M.actions = {}

local DEFAULT_FILE_MODE = tonumber("644", 8)
-- Directories have to be executable for you to chdir into them
local DEFAULT_DIR_MODE = tonumber("755", 8)

local function ensure_directory(path)
  vim.fn.mkdir(path, "p", DEFAULT_DIR_MODE)
end

local function create(path, ftype)
  -- FIXME: This is a TOCTOU
  if uv.fs_access(path, "W") then
    return string.format("'%s' already exists", ftype, path)
  end

  if ftype == "file" then
    local fd, err = uv.fs_open(path, "w", DEFAULT_FILE_MODE)
    if fd == nil then
      return err
    end
    local ok
    ok, err = uv.fs_close(fd)
    if not ok then
      return err
    end
  elseif ftype == "directory" then
    local ok, err = uv.fs_mkdir(path, DEFAULT_DIR_MODE)
    if not ok then
      return err
    end
  else
    return string.format("Cannot create %s", ftype)
  end

  return nil
end

local function cp(src_path, dst_path, ftype, force)
  if force == nil then
    force = false
  end

  -- FIXME: This is a TOCTOU
  if not force and uv.fs_access(dst_path, "W") then
    return string.format("'%s' already exists", ftype, dst_path)
  end

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
      err = cp(M.join_paths(src_path, next_fname), M.join_paths(dst_path, next_fname), next_ftype, force)
      if err ~= nil then
        return err
      end
    end

    return nil
  elseif ftype == "link" then
    local src_points_to, err, _ = uv.fs_readlink(src_path)
    if src_points_to == nil then
      return err
    end
    local ok
    ok, err, _ = uv.fs_symlink(src_points_to, dst_path)
    if not ok then
      return err
    end

    return nil
  else
    local ok, err, _ = uv.fs_copyfile(src_path, dst_path)
    if not ok then
      return err
    end
    return nil
  end
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

local function mv(src_path, dst_path, ftype, force)
  if force == nil then
    force = false
  end

  -- FIXME: This is a TOCTOU
  if not force and uv.fs_access(dst_path, "W") then
    return string.format("'%s' already exists", dst_path)
  end
  local ok, err, err_type = uv.fs_rename(src_path, dst_path)

  if not ok and err_type == "EXDEV" then
    err = cp(src_path, dst_path, ftype, force)
    if err ~= nil then
      return err
    end
    err = rm(src_path, ftype)
    if err ~= nil then
      return err
    end
  elseif not ok then
    return err
  end

  return nil
end

local function is_child_of(maybe_child, parent)
  local exact_match = maybe_child == parent
  local child_match = vim.startswith(maybe_child, parent .. M.path_separator)
  return exact_match or child_match
end

-- `rename_loaded_buffers` finds all renamed buffers under `old_path` and
-- renames them to be under `new_path`.
local function rename_loaded_buffers(old_path, new_path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if not api.nvim_buf_is_loaded(buf) then
      goto continue
    end

    -- api.nvim_buf_get_name() returns absolute path so no post-processing
    local buf_name = api.nvim_buf_get_name(buf)
    if is_child_of(buf_name, old_path) then
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

-- `delete_loaded_buffers` finds all deleted buffers under `path` and replaces
-- them with their alternate buffer, or a [No Name] buffer if its alternate
-- buffer doesn't exist.
local function delete_loaded_buffers(path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if not api.nvim_buf_is_loaded(buf) then
      goto continue
    end

    -- api.nvim_buf_get_name() returns absolute path so no post-processing
    local buf_name = api.nvim_buf_get_name(buf)
    if is_child_of(buf_name, path) then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        api.nvim_win_call(win, function()
          local altbuf = vim.fn.bufnr("#")
          if api.nvim_buf_is_valid(altbuf) then
            api.nvim_win_set_buf(win, altbuf)
          else
            vim.cmd("enew!")
          end
        end)
      end
      api.nvim_buf_delete(buf, { force = true })
    end

    ::continue::
  end
end

function M.plan.create(fs_entry)
  return { type = "create", fs_entry = fs_entry }
end

function M.actions.create(args)
  local fs_entry = args.fs_entry
  local err = create(fs_entry.path, fs_entry.ftype)
  if err ~= nil then
    return string.format("Create failed for %s: %s", fs_entry.path, err)
  end
  return nil
end

function M.plan.copy(src_fs_entry, dst_fs_entry)
  return { type = "copy", src_fs_entry = src_fs_entry, dst_fs_entry = dst_fs_entry }
end

function M.actions.copy(args)
  local src_fs_entry, dst_fs_entry = args.src_fs_entry, args.dst_fs_entry
  -- planner ensures src and dst have same ftype
  local err = cp(src_fs_entry.path, dst_fs_entry.path, src_fs_entry.ftype)
  if err ~= nil then
    return string.format("Copy failed for %s -> %s: %s", src_fs_entry.path, dst_fs_entry.path, err)
  end
  return nil
end

function M.plan.delete(fs_entry)
  return { type = "delete", fs_entry = fs_entry }
end

function M.actions.delete(args)
  local fs_entry = args.fs_entry
  -- local err = rm(fs_entry.path, fs_entry.ftype)
  -- if err ~= nil then
  --   return string.format("Delete failed for %s: %s", fs_entry.path, err)
  -- end

  local id = index.path_ids[fs_entry.path]

  local trash = M.join_paths(vim.fn.stdpath("data"), "dirbuf", "trash")
  ensure_directory(trash)
  local err = mv(fs_entry.path, M.join_paths(trash, id), fs_entry.ftype, true)
  if err ~= nil then
    return string.format("Delete failed for %s: %s", fs_entry.path, err)
  end

  delete_loaded_buffers(fs_entry.path)

  return nil
end

function M.plan.move(src_fs_entry, dst_fs_entry)
  return { type = "move", src_fs_entry = src_fs_entry, dst_fs_entry = dst_fs_entry }
end

function M.actions.move(args)
  local src_fs_entry, dst_fs_entry = args.src_fs_entry, args.dst_fs_entry
  -- planner ensures src and dst have same ftype
  local err = mv(src_fs_entry.path, dst_fs_entry.path, src_fs_entry.ftype)
  if err ~= nil then
    return string.format("Move failed for %s -> %s: %s", src_fs_entry.path, dst_fs_entry.path, err)
  end
  rename_loaded_buffers(src_fs_entry.path, dst_fs_entry.path)
  return nil
end

return M

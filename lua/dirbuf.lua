local api = vim.api
local uv = vim.loop

local parse_line = require("dirbuf.parser").parse_line
local planner = require("dirbuf.planner")
local fs = require("dirbuf.fs")
local FState = fs.FState

local M = {}

local CURRENT_BUFFER = 0

-- fill_dirbuf fills buffer `buf` with the contents of its corresponding
-- directory. `buf` must have the name of a valid directory and its contents
-- must be a valid dirbuf.
--
-- If `preserve_order` is true, then the contents of `buf` are left untouched,
-- only deleting old lines and appending new lines to the end. `preserve_order`
-- defaults to false.
--
-- If `on_fname` is set, then the cursor will be put on the line corresponding
-- to `on_fname`.
--
-- Returns: err
local function fill_dirbuf(buf, preserve_order, on_fname)
  if preserve_order == nil then
    preserve_order = false
  end

  local dir = api.nvim_buf_get_name(buf)
  local hide_hidden = api.nvim_buf_get_var(buf, "dirbuf_hide_hidden")

  -- Used to preserve the ordering of lines. Each line is guaranteed to be used
  -- exactly once assuming the buffer contains no non-existent fnames.
  local dispname_lnums = {}
  local tail = #dispname_lnums + 1
  if preserve_order then
    for lnum, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, true)) do
      local err, fname, _ = parse_line(line)
      if err ~= nil then
        return string.format("Line %d: %s", lnum, err)
      end
      if hide_hidden and fname:sub(1, 1) == "." then
        goto continue
      end
      dispname_lnums[fname] = tail
      tail = tail + 1

      ::continue::
    end
  end

  local move_cursor_to = nil

  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    return err
  end
  -- Fill out buffer
  -- Stores file info by hash
  local fstates = {}
  -- Stores (fname_esc, padding, hash) tuples which we will join into strings
  -- later to form the buffer's lines. We fill in the padding at the end to
  -- line up the hashes.
  local buf_lines = {}
  -- Used to we can make all the hashes line up
  local max_len = 0
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if hide_hidden and fname:sub(1, 1) == "." then
      goto continue
    end

    local fstate = FState.new(fname, dir, ftype)
    local hash = fstate:hash()
    if fstates[hash] ~= nil then
      -- This should never happen
      error(string.format("Colliding hashes '%s' with '%s' and '%s'", hash,
                          fstates[hash].fname, fname))
    end
    fstates[hash] = fstate

    local dispname = fstate:dispname()
    -- TODO: Maybe move this to fs.lua?
    -- TODO: Test filenames with escaped slashes in them
    local dispname_esc = dispname:gsub("[ \\]", "\\%0")
    if #dispname_esc > max_len then
      max_len = #dispname_esc
    end
    local lnum = dispname_lnums[dispname]
    if lnum == nil then
      lnum = tail
      tail = tail + 1
    end
    buf_lines[lnum] = {dispname_esc, nil, "  #" .. hash}

    if fstate.fname == on_fname then
      move_cursor_to = lnum
    end

    ::continue::
  end
  -- Now fill in the padding in the (fname_esc, padding, hash) tuples with
  -- appropriate padding such that the hashes line up
  for idx, tuple in ipairs(buf_lines) do
    tuple[2] = string.rep(" ", max_len - #tuple[1])
    buf_lines[idx] = table.concat(tuple)
  end
  api.nvim_buf_set_lines(buf, 0, -1, true, buf_lines)
  api.nvim_buf_set_var(buf, "dirbuf", fstates)

  if move_cursor_to ~= nil then
    api.nvim_win_set_cursor(0, {move_cursor_to, 0})
  end

  -- Us filling the buffer counts as modifying it
  api.nvim_buf_set_option(buf, "modified", false)

  return nil
end

local function clean_path(path)
  -- XXX: `dir .. "/"` fixes issues with .. appearing in filepath if you do
  -- dirbuf.open(".."), but it makes '/' become '//'
  if path ~= "/" then
    return vim.fn.fnamemodify(path .. "/", ":p")
  else
    return path
  end
end

-- This buffer must be the currently focused buffer
function M.init_dirbuf(buf, preserve_order, on_fname)
  local dir = clean_path(api.nvim_buf_get_name(buf))
  api.nvim_buf_set_name(buf, dir)

  api.nvim_buf_set_option(buf, "filetype", "dirbuf")
  api.nvim_buf_set_option(buf, "buftype", "acwrite")
  api.nvim_buf_set_option(buf, "bufhidden", "hide")

  -- TODO: Make the default mode configurable
  local ok, _ = pcall(api.nvim_buf_get_var, "dirbuf_hide_hidden")
  if not ok then
    api.nvim_buf_set_var(buf, "dirbuf_hide_hidden", false)
  end

  fill_dirbuf(buf, preserve_order, on_fname)
end

function M.open(dir)
  if dir == "" then
    dir = "."
  end
  dir = clean_path(dir)

  -- XXX: This is really hard to understand. What I want is to get the current
  -- buffer's name and get the basepath of it. Ideally, expand("%:t") would
  -- work but if you are in a directory (ends with a /), then it returns
  -- nothing. Therefore, we have to do a hack to get the directory by looking
  -- at the parent, stripping the slash, and then getting the tail.
  local old_fname = vim.fn.expand("%:t")
  if old_fname == "" then
    old_fname = vim.fn.expand("%:p:h:t")
  end

  local buf = vim.fn.bufnr("^" .. dir .. "$")
  if buf == -1 then
    buf = api.nvim_create_buf(true, false)
    if buf == 0 then
      api.nvim_err_writeln("Failed to create buffer")
      return
    end
    api.nvim_buf_set_name(buf, dir)
  end

  api.nvim_win_set_buf(0, buf)
  M.init_dirbuf(buf, false, old_fname)
end

function M.enter()
  if api.nvim_buf_get_option(CURRENT_BUFFER, "modified") then
    api.nvim_err_writeln("Dirbuf must be saved first")
    return
  end

  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local line = api.nvim_get_current_line()
  local err, _, hash = parse_line(line)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  local fstate = vim.b.dirbuf[hash]
  -- We rely on the autocmd to open directories
  vim.cmd("silent edit " .. vim.fn.fnameescape(fs.join(dir, fstate.fname)))
end

-- Ensure that the directory has not changed since our last snapshot
local function check_dirbuf(buf)
  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  local handle, err, _ = uv.fs_scandir(dir)
  if err ~= nil then
    return err
  end

  local fstates = api.nvim_buf_get_var(buf, "dirbuf")
  local hide_hidden = api.nvim_buf_get_var(CURRENT_BUFFER, "dirbuf_hide_hidden")
  while true do
    local fname, ftype = uv.fs_scandir_next(handle)
    if fname == nil then
      break
    end
    if hide_hidden and fname:sub(1, 1) == "." then
      goto continue
    end

    -- TODO: Maybe I should have have a way to directly hash dir and fname?
    local fstate = FState.new(fname, dir, ftype)
    local snapshot = fstates[fstate:hash()]
    if snapshot == nil or snapshot.fname ~= fname or snapshot.ftype ~= ftype then
      return
          "Snapshot out of date with current directory. Run :edit! to refresh"
    end

    ::continue::
  end

  return nil
end

function M.sync()
  local err = check_dirbuf(CURRENT_BUFFER)
  if err ~= nil then
    api.nvim_err_writeln("Cannot save dirbuf: " .. err)
    return
  end

  -- Parse the buffer to determine what we need to do get directory and dirbuf
  -- in sync
  local fstates, transition_graph
  err, fstates, transition_graph = planner.build_changes(CURRENT_BUFFER)
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  local plan = planner.determine_plan(fstates, transition_graph)
  err = planner.execute_plan(plan)
  if err ~= nil then
    api.nvim_err_writeln("Error making changes: " .. err)
    api.nvim_err_writeln(
        "WARNING: Dirbuf in inconsistent state. Run :edit! to refresh")
    return
  end
  fill_dirbuf(CURRENT_BUFFER, true)
end

function M.toggle_hide()
  vim.b.dirbuf_hide_hidden = not vim.b.dirbuf_hide_hidden
  local dir = api.nvim_buf_get_name(CURRENT_BUFFER)
  -- We want to ensure that we are still hovering on the same line
  local err, dispname, _ = parse_line(vim.fn.getline("."))
  if err ~= nil then
    api.nvim_err_writeln(err)
    return
  end
  -- TODO: Should I have a function to do this directly? Probably because this
  -- a bit hacky
  local fname = FState.from_dispname(dispname, dir).fname
  -- TODO: Is it intuitive to have keep your cursor on the fname?
  fill_dirbuf(CURRENT_BUFFER, false, fname)
end

return M

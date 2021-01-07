local uv = vim.loop

local M = {}

local function errorf(...)
  error(string.format(...), 2)
end

local DEFAULT_MODE = tonumber("644", 8)
local function action_create(args)
  local fstate = args.fstate

  -- TODO: This is a TOCTOU
  if uv.fs_access(fstate.fname, "W") then
    errorf("%s at '%s' already exists", fstate.ftype, fstate.fname)
  end

  local ok
  if fstate.ftype == "file" then
    -- append instead of write to be non-destructive
    ok = uv.fs_open(fstate.fname, "a", DEFAULT_MODE)
  elseif fstate.ftype == "directory" then
    ok = uv.fs_mkdir(fstate.fname, DEFAULT_MODE)
  else
    errorf("unsupported ftype: %s", fstate.ftype)
  end

  if not ok then
    errorf("create failed: %s", fstate.fname)
  end
end

local function action_copy(args)
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

local function action_delete(args)
  local fstate = args.fstate
  local ok, err, _ = rm(fstate.fname, fstate.ftype)
  if not ok then
    errorf("delete failed: %s", err)
  end
end

local function action_move(args)
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

-- Given the current state of the directory, `old_state`, and the desired new
-- state of the directory, `new_state`, determine the most efficient series of
-- actions necessary to reach the desired state.
--
-- old_state: Map from file hash to current state of file
-- new_state: Map from file hash to list of new associated fstate
function M.determine_plan(fstates, transformation_graph)
  local plan = {}

  for hash, dst_fstates in pairs(transformation_graph) do
    if hash == "" then
      -- New hash, so it's a new file
      for _, fstate in ipairs(dst_fstates) do
        table.insert(plan, {fn = action_create, fstate = fstate})
      end

    elseif next(dst_fstates) == nil then
      -- Graph goes nowhere
      table.insert(plan, {fn = action_delete, fstate = fstates[hash]})

    else
      -- We just use fname because we can move across
      local current_fname = fstates[hash].fname
      -- Try to find the current fname in the list of new_fnames. If it's
      -- there, then we can do nothing. If it's not there, then we copy the
      -- file n - 1 times and then move for the last file.
      local one_unchanged = false
      for _, dst_fstate in ipairs(dst_fstates) do
        if current_fname == dst_fstate.fname then
          one_unchanged = true
          break
        end
      end

      if one_unchanged then
        for _, dst_fstate in ipairs(dst_fstates) do
          if current_fname ~= dst_fstate.fname then
            table.insert(plan, {
              fn = action_copy,
              old_fname = current_fname,
              new_fname = dst_fstate.fname,
            })
          end
        end

      else
        local first = true
        local move_to
        for _, dst_fstate in ipairs(dst_fstates) do
          -- The first fstate gets special treatment as a move
          if first then
            move_to = dst_fstate
            first = false
          else
            table.insert(plan, {
              fn = action_copy,
              old_fname = current_fname,
              new_fname = dst_fstate.fname,
            })
          end
        end
        table.insert(plan, {
          fn = action_move,
          old_fname = current_fname,
          new_fname = move_to.fname,
        })
      end
    end
  end

  return plan
end

function M.execute_plan(plan)
  -- TODO: Make this async
  -- TODO: Check that all actions are valid before taking any action?
  -- determine_plan should only generate valid plans
  for _, action in ipairs(plan) do
    action.fn(action)
  end
end

function M.test()

  -- Taken from dirbuf.lua
  local function fst(dispname)
    -- This is the last byte as a string, which is okay because all our
    -- identifiers are single characters
    local last_char = dispname:sub(-1, -1)
    if last_char == "/" then
      return {fname = dispname:sub(0, -2), ftype = "directory"}
    elseif last_char == "@" then
      return {fname = dispname:sub(0, -2), ftype = "link"}
    else
      return {fname = dispname, ftype = "file"}
    end
  end
  describe("determine_plan", function()
    it("no changes", function()
      local fstates = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("a")}, b = {fst("b")}}
      assert.same({}, M.determine_plan(fstates, changes))
    end)

    it("rename one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("c")}, b = {fst("b")}}
      local correct_plan = {
        {fn = action_move, old_fname = "a", new_fname = "c"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("delete one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {}, b = {fst("b")}}
      local correct_plan = {{fn = action_delete, fstate = fst("a")}}
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("copy one", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("a"), fst("c")}, b = {fst("b")}}
      local correct_plan = {
        {fn = action_copy, old_fname = "a", new_fname = "c"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("dependent renames", function()
      local identities = {a = fst("a"), b = fst("b")}
      local changes = {a = {fst("b")}, b = {fst("c")}}
      local correct_plan = {
        {fn = action_move, old_fname = "b", new_fname = "c"},
        {fn = action_move, old_fname = "a", new_fname = "b"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)

    it("difficult example", function()
      local identities = {a = fst("a"), b = fst("b"), c = fst("c")}
      local changes = {a = {fst("b"), fst("d")}, b = {fst("c")}, c = {fst("a")}}
      local correct_plan = {
        {fn = action_move, old_fname = "a", new_fname = "d"},
        {fn = action_move, old_fname = "c", new_fname = "a"},
        {fn = action_move, old_fname = "b", new_fname = "c"},
        {fn = action_copy, old_fname = "d", new_fname = "c"},
      }
      assert.same(correct_plan, M.determine_plan(identities, changes))
    end)
  end)
end

return M

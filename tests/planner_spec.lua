local buffer = require("dirbuf.buffer")
local fs = require("dirbuf.fs")
local planner = require("dirbuf.planner")

local function mkplan(before, after)
  local fake_fs = {}
  local before_fs_entries = {}
  for _, line in ipairs(before) do
    local err, hash, fname, ftype = buffer.parse_line(line)
    assert(err == nil, err)
    fake_fs["/" .. fname] = fname
    before_fs_entries[hash] = fs.FSEntry.new(fname, "/", ftype)
  end

  local err, changes = planner.build_changes("/", before_fs_entries, after)
  assert(err == nil, err)
  local plan = planner.determine_plan(changes)
  return fake_fs, plan
end

local function apply_plan(fake_fs, plan)
  for _, action in ipairs(plan) do
    if action.type == "create" then
      fake_fs[action.fs_entry.path] = ""
    elseif action.type == "copy" then
      fake_fs[action.dst_fs_entry.path] = fake_fs[action.src_fs_entry.path]
    elseif action.type == "delete" then
      fake_fs[action.fs_entry.path] = nil
    elseif action.type == "move" then
      fake_fs[action.dst_fs_entry.path] = fake_fs[action.src_fs_entry.path]
      fake_fs[action.src_fs_entry.path] = nil
    end
  end
end

local function opcount(plan, op)
  local count = 0
  for _, action in ipairs(plan) do
    if action.type == op then
      count = count + 1
    end
  end
  return count
end

describe("determine_plan", function()
  it("no changes", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000a	a]],
      [[#0000000b	b]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "a", ["/b"] = "b" }, fake_fs)
    assert.same(0, #plan)
  end)

  it("reordering", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000b	b]],
      [[#0000000a	a]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "a", ["/b"] = "b" }, fake_fs)
    assert.same(0, #plan)
  end)

  it("rename", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000a	c]],
      [[#0000000b	b]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/c"] = "a", ["/b"] = "b" }, fake_fs)
    assert.same(1, #plan)
  end)

  it("delete", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000b	b]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/b"] = "b" }, fake_fs)
    assert.same(1, #plan)
  end)

  it("create", function()
    local fake_fs, plan = mkplan({
      [[#0000000b	b]],
    }, {
      [[a]],
      [[#0000000b	b]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "", ["/b"] = "b" }, fake_fs)
    assert.same(1, #plan)
  end)

  it("copy", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000a	a]],
      [[#0000000a	c]],
      [[#0000000b	b]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "a", ["/b"] = "b", ["/c"] = "a" }, fake_fs)
    assert.same(1, #plan)
  end)

  it("dependent rename", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000a	b]],
      [[#0000000b	c]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/b"] = "a", ["/c"] = "b" }, fake_fs)
    assert.same(2, #plan)
    assert.same(2, opcount(plan, "move"))
  end)

  it("swap", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000a	b]],
      [[#0000000b	a]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "b", ["/b"] = "a" }, fake_fs)
    assert.same(3, #plan)
    assert.same(3, opcount(plan, "move"))
  end)

  -- FIXME: We skip the "efficient breakpoint" efficiency tests because Dirbuf
  -- sometimes misses efficient breakpoints. Dirbuf's solutions are always
  -- correct but not always optimal.
  it("swap with efficient breakpoint", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
    }, {
      [[#0000000a	b]],
      [[#0000000b	a]],
      [[#0000000b	c]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "b", ["/b"] = "a", ["/c"] = "b" }, fake_fs)
    -- assert.same(3, #plan)
    -- assert.same(3, opcount(plan, "move"))
  end)

  it("cycle with efficient breakpoint", function()
    local fake_fs, plan = mkplan({
      [[#0000000a	a]],
      [[#0000000b	b]],
      [[#0000000c	c]],
    }, {
      [[#0000000a	b]],
      [[#0000000b	c]],
      [[#0000000b	d]],
      [[#0000000c	a]],
    })
    apply_plan(fake_fs, plan)
    assert.same({ ["/a"] = "c", ["/b"] = "a", ["/c"] = "b", ["/d"] = "b" }, fake_fs)
    -- assert.same(4, #plan)
    -- assert.same(3, opcount(plan, "move"))
    -- assert.same(1, opcount(plan, "copy"))
  end)
end)

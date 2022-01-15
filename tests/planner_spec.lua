local fs = require("dirbuf.fs")
local planner = require("dirbuf.planner")
local FState = fs.FState

local function fst(dispname)
  return FState.from_dispname(dispname, "")
end

-- Monkeypatch fs.temppath for testing
local TEMP = "$TEMP"
fs.temppath = function()
  return TEMP
end

local function apply_plan(fake_fs, plan)
  for _, action in ipairs(plan) do
    if action.type == "create" then
      fake_fs[action.fstate.path] = ""
    elseif action.type == "copy" then
      fake_fs[action.dst_fstate.path] = fake_fs[action.src_fstate.path]
    elseif action.type == "delete" then
      fake_fs[action.fstate.path] = nil
    elseif action.type == "move" then
      fake_fs[action.dst_path] = fake_fs[action.src_path]
      fake_fs[action.src_path] = nil
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
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {current_fstate = fst("a"), stays = true, progress = "unhandled"},
        b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/a"] = "a", ["/b"] = "b"}, fake_fs)
    assert.same(0, #plan)
  end)

  it("move one", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {
          fst("c"),
          current_fstate = fst("a"),
          stays = false,
          progress = "unhandled",
        },
        b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/c"] = "a", ["/b"] = "b"}, fake_fs)
    assert.same(1, #plan)
  end)

  it("delete one", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {current_fstate = fst("a"), stays = false, progress = "unhandled"},
        b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/b"] = "b"}, fake_fs)
    assert.same(1, #plan)
  end)

  it("create one", function()
    local plan = planner.determine_plan {
      new_files = {fst("a")},
      change_map = {
        b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
      },
    }

    local fake_fs = {["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/a"] = "", ["/b"] = "b"}, fake_fs)
    assert.same(1, #plan)
  end)

  it("copy one", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {
          fst("c"),
          current_fstate = fst("a"),
          stays = true,
          progress = "unhandled",
        },
        b = {current_fstate = fst("b"), stays = true, progress = "unhandled"},
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/a"] = "a", ["/b"] = "b", ["/c"] = "a"}, fake_fs)
    assert.same(1, #plan)
  end)

  it("dependent rename", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {
          fst("b"),
          current_fstate = fst("a"),
          stays = false,
          progress = "unhandled",
        },
        b = {
          fst("c"),
          current_fstate = fst("b"),
          stays = false,
          progress = "unhandled",
        },
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/b"] = "a", ["/c"] = "b"}, fake_fs)
    assert.same(2, #plan)
    assert.same(2, opcount(plan, "move"))
  end)

  it("simple cycle", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {
          fst("b"),
          current_fstate = fst("a"),
          stays = false,
          progress = "unhandled",
        },
        b = {
          fst("c"),
          current_fstate = fst("b"),
          stays = false,
          progress = "unhandled",
        },
        c = {
          fst("a"),
          current_fstate = fst("c"),
          stays = false,
          progress = "unhandled",
        },
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b", ["/c"] = "c"}
    apply_plan(fake_fs, plan)
    assert.same({["/a"] = "c", ["/b"] = "a", ["/c"] = "b"}, fake_fs)
    assert.same(4, #plan)
    assert.same(4, opcount(plan, "move"))
  end)

  -- FIXME: We skip the "efficient breakpoint" tests because Dirbuf sometimes
  -- misses efficient breakpoints. Dirbuf's solutions are always correct but
  -- not always optimal.
  pending("swap with efficient breakpoint", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {
          fst("b"),
          current_fstate = fst("a"),
          stays = false,
          progress = "unhandled",
        },
        b = {
          fst("a"),
          fst("c"),
          current_fstate = fst("b"),
          stays = false,
          progress = "unhandled",
        },
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b"}
    apply_plan(fake_fs, plan)
    assert.same({["/a"] = "b", ["/b"] = "a", ["/c"] = "b"}, fake_fs)
    assert.same(3, #plan)
    assert.same(3, opcount(plan, "move"))
  end)

  pending("cycle with efficient breakpoint", function()
    local plan = planner.determine_plan {
      new_files = {},
      change_map = {
        a = {
          fst("b"),
          current_fstate = fst("a"),
          stays = false,
          progress = "unhandled",
        },
        b = {
          fst("c"),
          fst("d"),
          current_fstate = fst("b"),
          stays = false,
          progress = "unhandled",
        },
        c = {
          fst("a"),
          current_fstate = fst("c"),
          stays = false,
          progress = "unhandled",
        },
      },
    }

    local fake_fs = {["/a"] = "a", ["/b"] = "b", ["/c"] = "c"}
    apply_plan(fake_fs, plan)
    assert.same({["/a"] = "c", ["/b"] = "a", ["/c"] = "b", ["/d"] = "b"},
                fake_fs)
    assert.same(4, #plan)
    assert.same(3, opcount(plan, "move"))
    assert.same(1, opcount(plan, "copy"))
  end)

end)

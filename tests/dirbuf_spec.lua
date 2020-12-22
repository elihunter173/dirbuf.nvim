local dirbuf = require("dirbuf")

describe("dirbuf", function()

  describe("parse_line", function()
    it("simple line", function()
      local fname, hash = dirbuf.parse_line([[README.md  #dedbeef]])
      assert.equal(fname, "README.md")
      assert.equal(hash, "dedbeef")
    end)

    it("escaped spaces", function()
      local fname, hash = dirbuf.parse_line([[\ a\ b\ c\   #0123456]])
      assert.equal(fname, " a b c ")
      assert.equal(hash, "0123456")
    end)

    it("escaped backslashes", function()
      local fname, hash = dirbuf.parse_line([[before\\after  #0123456]])
      assert.equal(fname, [[before\after]])
      assert.equal(hash, "0123456")
    end)

    it("invalid escape sequence", function()
      assert.has_error(function() dirbuf.parse_line([[\a  #0123456]]) end)
    end)
  end)

  describe("determine_plan", function()
    it("no changes", function()
      local identities = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local changes = {
        ["a"] = {"a"},
        ["b"] = {"b"},
      }
      assert.same({}, dirbuf.determine_plan(identities, changes))
    end)

    it("rename one", function()
      local identities = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local changes = {
        ["a"] = {"c"},
        ["b"] = {"b"},
      }
      local correct_plan = {
        {
          type = "move",
          old_fname = "a",
          new_fname = "c",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(identities, changes))
    end)

    it("delete one", function()
      local identities = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local changes = {
        ["a"] = {},
        ["b"] = {"b"},
      }
      local correct_plan = {
        { type = "delete", fname = "a" },
      }
      assert.same(correct_plan, dirbuf.determine_plan(identities, changes))
    end)

    it("copy one", function()
      local identities = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local changes = {
        ["a"] = {"a", "c"},
        ["b"] = {"b"},
      }
      local correct_plan = {
        {
          type = "copy",
          old_fname = "a",
          new_fname = "c",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(identities, changes))
    end)

    it("dependent renames", function()
      local identities = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local changes = {
        ["a"] = {"b"},
        ["b"] = {"c"},
      }
      local correct_plan = {
        {
          type = "move",
          old_fname = "b",
          new_fname = "c",
        },
        {
          type = "move",
          old_fname = "a",
          new_fname = "b",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(identities, changes))
    end)

    it("difficult example", function()
      local identities = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
        ["c"] = { fname = "c", ftype = "file" },
      }
      local changes = {
        ["a"] = {"b", "d"},
        ["b"] = {"c"},
        ["c"] = {"a"},
      }
      local correct_plan = {
        {
          type = "move",
          old_fname = "a",
          new_fname = "d",
        },
        {
          type = "move",
          old_fname = "c",
          new_fname = "a",
        },
        {
          type = "move",
          old_fname = "b",
          new_fname = "c",
        },
        {
          type = "copy",
          old_fname = "d",
          new_fname = "c",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(identities, changes))
    end)

  end)
end)

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
      local cur_state = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local desired_state = {
        ["a"] = {"a"},
        ["b"] = {"b"},
      }
      assert.same({}, dirbuf.determine_plan(cur_state, desired_state))
    end)

    it("rename one", function()
      local cur_state = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local desired_state = {
        ["a"] = {"c"},
        ["b"] = {"b"},
      }
      local correct_plan = {
        {
          type = dirbuf.ACTION.MOVE,
          old_fname = "a",
          new_fname = "c",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(cur_state, desired_state))
    end)

    it("delete one", function()
      local cur_state = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local desired_state = {
        ["a"] = {},
        ["b"] = {"b"},
      }
      local correct_plan = {
        { type = dirbuf.ACTION.DELETE, fname = "a" },
      }
      assert.same(correct_plan, dirbuf.determine_plan(cur_state, desired_state))
    end)

    it("copy one", function()
      local cur_state = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local desired_state = {
        ["a"] = {"a", "c"},
        ["b"] = {"b"},
      }
      local correct_plan = {
        {
          type = dirbuf.ACTION.COPY,
          old_fname = "a",
          new_fname = "c",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(cur_state, desired_state))
    end)

    it("dependent renames", function()
      local cur_state = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
      }
      local desired_state = {
        ["a"] = {"b"},
        ["b"] = {"c"},
      }
      local correct_plan = {
        {
          type = dirbuf.ACTION.MOVE,
          old_fname = "b",
          new_fname = "c",
        },
        {
          type = dirbuf.ACTION.MOVE,
          old_fname = "a",
          new_fname = "b",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(cur_state, desired_state))
    end)

    it("difficult example", function()
      local cur_state = {
        ["a"] = { fname = "a", ftype = "file" },
        ["b"] = { fname = "b", ftype = "file" },
        ["c"] = { fname = "c", ftype = "file" },
      }
      local desired_state = {
        ["a"] = {"b", "d"},
        ["b"] = {"c"},
        ["c"] = {"a"},
      }
      local correct_plan = {
        {
          type = dirbuf.ACTION.MOVE,
          old_fname = "a",
          new_fname = "d",
        },
        {
          type = dirbuf.ACTION.MOVE,
          old_fname = "c",
          new_fname = "a",
        },
        {
          type = dirbuf.ACTION.MOVE,
          old_fname = "b",
          new_fname = "c",
        },
        {
          type = dirbuf.ACTION.COPY,
          old_fname = "d",
          new_fname = "c",
        },
      }
      assert.same(correct_plan, dirbuf.determine_plan(cur_state, desired_state))
    end)

  end)
end)

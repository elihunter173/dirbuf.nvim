local config = require("dirbuf.config")

describe("update", function()
  it("legal", function()
    local errors = config.update({
      hash_first = false,
      hash_padding = 3,
      show_hidden = false,
      sort_order = "directories_first",
    })
    assert.equal(0, #errors)
    assert.equal(false, config.get("hash_first"))
    assert.equal(3, config.get("hash_padding"))
    assert.equal(false, config.get("show_hidden"))
  end)

  it("illegal", function()
    local errors = config.update({
      hash_first = 1,
      hash_padding = -1,
      show_hidden = "foo",
      sort_order = {},
      unknown = true,
    })
    assert.equal(5, #errors)
  end)

  it("set then unset", function()
    config.update({ hash_padding = 3 })
    assert.equal(3, config.get("hash_padding"))
    config.update({})
    assert.equal(2, config.get("hash_padding"))
  end)

  it("unknown option", function()
    assert.has.errors(function()
      config.get("unknown")
    end)
  end)
end)

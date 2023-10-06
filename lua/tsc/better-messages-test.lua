local bm = require("tsc.better-messages")

describe("Does the basics", function()
  it("Replaces the original text with the correct md file text", function()
    local original_message = "TS7061: A mapped type may not declare properties or methods"
    local expected_message = "TS7061: You're trying to create a mapped type with both static and dynamic properties."
    assert.equals(expected_message, bm.best_message(original_message))
  end)
end)

describe("Handles slots", function()
  it("Handles a message with one slot", function()
    local original_message = "TS2604: JSX element type 'BadComponent' does not have any construct or call signatures."
    local expected_message = "TS2604: 'BadComponent' cannot be used as a JSX component because it isn't a function."
    assert.equals(expected_message, bm.best_message(original_message))
  end)
  it("Handles a message with multiple slots", function()
    local original_message = "TS2551: Property 'foo' does not exist on type 'bar'. Did you mean 'baz'?"
    local expected_message =
      "TS2551: You're trying to access 'foo' on an object that doesn't contain it. Did you mean 'baz'?"
    assert.equals(expected_message, bm.best_message(original_message))
  end)
end)

describe("Handles links", function()
  it("Removes a 'read more' link", function()
    local original_message = "TS7006: Parameter 'foo' implicitly has an 'bar' type."
    -- check 7006.md to see original pretty message with link
    local expected_message =
      "TS7006: I don't know what type 'foo' is supposed to be, so I've defaulted it to 'bar'. Your `tsconfig.json` file says I should throw an error here."
    assert.equals(expected_message, bm.best_message(original_message))
  end)
  it("Removes a 'this article' link and sentence", function()
    local original_message =
      "TS7053: Element implicitly has an 'any' type because expression of type 'foo' can't be used to index type 'bar'."
    -- check 7053.md to see original pretty message with link
    local expected_message = "TS7053: You can't use 'foo' to index into 'bar'."
    assert.equals(expected_message, bm.best_message(original_message))
  end)
  it("Handles removes other links href, keeps link text", function()
    local original_message =
      "TS1268: An index signature parameter type must be 'string', 'number', 'symbol', or a template literal type."
    -- check 1268.md to see original pretty message with link
    local expected_message =
      "TS1268: Objects in TypeScript (and JavaScript!) can only have strings, numbers or symbols as keys. Template literal types are a way of constructing strings."
    assert.equals(expected_message, bm.best_message(original_message))
  end)
end)

local utils = require("tsc.utils")

describe("Auto-detection override fix", function()
  it("Auto-detects project when not explicitly configured", function()
    local flags = {
      noEmit = true,
      watch = false,
    }
    
    -- Mock find_nearest_tsconfig to return a test path
    local original_find_nearest_tsconfig = utils.find_nearest_tsconfig
    utils.find_nearest_tsconfig = function()
      return {"/test/path/tsconfig.json"}
    end
    
    local result = utils.parse_flags(flags)
    
    -- Restore original function
    utils.find_nearest_tsconfig = original_find_nearest_tsconfig
    
    assert.is_true(string.find(result, "--project /test/path/tsconfig.json") ~= nil)
  end)
  
  it("Does not override explicit project configuration", function()
    local flags = {
      noEmit = true,
      watch = false,
      project = "/custom/path/tsconfig.json",
    }
    
    local result = utils.parse_flags(flags)
    
    assert.is_true(string.find(result, "--project /custom/path/tsconfig.json") ~= nil)
  end)
  
  it("Handles missing tsconfig gracefully", function()
    local flags = {
      noEmit = true,
      watch = false,
    }
    
    -- Mock find_nearest_tsconfig to return empty array
    local original_find_nearest_tsconfig = utils.find_nearest_tsconfig
    utils.find_nearest_tsconfig = function()
      return {}
    end
    
    local result = utils.parse_flags(flags)
    
    -- Restore original function
    utils.find_nearest_tsconfig = original_find_nearest_tsconfig
    
    assert.is_true(string.find(result, "--project") == nil)
  end)
end)

describe("ANSI color parsing fix", function()
  it("Includes --color false flag by default when not explicitly set", function()
    local flags = {
      noEmit = true,
      watch = false,
    }
    
    local result = utils.parse_flags(flags)
    
    assert.is_true(string.find(result, "--color false") ~= nil)
  end)
  
  it("Respects explicit color configuration", function()
    local flags = {
      noEmit = true,
      watch = false,
      color = true,
    }
    
    local result = utils.parse_flags(flags)
    
    assert.is_true(string.find(result, "--color") ~= nil)
    assert.is_true(string.find(result, "--color false") == nil)
  end)
end)

describe("Working directory mismatch fix", function()
  it("find_nearest_tsconfig returns absolute path", function()
    -- Mock vim.fn.findfile to return a relative path
    local original_findfile = vim.fn.findfile
    local original_fnamemodify = vim.fn.fnamemodify
    
    vim.fn.findfile = function(name, path)
      return "./tsconfig.json"
    end
    
    vim.fn.fnamemodify = function(path, modifier)
      if modifier == ":p" then
        return "/absolute/path/tsconfig.json"
      end
      return path
    end
    
    local result = utils.find_nearest_tsconfig()
    
    -- Restore original functions
    vim.fn.findfile = original_findfile
    vim.fn.fnamemodify = original_fnamemodify
    
    assert.equals("/absolute/path/tsconfig.json", result[1])
  end)
  
  it("get_project_root returns correct directory", function()
    -- Mock vim.fn.fnamemodify
    local original_fnamemodify = vim.fn.fnamemodify
    
    vim.fn.fnamemodify = function(path, modifier)
      if modifier == ":h" then
        return "/absolute/path"
      end
      return path
    end
    
    local result = utils.get_project_root("/absolute/path/tsconfig.json")
    
    -- Restore original function
    vim.fn.fnamemodify = original_fnamemodify
    
    assert.equals("/absolute/path", result)
  end)
  
  it("get_project_root handles nil input", function()
    local result = utils.get_project_root(nil)
    assert.equals(nil, result)
  end)
end)

describe("TSC output parsing", function()
  it("Parses TSC output correctly", function()
    local output = {
      "src/test.ts(10,5): error TS2304: Cannot find name 'foo'.",
      "src/other.ts(20,10): error TS2322: Type 'string' is not assignable to type 'number'.",
    }
    
    local config = { pretty_errors = false }
    local result = utils.parse_tsc_output(output, config)
    
    assert.equals(2, #result.errors)
    assert.equals("src/test.ts", result.errors[1].filename)
    assert.equals(10, result.errors[1].lnum)
    assert.equals(5, result.errors[1].col)
    assert.equals("error TS2304: Cannot find name 'foo'.", result.errors[1].text)
    
    assert.equals("src/other.ts", result.errors[2].filename)
    assert.equals(20, result.errors[2].lnum)
    assert.equals(10, result.errors[2].col)
    assert.equals("error TS2322: Type 'string' is not assignable to type 'number'.", result.errors[2].text)
  end)
  
  it("Handles empty output gracefully", function()
    local config = { pretty_errors = false }
    local result = utils.parse_tsc_output(nil, config)
    
    assert.equals(0, #result.errors)
    assert.equals(0, #result.files)
  end)
end)
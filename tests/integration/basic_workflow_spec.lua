-- Integration tests for basic workflow
local tsc = require("tsc")
local fs = require("tsc.utils.fs")

describe("Basic Workflow Integration", function()
  local temp_dir
  local original_cwd

  before_each(function()
    original_cwd = vim.fn.getcwd()
    temp_dir = vim.fn.tempname()

    -- Create temporary project structure
    vim.fn.mkdir(temp_dir, "p")
    vim.cmd("cd " .. temp_dir)

    -- Create package.json
    local package_content = vim.fn.json_encode({
      name = "test-project",
      version = "1.0.0",
      devDependencies = {
        typescript = "^4.0.0",
      },
    })
    fs.write_file(temp_dir .. "/package.json", package_content)

    -- Create tsconfig.json
    local tsconfig_content = vim.fn.json_encode({
      compilerOptions = {
        target = "ES2020",
        module = "commonjs",
        strict = true,
        noEmit = true,
      },
      include = { "src/**/*" },
    })
    fs.write_file(temp_dir .. "/tsconfig.json", tsconfig_content)

    -- Create src directory
    vim.fn.mkdir(temp_dir .. "/src", "p")
  end)

  after_each(function()
    vim.cmd("cd " .. original_cwd)
    if temp_dir and fs.dir_exists(temp_dir) then
      vim.fn.delete(temp_dir, "rf")
    end

    -- Clean up tsc instance
    if tsc.cleanup then
      tsc.cleanup()
    end
  end)

  describe("project detection", function()
    it("should detect single project", function()
      -- Initialize tsc.nvim
      local instance = tsc.setup({
        mode = "project",
        plugins = {
          quickfix = { enabled = false },
          watch = { enabled = false },
          diagnostics = { enabled = false },
        },
      })

      -- Mock TypeScript binary
      local original_is_executable = fs.is_executable
      fs.is_executable = function(path)
        return path:match("tsc$") ~= nil
      end

      -- Mock process execution
      local executed_commands = {}
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        table.insert(executed_commands, cmd)

        -- Simulate successful execution
        if opts.on_exit then
          vim.schedule(function()
            opts.on_exit(nil, 0)
          end)
        end

        return 123 -- Mock job ID
      end

      -- Run type-checking
      local run_id = instance:run()

      -- Wait for completion
      vim.wait(100)

      assert.is_string(run_id)
      assert.is_true(#run_id > 0)
      assert.equal(1, #executed_commands)
      assert.is_true(executed_commands[1]:match("--project"))
      assert.is_true(executed_commands[1]:match("tsconfig.json"))

      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
  end)

  describe("error handling", function()
    it("should handle TypeScript compilation errors", function()
      -- Create TypeScript file with errors
      local error_content = [[
const x: string = 42; // Type error
function test() {
  return unknownVariable; // Reference error
}
]]
      fs.write_file(temp_dir .. "/src/errors.ts", error_content)

      local errors_received = {}

      -- Initialize tsc.nvim
      local instance = tsc.setup({
        mode = "project",
        plugins = {
          quickfix = { enabled = false },
          watch = { enabled = false },
          diagnostics = { enabled = false },
        },
      })

      -- Listen for completion events
      local events = instance:get_events()
      events:on("tsc.completed", function(data)
        errors_received = data.errors or {}
      end)

      -- Mock TypeScript binary and execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function(path)
        return path:match("tsc$") ~= nil
      end

      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        -- Simulate TypeScript output with errors
        local mock_output = {
          "src/errors.ts(1,19): error TS2322: Type 'number' is not assignable to type 'string'.",
          "src/errors.ts(3,10): error TS2304: Cannot find name 'unknownVariable'.",
        }

        if opts.on_stdout then
          vim.schedule(function()
            opts.on_stdout(nil, mock_output)
          end)
        end

        if opts.on_exit then
          vim.schedule(function()
            opts.on_exit(nil, 1) -- Exit with error
          end)
        end

        return 123
      end

      -- Run type-checking
      instance:run()

      -- Wait for completion
      vim.wait(200)

      assert.equal(2, #errors_received)
      assert.equal("src/errors.ts", errors_received[1].filename)
      assert.equal(1, errors_received[1].lnum)
      assert.is_true(errors_received[1].text:match("TS2322"))

      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
  end)

  describe("plugin integration", function()
    it("should integrate with quickfix plugin", function()
      local quickfix_items = {}

      -- Mock quickfix functions
      vim.fn.setqflist = function(items, action, what)
        if action == "r" then
          quickfix_items = what.items or {}
        end
      end

      -- Initialize tsc.nvim with quickfix enabled
      local instance = tsc.setup({
        mode = "project",
        plugins = {
          quickfix = {
            enabled = true,
            auto_open = false, -- Disable auto-open for test
          },
          watch = { enabled = false },
          diagnostics = { enabled = false },
        },
      })

      -- Mock TypeScript execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function()
        return true
      end

      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        local mock_output = {
          "src/test.ts(5,10): error TS2322: Type error example.",
        }

        if opts.on_stdout then
          vim.schedule(function()
            opts.on_stdout(nil, mock_output)
          end)
        end

        if opts.on_exit then
          vim.schedule(function()
            opts.on_exit(nil, 1)
          end)
        end

        return 123
      end

      -- Create test file
      fs.write_file(temp_dir .. "/src/test.ts", "const x: string = 42;")

      -- Run type-checking
      instance:run()

      -- Wait for completion and plugin processing
      vim.wait(200)

      assert.equal(1, #quickfix_items)
      assert.equal("src/test.ts", quickfix_items[1].filename)
      assert.equal(5, quickfix_items[1].lnum)

      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)

    it("should integrate with diagnostics plugin", function()
      local diagnostic_calls = {}

      -- Mock diagnostic functions
      local original_create_namespace = vim.api.nvim_create_namespace
      local original_diagnostic_set = vim.diagnostic.set
      local original_diagnostic_reset = vim.diagnostic.reset

      vim.api.nvim_create_namespace = function(name)
        return 42 -- Mock namespace ID
      end

      vim.diagnostic.set = function(namespace, bufnr, diagnostics, opts)
        table.insert(diagnostic_calls, {
          namespace = namespace,
          bufnr = bufnr,
          diagnostics = diagnostics,
        })
      end

      vim.diagnostic.reset = function() end

      -- Mock buffer functions
      vim.fn.bufnr = function(filename)
        return 1 -- Mock buffer number
      end

      vim.fn.bufadd = function()
        return 1
      end

      vim.fn.filereadable = function()
        return 1
      end

      -- Initialize tsc.nvim with diagnostics enabled
      local instance = tsc.setup({
        mode = "project",
        plugins = {
          quickfix = { enabled = false },
          watch = { enabled = false },
          diagnostics = { enabled = true },
        },
      })

      -- Mock TypeScript execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function()
        return true
      end

      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        local mock_output = {
          'src/test.ts(10,5): error TS2322: Type "number" is not assignable to type "string".',
        }

        if opts.on_stdout then
          vim.schedule(function()
            opts.on_stdout(nil, mock_output)
          end)
        end

        if opts.on_exit then
          vim.schedule(function()
            opts.on_exit(nil, 1)
          end)
        end

        return 123
      end

      -- Run type-checking
      instance:run()

      -- Wait for completion
      vim.wait(200)

      assert.is_true(#diagnostic_calls > 0)
      local call = diagnostic_calls[1]
      assert.equal(42, call.namespace)
      assert.equal(1, #call.diagnostics)
      assert.equal(9, call.diagnostics[1].lnum) -- 0-based
      assert.equal(4, call.diagnostics[1].col) -- 0-based

      -- Restore mocks
      vim.api.nvim_create_namespace = original_create_namespace
      vim.diagnostic.set = original_diagnostic_set
      vim.diagnostic.reset = original_diagnostic_reset
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
  end)

  describe("configuration", function()
    it("should respect configuration options", function()
      local executed_commands = {}

      -- Initialize with custom configuration
      local instance = tsc.setup({
        mode = "project",
        typescript = {
          flags = "--strict --noUnusedLocals",
          timeout = 15000,
        },
        plugins = {
          quickfix = { enabled = false },
        },
      })

      -- Mock execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function()
        return true
      end

      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        table.insert(executed_commands, cmd)

        if opts.on_exit then
          vim.schedule(function()
            opts.on_exit(nil, 0)
          end)
        end

        return 123
      end

      -- Run type-checking
      instance:run()

      -- Wait for completion
      vim.wait(100)

      assert.equal(1, #executed_commands)
      local cmd = executed_commands[1]
      assert.is_true(cmd:match("--strict"))
      assert.is_true(cmd:match("--noUnusedLocals"))
      assert.is_true(cmd:match("--color false"))

      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
  end)
end)


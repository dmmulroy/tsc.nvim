---@class LegacyCommands
local M = {}

---Setup legacy command aliases for backward compatibility
---@param instance table TSC instance
function M.setup_legacy_commands(instance)
  -- Legacy TSCOpen command (already exists in main init.lua)
  -- Legacy TSCClose command (already exists in main init.lua)
  -- Legacy TSCStop command (already exists in main init.lua)

  -- Additional legacy commands that might have existed
  vim.api.nvim_create_user_command("TSCRestart", function()
    vim.notify("TSCRestart is deprecated. Use :TSCStop followed by :TSC instead.", vim.log.levels.WARN)
    instance:stop()
    vim.defer_fn(function()
      instance:run()
    end, 100)
  end, {
    desc = "[DEPRECATED] Restart TypeScript type-checking",
  })

  vim.api.nvim_create_user_command("TSCWatch", function()
    vim.notify("TSCWatch is deprecated. Use :TSC watch or configure watch mode in setup().", vim.log.levels.WARN)
    instance:run({ watch = true })
  end, {
    desc = "[DEPRECATED] Start TypeScript type-checking in watch mode",
  })

  vim.api.nvim_create_user_command("TSCClear", function()
    vim.notify("TSCClear is deprecated. Use :TSCClose or configure auto_close in quickfix plugin.", vim.log.levels.WARN)
    local quickfix_plugin = instance:get_plugin("quickfix")
    if quickfix_plugin then
      quickfix_plugin:clear()
    end
  end, {
    desc = "[DEPRECATED] Clear TypeScript errors from quickfix list",
  })
end

---Show deprecation warnings for old configuration patterns
---@param old_config table Old configuration
function M.show_deprecation_warnings(old_config)
  local warnings = {}

  -- Check for deprecated configuration options
  local deprecated_options = {
    use_trouble_qflist = "Configure trouble.nvim externally instead",
    enable_progress_notifications = "Use notification plugins instead",
    enable_error_notifications = "Use notification plugins instead",
    hide_progress_notifications_from_history = "Configure notifications externally",
    spinner = "Configure notifications externally",
    bin_path = "Use typescript.bin instead",
    pretty_errors = "Use plugins.better_messages.enabled instead",
  }

  for option, message in pairs(deprecated_options) do
    if old_config[option] ~= nil then
      table.insert(warnings, string.format("%s: %s", option, message))
    end
  end

  -- Check for deprecated flag formats
  if old_config.flags and type(old_config.flags) == "table" then
    if old_config.flags.watch then
      table.insert(warnings, "flags.watch: Use plugins.watch.enabled instead")
    end
    if old_config.flags.project then
      table.insert(warnings, "flags.project: Projects are now auto-detected")
    end
  end

  if #warnings > 0 then
    local message = "tsc.nvim: Deprecated configuration options detected:\n"
      .. table.concat(warnings, "\n")
      .. "\nSee :help tsc-migration for migration guide."

    vim.notify(message, vim.log.levels.WARN)
  end
end

---Create compatibility shim for old API methods
---@param instance table TSC instance
---@return table Compatibility shim
function M.create_compatibility_shim(instance)
  local shim = {}

  -- Legacy method names
  function shim.setup(opts)
    return instance.setup(opts)
  end

  function shim.run()
    return instance:run()
  end

  function shim.stop()
    return instance:stop()
  end

  function shim.is_running()
    vim.notify("is_running() is deprecated. Use status() instead.", vim.log.levels.WARN)
    local status = instance:status()
    return status.runner and status.runner.running_processes > 0
  end

  -- Legacy configuration access
  function shim.get_config()
    vim.notify("get_config() is deprecated. Use status().config instead.", vim.log.levels.WARN)
    return instance:status().config
  end

  return shim
end

---Setup legacy autocommands for backward compatibility
---@param instance table TSC instance
function M.setup_legacy_autocommands(instance)
  -- Some users might have relied on specific autocommand patterns
  -- We'll create them but show deprecation warnings

  local group = vim.api.nvim_create_augroup("tsc_nvim_legacy", { clear = true })

  -- Legacy auto-run on save (if they had custom setups)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.ts,*.tsx",
    desc = "[LEGACY] Auto-run TSC on save",
    callback = function()
      -- Only trigger if user hasn't configured watch mode properly
      local watch_plugin = instance:get_plugin("watch")
      if watch_plugin and not watch_plugin._config.enabled then
        vim.notify_once(
          "Auto-run on save detected. Consider enabling watch mode in plugin configuration.",
          vim.log.levels.INFO
        )
      end
    end,
  })
end

---Provide migration helpers
M.migration = {
  ---Convert 2.x style flags to 3.x format
  ---@param old_flags table|string Old flags
  ---@return string New flags format
  convert_flags = function(old_flags)
    if type(old_flags) == "string" then
      return old_flags
    end

    if type(old_flags) == "table" then
      local parts = {}
      for key, value in pairs(old_flags) do
        if key ~= "watch" and key ~= "project" then
          if type(value) == "boolean" and value then
            table.insert(parts, "--" .. key)
          elseif type(value) == "string" then
            table.insert(parts, "--" .. key .. " " .. value)
          end
        end
      end
      return table.concat(parts, " ")
    end

    return "--noEmit"
  end,

  ---Convert 2.x configuration to 3.x
  ---@param old_config table 2.x configuration
  ---@return table 3.x configuration
  convert_config = function(old_config)
    local new_config = {
      mode = old_config.run_as_monorepo and "monorepo" or "project",

      discovery = {
        max_projects = old_config.max_tsconfig_files or 20,
      },

      typescript = {
        bin = old_config.bin_path,
        flags = M.migration.convert_flags(old_config.flags),
        timeout = 30000,
      },

      output = {
        auto_open = old_config.auto_open_qflist,
        auto_close = old_config.auto_close_qflist,
      },

      plugins = {
        quickfix = {
          enabled = true,
          auto_focus = old_config.auto_focus_qflist,
        },
        watch = {
          enabled = old_config.flags and old_config.flags.watch or false,
          auto_start = old_config.auto_start_watch_mode,
        },
        diagnostics = {
          enabled = old_config.use_diagnostics or false,
        },
        better_messages = {
          enabled = old_config.pretty_errors ~= false,
        },
      },
    }

    return new_config
  end,

  ---Show migration guide
  show_guide = function()
    local guide = {
      "tsc.nvim 2.x → 3.x Migration Guide",
      "=====================================",
      "",
      "Configuration Changes:",
      "• auto_open_qflist → output.auto_open",
      "• auto_close_qflist → output.auto_close",
      '• run_as_monorepo → mode = "monorepo"',
      "• use_diagnostics → plugins.diagnostics.enabled",
      "• bin_path → typescript.bin",
      "• flags (table) → typescript.flags (string)",
      "",
      "Removed Options:",
      "• use_trouble_qflist (configure trouble.nvim externally)",
      "• enable_progress_notifications (use notification plugins)",
      "• spinner (use notification plugins)",
      "",
      "New Features:",
      "• Plugin system for extensibility",
      "• Better error message translations",
      "• Enhanced watch mode with debouncing",
      "• Async file operations",
      "",
      "For detailed migration instructions:",
      ":help tsc-migration",
    }

    vim.notify(table.concat(guide, "\n"), vim.log.levels.INFO)
  end,
}

return M

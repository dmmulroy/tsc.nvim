---@class ConfigMigration
local M = {}

---Check if configuration is from 2.x
---@param config table Configuration to check
---@return boolean
function M.is_v2_config(config)
  -- Check for 2.x specific properties
  local v2_properties = {
    "auto_open_qflist",
    "auto_close_qflist",
    "auto_focus_qflist",
    "auto_start_watch_mode",
    "use_trouble_qflist",
    "use_diagnostics",
    "run_as_monorepo",
    "max_tsconfig_files",
    "bin_path",
    "enable_progress_notifications",
    "enable_error_notifications",
    "hide_progress_notifications_from_history",
    "spinner",
    "pretty_errors",
  }

  for _, prop in ipairs(v2_properties) do
    if config[prop] ~= nil then
      return true
    end
  end

  -- Check for 2.x flags format
  if config.flags and type(config.flags) == "table" then
    -- 2.x used table format for flags
    return true
  end

  return false
end

---Convert 2.x configuration to 3.x format
---@param old_config table 2.x configuration
---@return table 3.x configuration
function M.migrate_v2_config(old_config)
  local new_config = {}

  -- Migrate mode
  new_config.mode = old_config.run_as_monorepo and "monorepo" or "project"

  -- Migrate discovery section
  new_config.discovery = {
    max_projects = old_config.max_tsconfig_files or 20,
  }

  -- Migrate typescript section
  new_config.typescript = {
    bin = old_config.bin_path,
    timeout = 30000,
  }

  -- Handle flags migration
  if type(old_config.flags) == "string" then
    new_config.typescript.flags = old_config.flags
  elseif type(old_config.flags) == "table" then
    local flag_parts = {}
    for key, value in pairs(old_config.flags) do
      -- Skip special flags that are handled elsewhere
      if key ~= "watch" and key ~= "project" then
        if type(value) == "boolean" and value then
          table.insert(flag_parts, "--" .. key)
        elseif type(value) == "string" then
          table.insert(flag_parts, "--" .. key .. " " .. value)
        end
      end
    end
    new_config.typescript.flags = table.concat(flag_parts, " ")
  else
    new_config.typescript.flags = "--noEmit"
  end

  -- Migrate output section
  new_config.output = {
    format = "quickfix",
    auto_open = old_config.auto_open_qflist,
    auto_close = old_config.auto_close_qflist,
  }

  -- Migrate plugins section
  new_config.plugins = {
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
  }

  return new_config
end

---Show migration warnings for deprecated features
---@param old_config table 2.x configuration
function M.show_migration_warnings(old_config)
  local warnings = {}
  local infos = {}

  -- Breaking changes that need user attention
  if old_config.use_trouble_qflist then
    table.insert(warnings, "use_trouble_qflist: Configure trouble.nvim externally instead")
  end

  if old_config.enable_progress_notifications == false then
    table.insert(infos, "Progress notifications now handled by external plugins")
  end

  if old_config.enable_error_notifications == false then
    table.insert(infos, "Error notifications now handled by external plugins")
  end

  if old_config.hide_progress_notifications_from_history then
    table.insert(infos, "Notification history now configured externally")
  end

  if old_config.spinner then
    table.insert(infos, "Custom spinners now configured in notification plugins")
  end

  -- Configuration migrations
  if old_config.flags and type(old_config.flags) == "table" then
    table.insert(infos, "Table-style flags converted to string format")
  end

  if old_config.max_tsconfig_files then
    table.insert(infos, "max_tsconfig_files → discovery.max_projects")
  end

  -- Show warnings for breaking changes
  if #warnings > 0 then
    vim.notify(
      "tsc.nvim 3.0 Migration Required:\n" .. table.concat(warnings, "\n") .. "\nSee :help tsc-migration for details.",
      vim.log.levels.WARN
    )
  end

  -- Show info for automatic migrations
  if #infos > 0 then
    vim.notify("tsc.nvim 3.0 Configuration Migrated:\n" .. table.concat(infos, "\n"), vim.log.levels.INFO)
  end
end

---Migrate configuration if needed
---@param config table Configuration to potentially migrate
---@return table Migrated configuration
function M.migrate_if_needed(config)
  if M.is_v2_config(config) then
    vim.notify("Detected tsc.nvim 2.x configuration. Migrating to 3.x format...", vim.log.levels.INFO)

    local migrated = M.migrate_v2_config(config)
    M.show_migration_warnings(config)

    return migrated
  end

  return config
end

---Get migration guide information
---@return table
function M.get_migration_guide()
  return {
    title = "tsc.nvim 2.x to 3.x Migration Guide",
    changes = {
      {
        category = "Configuration Structure",
        description = "Configuration is now organized into sections: mode, discovery, typescript, output, plugins",
        before = "{ auto_open_qflist = true, run_as_monorepo = false }",
        after = '{ mode = "project", output = { auto_open = true } }',
      },
      {
        category = "Plugin Integration",
        description = "Direct plugin integrations removed in favor of plugin system",
        before = "{ use_trouble_qflist = true }",
        after = "Configure trouble.nvim externally",
      },
      {
        category = "Flags Format",
        description = "Flags are now strings instead of tables",
        before = "{ flags = { noEmit = true, strict = true } }",
        after = '{ typescript = { flags = "--noEmit --strict" } }',
      },
    },
    resources = {
      "docs/migration/from-2x.md",
      "docs/configuration.md",
      "examples/configurations/",
    },
  }
end

return M

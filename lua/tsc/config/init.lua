local defaults = require("tsc.config.defaults")
local schema = require("tsc.config.schema")
local migration = require("tsc.config.migration")

---@class ConfigManager
---@field private _config table Current configuration
---@field private _defaults table Default configuration
local ConfigManager = {}

---Create new configuration manager
---@param user_config? table User configuration
---@return ConfigManager
function ConfigManager.new(user_config)
  local self = {
    _config = {},
    _defaults = defaults.get_defaults(),
  }

  -- Set up configuration
  self:_setup_config(user_config or {})

  return setmetatable(self, { __index = ConfigManager })
end

---Setup configuration with validation and migration
---@param user_config table User configuration
function ConfigManager:_setup_config(user_config)
  -- Check if this is a 2.x configuration and migrate if needed
  local migrated_config = migration.migrate_if_needed(user_config)

  -- Validate configuration
  local valid, error_msg = schema.validate(migrated_config)
  if not valid then
    vim.notify(string.format("Invalid tsc.nvim configuration: %s", error_msg), vim.log.levels.ERROR)
    -- Fall back to defaults
    self._config = self._defaults
    return
  end

  -- Merge user config with defaults
  self._config = vim.tbl_deep_extend("force", self._defaults, migrated_config)
end

---Get the current configuration
---@return table
function ConfigManager:get()
  return vim.deepcopy(self._config)
end

---Get a specific configuration section
---@param section string Section name
---@return table|nil
function ConfigManager:get_section(section)
  if self._config[section] then
    return vim.deepcopy(self._config[section])
  end
  return nil
end

---Update configuration at runtime
---@param updates table Configuration updates
---@return boolean success
function ConfigManager:update(updates)
  -- Validate updates
  local valid, error_msg = schema.validate(updates)
  if not valid then
    vim.notify(string.format("Invalid configuration update: %s", error_msg), vim.log.levels.ERROR)
    return false
  end

  -- Apply updates
  self._config = vim.tbl_deep_extend("force", self._config, updates)
  return true
end

---Get configuration for a specific plugin
---@param plugin_name string Plugin name
---@return table|nil
function ConfigManager:get_plugin_config(plugin_name)
  if self._config.plugins and self._config.plugins[plugin_name] then
    return vim.deepcopy(self._config.plugins[plugin_name])
  end
  return nil
end

---Check if a plugin is enabled
---@param plugin_name string Plugin name
---@return boolean
function ConfigManager:is_plugin_enabled(plugin_name)
  local plugin_config = self:get_plugin_config(plugin_name)
  if plugin_config then
    return plugin_config.enabled ~= false
  end
  return false
end

---Get TypeScript binary path
---@return string
function ConfigManager:get_tsc_binary()
  local bin = self._config.typescript.bin
  if bin then
    return bin
  end

  -- Auto-detect TypeScript binary
  local node_modules_tsc = vim.fn.findfile("node_modules/.bin/tsc", ".;")
  if node_modules_tsc ~= "" then
    return node_modules_tsc
  end

  return "tsc"
end

---Get TypeScript flags
---@return string
function ConfigManager:get_tsc_flags()
  return self._config.typescript.flags or "--noEmit"
end

---Get process timeout
---@return number
function ConfigManager:get_timeout()
  return self._config.typescript.timeout or 30000
end

---Get working directory
---@return string|nil
function ConfigManager:get_working_dir()
  return self._config.typescript.working_dir
end

---Get discovery configuration
---@return table
function ConfigManager:get_discovery_config()
  return vim.deepcopy(self._config.discovery)
end

---Get output configuration
---@return table
function ConfigManager:get_output_config()
  return vim.deepcopy(self._config.output)
end

---Get execution mode
---@return string
function ConfigManager:get_mode()
  return self._config.mode or "project"
end

---Reset configuration to defaults
function ConfigManager:reset()
  self._config = defaults.get_defaults()
end

---Get configuration summary for debugging
---@return table
function ConfigManager:get_summary()
  return {
    mode = self._config.mode,
    typescript_bin = self:get_tsc_binary(),
    typescript_flags = self:get_tsc_flags(),
    timeout = self:get_timeout(),
    output_format = self._config.output.format,
    enabled_plugins = vim.tbl_filter(function(plugin_name)
      return self:is_plugin_enabled(plugin_name)
    end, vim.tbl_keys(self._config.plugins)),
  }
end

return ConfigManager

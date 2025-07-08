---@class PluginManager
---@field private _plugins table<string, Plugin>
---@field private _events Events
---@field private _config ConfigManager
---@field private _plugin_factories table<string, function>
local PluginManager = {}

---@class Plugin
---@field name string Plugin name
---@field version string Plugin version
---@field dependencies string[] Plugin dependencies
---@field enabled boolean Whether plugin is enabled
local Plugin = {}

---Create new plugin manager
---@param events Events Event system
---@param config ConfigManager Configuration manager
---@return PluginManager
function PluginManager.new(events, config)
  local self = {
    _plugins = {},
    _events = events,
    _config = config,
    _plugin_factories = {},
  }
  
  -- Register core plugins
  self:_register_core_plugins()
  
  return setmetatable(self, { __index = PluginManager })
end

---Register core plugins
function PluginManager:_register_core_plugins()
  -- Register core plugin factories
  self._plugin_factories.quickfix = function(events, config)
    return require('tsc.plugins.quickfix').new(events, config)
  end
  
  self._plugin_factories.watch = function(events, config)
    return require('tsc.plugins.watch').new(events, config)
  end
  
  self._plugin_factories.diagnostics = function(events, config)
    return require('tsc.plugins.diagnostics').new(events, config)
  end
  
  self._plugin_factories.better_messages = function(events, config)
    return require('tsc.plugins.better_messages').new(events, config)
  end
end

---Register a plugin factory
---@param name string Plugin name
---@param factory function Plugin factory function
---@return boolean success
function PluginManager:register(name, factory)
  if type(name) ~= 'string' or name == '' then
    vim.notify('Plugin name must be a non-empty string', vim.log.levels.ERROR)
    return false
  end
  
  if type(factory) ~= 'function' then
    vim.notify('Plugin factory must be a function', vim.log.levels.ERROR)
    return false
  end
  
  self._plugin_factories[name] = factory
  return true
end

---Load all enabled plugins
---@return boolean success
function PluginManager:load_all()
  local loaded_count = 0
  local failed_count = 0
  
  -- Load plugins in dependency order
  local load_order = self:_get_load_order()
  
  for _, plugin_name in ipairs(load_order) do
    if self:_should_load_plugin(plugin_name) then
      local success = self:_load_plugin(plugin_name)
      if success then
        loaded_count = loaded_count + 1
      else
        failed_count = failed_count + 1
      end
    end
  end
  
  -- Emit event
  self._events:emit('tsc.plugins_loaded', {
    loaded = loaded_count,
    failed = failed_count,
    total = loaded_count + failed_count,
  })
  
  return failed_count == 0
end

---Check if plugin should be loaded
---@param plugin_name string Plugin name
---@return boolean
function PluginManager:_should_load_plugin(plugin_name)
  -- Check if plugin is enabled in config
  local plugin_config = self._config:get_plugin_config(plugin_name)
  if plugin_config and plugin_config.enabled == false then
    return false
  end
  
  -- Check if plugin factory exists
  if not self._plugin_factories[plugin_name] then
    return false
  end
  
  -- Check if already loaded
  if self._plugins[plugin_name] then
    return false
  end
  
  return true
end

---Load a single plugin
---@param plugin_name string Plugin name
---@return boolean success
function PluginManager:_load_plugin(plugin_name)
  local factory = self._plugin_factories[plugin_name]
  if not factory then
    vim.notify(
      string.format('Plugin factory not found: %s', plugin_name),
      vim.log.levels.ERROR
    )
    return false
  end
  
  local plugin_config = self._config:get_plugin_config(plugin_name) or {}
  
  -- Create plugin instance
  local success, plugin = pcall(factory, self._events, plugin_config)
  if not success then
    vim.notify(
      string.format('Failed to create plugin %s: %s', plugin_name, plugin),
      vim.log.levels.ERROR
    )
    
    -- Emit plugin error event
    self._events:emit('tsc.plugin_error', {
      plugin = plugin_name,
      error = plugin,
      phase = 'creation',
    })
    
    return false
  end
  
  -- Validate plugin
  if not self:_validate_plugin(plugin) then
    vim.notify(
      string.format('Plugin validation failed: %s', plugin_name),
      vim.log.levels.ERROR
    )
    return false
  end
  
  -- Setup plugin
  success, err = pcall(function()
    plugin:setup()
  end)
  
  if not success then
    vim.notify(
      string.format('Plugin setup failed for %s: %s', plugin_name, err),
      vim.log.levels.ERROR
    )
    
    -- Emit plugin error event
    self._events:emit('tsc.plugin_error', {
      plugin = plugin_name,
      error = err,
      phase = 'setup',
    })
    
    return false
  end
  
  -- Store plugin
  self._plugins[plugin_name] = plugin
  
  -- Emit plugin loaded event
  self._events:emit('tsc.plugin_loaded', {
    plugin = plugin_name,
    version = plugin.version,
  })
  
  return true
end

---Validate plugin instance
---@param plugin Plugin Plugin instance
---@return boolean
function PluginManager:_validate_plugin(plugin)
  if type(plugin) ~= 'table' then
    return false
  end
  
  -- Check required fields
  if not plugin.name or type(plugin.name) ~= 'string' then
    return false
  end
  
  if not plugin.version or type(plugin.version) ~= 'string' then
    return false
  end
  
  -- Check required methods
  if not plugin.setup or type(plugin.setup) ~= 'function' then
    return false
  end
  
  return true
end

---Get plugin load order (considering dependencies)
---@return string[] Plugin names in load order
function PluginManager:_get_load_order()
  local all_plugins = vim.tbl_keys(self._plugin_factories)
  local ordered = {}
  local visited = {}
  local visiting = {}
  
  local function visit(plugin_name)
    if visited[plugin_name] then
      return
    end
    
    if visiting[plugin_name] then
      vim.notify(
        string.format('Circular dependency detected with plugin: %s', plugin_name),
        vim.log.levels.ERROR
      )
      return
    end
    
    visiting[plugin_name] = true
    
    -- Visit dependencies first (if we had dependency info)
    -- For now, we'll use a simple order
    
    visiting[plugin_name] = nil
    visited[plugin_name] = true
    table.insert(ordered, plugin_name)
  end
  
  -- Visit all plugins
  for _, plugin_name in ipairs(all_plugins) do
    visit(plugin_name)
  end
  
  return ordered
end

---Get plugin instance
---@param name string Plugin name
---@return Plugin|nil
function PluginManager:get(name)
  return self._plugins[name]
end

---Get all loaded plugins
---@return table<string, Plugin>
function PluginManager:get_all()
  return vim.deepcopy(self._plugins)
end

---Check if plugin is loaded
---@param name string Plugin name
---@return boolean
function PluginManager:is_loaded(name)
  return self._plugins[name] ~= nil
end

---Unload a plugin
---@param name string Plugin name
---@return boolean success
function PluginManager:unload(name)
  local plugin = self._plugins[name]
  if not plugin then
    return false
  end
  
  -- Call cleanup if available
  if plugin.cleanup and type(plugin.cleanup) == 'function' then
    local success, err = pcall(function()
      plugin:cleanup()
    end)
    
    if not success then
      vim.notify(
        string.format('Plugin cleanup failed for %s: %s', name, err),
        vim.log.levels.ERROR
      )
    end
  end
  
  -- Remove from loaded plugins
  self._plugins[name] = nil
  
  return true
end

---Unload all plugins
---@return number Number of plugins unloaded
function PluginManager:unload_all()
  local count = 0
  
  for name, _ in pairs(self._plugins) do
    if self:unload(name) then
      count = count + 1
    end
  end
  
  return count
end

---Reload a plugin
---@param name string Plugin name
---@return boolean success
function PluginManager:reload(name)
  if self:unload(name) then
    return self:_load_plugin(name)
  end
  return false
end

---Get plugin manager statistics
---@return table Statistics
function PluginManager:get_stats()
  local loaded = vim.tbl_count(self._plugins)
  local available = vim.tbl_count(self._plugin_factories)
  local enabled = 0
  
  for name, _ in pairs(self._plugin_factories) do
    if self:_should_load_plugin(name) then
      enabled = enabled + 1
    end
  end
  
  return {
    loaded = loaded,
    available = available,
    enabled = enabled,
    disabled = available - enabled,
    loaded_plugins = vim.tbl_keys(self._plugins),
    available_plugins = vim.tbl_keys(self._plugin_factories),
  }
end

---Get plugin status
---@param name? string Plugin name (optional)
---@return table Plugin status
function PluginManager:get_status(name)
  if name then
    local plugin = self._plugins[name]
    if plugin then
      local status = {
        name = plugin.name,
        version = plugin.version,
        loaded = true,
        enabled = true,
      }
      
      if plugin.get_status and type(plugin.get_status) == 'function' then
        local plugin_status = plugin:get_status()
        status = vim.tbl_extend('force', status, plugin_status)
      end
      
      return status
    else
      return {
        name = name,
        loaded = false,
        enabled = self:_should_load_plugin(name),
      }
    end
  else
    -- Return status for all plugins
    local status = {}
    for plugin_name, _ in pairs(self._plugin_factories) do
      status[plugin_name] = self:get_status(plugin_name)
    end
    return status
  end
end

return PluginManager
local Events = require('tsc.core.events')
local ConfigManager = require('tsc.config')
local PluginManager = require('tsc.plugins')
local ProjectDiscovery = require('tsc.core.discovery')
local Runner = require('tsc.core.runner')
local LegacyCommands = require('tsc.compat.commands')

---@class TSC
---@field private _config ConfigManager
---@field private _events Events
---@field private _plugins PluginManager
---@field private _discovery ProjectDiscovery
---@field private _runner Runner
---@field private _initialized boolean
local TSC = {}

---Initialize tsc.nvim
---@param opts? table Configuration options
---@return TSC
function TSC.setup(opts)
  local self = {
    _initialized = false,
  }
  
  -- Initialize event system
  self._events = Events.new()
  
  -- Initialize configuration manager
  self._config = ConfigManager.new(opts)
  
  -- Initialize plugin manager
  self._plugins = PluginManager.new(self._events, self._config)
  
  -- Initialize project discovery
  local discovery_config = self._config:get_discovery_config()
  self._discovery = ProjectDiscovery.new(discovery_config)
  
  -- Initialize runner
  self._runner = Runner.new(self._config, self._events)
  
  -- Load plugins
  self._plugins:load_all()
  
  -- Set up user commands
  self:_setup_commands()
  
  -- Set up legacy commands for backward compatibility
  LegacyCommands.setup_legacy_commands(self)
  
  -- Set up autocommands if needed
  self:_setup_autocommands()
  
  -- Set up legacy autocommands
  LegacyCommands.setup_legacy_autocommands(self)
  
  -- Mark as initialized
  self._initialized = true
  
  -- Emit initialized event
  self._events:emit(Events.EVENTS.INITIALIZED, {
    config = self._config:get_summary(),
    plugins = self._plugins:get_stats(),
  })
  
  return setmetatable(self, { __index = TSC })
end

---Set up user commands
function TSC:_setup_commands()
  -- Main TSC command
  vim.api.nvim_create_user_command('TSC', function(cmd)
    local opts = {}
    
    -- Parse command arguments
    if cmd.args and cmd.args ~= '' then
      -- Simple argument parsing for now
      if cmd.args:match('watch') then
        opts.watch = true
      end
    end
    
    self:run(opts)
  end, {
    desc = 'Run TypeScript type-checking',
    nargs = '?',
    complete = function()
      return {'watch'}
    end,
  })
  
  -- Stop command
  vim.api.nvim_create_user_command('TSCStop', function()
    self:stop()
  end, {
    desc = 'Stop all TypeScript type-checking processes',
  })
  
  -- Status command
  vim.api.nvim_create_user_command('TSCStatus', function()
    self:show_status()
  end, {
    desc = 'Show TypeScript type-checking status',
  })
  
  -- Open quickfix command
  vim.api.nvim_create_user_command('TSCOpen', function()
    local quickfix_plugin = self._plugins:get('quickfix')
    if quickfix_plugin then
      quickfix_plugin:open()
    end
  end, {
    desc = 'Open TypeScript errors in quickfix list',
  })
  
  -- Close quickfix command
  vim.api.nvim_create_user_command('TSCClose', function()
    local quickfix_plugin = self._plugins:get('quickfix')
    if quickfix_plugin then
      quickfix_plugin:close()
    end
  end, {
    desc = 'Close TypeScript errors quickfix list',
  })
  
  -- Toggle quickfix command
  vim.api.nvim_create_user_command('TSCToggle', function()
    local quickfix_plugin = self._plugins:get('quickfix')
    if quickfix_plugin then
      quickfix_plugin:toggle()
    end
  end, {
    desc = 'Toggle TypeScript errors quickfix list',
  })
end

---Set up autocommands
function TSC:_setup_autocommands()
  -- Auto-start watch mode if configured
  local watch_plugin = self._plugins:get('watch')
  if watch_plugin and watch_plugin._config.auto_start then
    vim.api.nvim_create_autocmd({'BufRead', 'BufNewFile'}, {
      pattern = {'*.ts', '*.tsx'},
      desc = 'Auto-start TypeScript watch mode',
      callback = function()
        self:run({watch = true})
      end,
    })
  end
end

---Run TypeScript type-checking
---@param opts? table Runtime options
---@return string Run ID
function TSC:run(opts)
  if not self._initialized then
    vim.notify('tsc.nvim not initialized. Call setup() first.', vim.log.levels.ERROR)
    return ''
  end
  
  opts = opts or {}
  
  -- Emit run requested event
  self._events:emit(Events.EVENTS.RUN_REQUESTED, {
    opts = opts,
  })
  
  -- Discover projects
  local mode = opts.mode or self._config:get_mode()
  local projects = self._discovery:find_projects(mode)
  
  if #projects == 0 then
    vim.notify('No TypeScript projects found', vim.log.levels.WARN)
    return ''
  end
  
  -- Emit project discovered event
  self._events:emit(Events.EVENTS.PROJECT_DISCOVERED, {
    projects = projects,
    mode = mode,
  })
  
  -- Run type-checking
  local run_id = self._runner:run(projects, opts)
  
  return run_id
end

---Stop all running TypeScript processes
---@return number Number of runs stopped
function TSC:stop()
  if not self._initialized then
    vim.notify('tsc.nvim not initialized. Call setup() first.', vim.log.levels.ERROR)
    return 0
  end
  
  local stopped = self._runner:stop_all()
  
  -- Emit stopped event
  self._events:emit(Events.EVENTS.STOPPED, {
    stopped_runs = stopped,
  })
  
  return stopped
end

---Get current status
---@return table Status information
function TSC:status()
  if not self._initialized then
    return {
      initialized = false,
      error = 'tsc.nvim not initialized',
    }
  end
  
  return {
    initialized = true,
    config = self._config:get_summary(),
    plugins = self._plugins:get_stats(),
    discovery = self._discovery:get_stats(),
    runner = self._runner:get_stats(),
  }
end

---Show status in a formatted way
function TSC:show_status()
  local status = self:status()
  
  if not status.initialized then
    vim.notify(status.error, vim.log.levels.ERROR)
    return
  end
  
  local lines = {
    'tsc.nvim Status:',
    '',
    string.format('Mode: %s', status.config.mode),
    string.format('TypeScript Binary: %s', status.config.typescript_bin),
    string.format('Flags: %s', status.config.typescript_flags),
    string.format('Timeout: %dms', status.config.timeout),
    '',
    'Plugins:',
    string.format('  Loaded: %d/%d', status.plugins.loaded, status.plugins.available),
    string.format('  Enabled: %s', table.concat(status.plugins.loaded_plugins, ', ')),
    '',
    'Runner:',
    string.format('  Active Runs: %d', status.runner.active_runs),
    string.format('  Running Processes: %d', status.runner.running_processes),
    '',
    'Discovery:',
    string.format('  Cache Entries: %d', status.discovery.cache_entries),
    string.format('  Cached Projects: %d', status.discovery.total_cached_projects),
  }
  
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

---Get plugin instance for advanced usage
---@param name string Plugin name
---@return Plugin|nil Plugin instance
function TSC:get_plugin(name)
  if not self._initialized then
    return nil
  end
  
  return self._plugins:get(name)
end

---Update configuration at runtime
---@param updates table Configuration updates
---@return boolean success
function TSC:update_config(updates)
  if not self._initialized then
    return false
  end
  
  return self._config:update(updates)
end

---Get events system for advanced usage
---@return Events
function TSC:get_events()
  return self._events
end

---Clean up resources
function TSC:cleanup()
  if not self._initialized then
    return
  end
  
  -- Stop all processes
  self:stop()
  
  -- Unload all plugins
  self._plugins:unload_all()
  
  -- Clear event listeners
  self._events:clear()
  
  -- Clear discovery cache
  self._discovery:clear_cache()
  
  self._initialized = false
end

-- Create default instance
local default_instance = nil

-- Module exports
local M = {}

---Setup tsc.nvim with configuration
---@param opts? table Configuration options
---@return TSC
function M.setup(opts)
  default_instance = TSC.setup(opts)
  return default_instance
end

---Run TypeScript type-checking
---@param opts? table Runtime options
---@return string Run ID
function M.run(opts)
  if not default_instance then
    vim.notify('tsc.nvim not initialized. Call setup() first.', vim.log.levels.ERROR)
    return ''
  end
  
  return default_instance:run(opts)
end

---Stop all running processes
---@return number Number of runs stopped
function M.stop()
  if not default_instance then
    return 0
  end
  
  return default_instance:stop()
end

---Get current status
---@return table Status information
function M.status()
  if not default_instance then
    return {
      initialized = false,
      error = 'tsc.nvim not initialized',
    }
  end
  
  return default_instance:status()
end

---Get plugin instance
---@param name string Plugin name
---@return Plugin|nil Plugin instance
function M.get_plugin(name)
  if not default_instance then
    return nil
  end
  
  return default_instance:get_plugin(name)
end

---Update configuration
---@param updates table Configuration updates
---@return boolean success
function M.update_config(updates)
  if not default_instance then
    return false
  end
  
  return default_instance:update_config(updates)
end

---Get events system
---@return Events
function M.get_events()
  if not default_instance then
    return nil
  end
  
  return default_instance:get_events()
end

---Clean up resources
function M.cleanup()
  if default_instance then
    default_instance:cleanup()
    default_instance = nil
  end
end

-- Export constants
M.EVENTS = Events.EVENTS

return M
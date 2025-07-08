# Creating Custom Plugins for tsc.nvim 3.0

This guide explains how to create custom plugins for tsc.nvim 3.0 using the new plugin architecture.

## Plugin Architecture Overview

tsc.nvim 3.0 uses an event-driven plugin system where:

- **Core** emits events during TypeScript compilation
- **Plugins** listen to events and perform actions
- **No direct coupling** between core and plugins
- **Easy to test** and maintain

## Basic Plugin Structure

Every plugin must implement the following interface:

```lua
---@class Plugin
---@field name string Plugin name
---@field version string Plugin version
---@field dependencies string[] Plugin dependencies
---@field enabled boolean Whether plugin is enabled
local MyPlugin = {}

---Create new plugin instance
---@param events Events Event system
---@param config table Plugin configuration
---@return MyPlugin
function MyPlugin.new(events, config)
  local self = {
    name = 'my_plugin',
    version = '1.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      -- Default configuration
      enabled = true,
      option1 = 'default_value',
    }, config or {}),
  }
  
  return setmetatable(self, { __index = MyPlugin })
end

---Initialize plugin (called once during setup)
function MyPlugin:setup()
  if not self._config.enabled then
    return
  end
  
  -- Subscribe to events
  self._events:on('tsc.completed', function(data)
    self:_handle_completion(data)
  end)
end

---Clean up plugin resources
function MyPlugin:cleanup()
  -- Clean up any resources
end

---Get plugin status
---@return table Status information
function MyPlugin:get_status()
  return {
    enabled = self._config.enabled,
    config = self._config,
  }
end

return MyPlugin
```

## Available Events

### Core Events

```lua
-- Lifecycle events
'tsc.initialized'        -- Plugin system initialized
'tsc.run_requested'      -- User requested type-checking
'tsc.started'            -- Type-checking started
'tsc.completed'          -- Type-checking completed
'tsc.stopped'            -- Type-checking stopped
'tsc.error'              -- Error occurred

-- Process events
'tsc.process_started'    -- Individual process started
'tsc.process_completed'  -- Individual process completed
'tsc.process_error'      -- Process error

-- Output events
'tsc.output_received'    -- Raw output received
'tsc.output_parsed'      -- Output parsed
'tsc.results_ready'      -- Results ready for consumption

-- Project events
'tsc.project_discovered' -- Project discovered
'tsc.project_validated'  -- Project validated

-- Watch events
'tsc.watch_started'      -- Watch mode started
'tsc.watch_stopped'      -- Watch mode stopped
'tsc.file_changed'       -- File changed in watch mode

-- Plugin events
'tsc.plugin_loaded'      -- Plugin loaded
'tsc.plugin_error'       -- Plugin error
```

### Event Data Structures

#### tsc.completed Event
```lua
{
  run_id = "string",           -- Unique run identifier
  results = {                  -- Array of project results
    {
      project = "string",      -- Project path
      errors = {               -- Array of errors
        {
          filename = "string", -- File path
          lnum = number,       -- Line number
          col = number,        -- Column number
          text = "string",     -- Error message
          type = "E",          -- Error type
        }
      },
      files = {"string"}       -- Array of files with errors
    }
  },
  errors = {},                 -- All errors (flattened)
  duration = number,           -- Execution duration in ms
  project_count = number,      -- Number of projects checked
}
```

#### tsc.file_changed Event
```lua
{
  file = "string",            -- Changed file path
  directory = "string",       -- Directory being watched
  event_type = table,         -- File system event details
}
```

## Plugin Examples

### 1. Notification Plugin

```lua
local NotificationPlugin = {}

function NotificationPlugin.new(events, config)
  local self = {
    name = 'notification',
    version = '1.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      enabled = true,
      show_success = true,
      show_errors = true,
      timeout = 5000,
    }, config or {}),
  }
  
  return setmetatable(self, { __index = NotificationPlugin })
end

function NotificationPlugin:setup()
  if not self._config.enabled then
    return
  end
  
  -- Listen for completion events
  self._events:on('tsc.completed', function(data)
    local error_count = #data.errors
    
    if error_count == 0 and self._config.show_success then
      vim.notify(
        '✅ TypeScript compilation successful!',
        vim.log.levels.INFO,
        { timeout = self._config.timeout }
      )
    elseif error_count > 0 and self._config.show_errors then
      vim.notify(
        string.format('❌ Found %d TypeScript errors', error_count),
        vim.log.levels.ERROR,
        { timeout = self._config.timeout }
      )
    end
  end)
  
  -- Listen for watch mode events
  self._events:on('tsc.watch_started', function()
    vim.notify(
      '👀 TypeScript watch mode started',
      vim.log.levels.INFO,
      { timeout = 2000 }
    )
  end)
end

function NotificationPlugin:cleanup()
  -- No cleanup needed
end

return NotificationPlugin
```

### 2. File Statistics Plugin

```lua
local StatsPlugin = {}

function StatsPlugin.new(events, config)
  local self = {
    name = 'stats',
    version = '1.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      enabled = true,
      track_history = true,
      max_history = 50,
    }, config or {}),
    _stats = {
      total_runs = 0,
      total_errors = 0,
      total_files_checked = 0,
      history = {},
    },
  }
  
  return setmetatable(self, { __index = StatsPlugin })
end

function StatsPlugin:setup()
  if not self._config.enabled then
    return
  end
  
  self._events:on('tsc.completed', function(data)
    self:_update_stats(data)
  end)
end

function StatsPlugin:_update_stats(data)
  self._stats.total_runs = self._stats.total_runs + 1
  self._stats.total_errors = self._stats.total_errors + #data.errors
  
  -- Count unique files
  local files = {}
  for _, result in ipairs(data.results) do
    for _, file in ipairs(result.files) do
      files[file] = true
    end
  end
  self._stats.total_files_checked = self._stats.total_files_checked + vim.tbl_count(files)
  
  -- Track history
  if self._config.track_history then
    table.insert(self._stats.history, {
      timestamp = os.time(),
      errors = #data.errors,
      duration = data.duration,
      projects = data.project_count,
    })
    
    -- Limit history size
    if #self._stats.history > self._config.max_history then
      table.remove(self._stats.history, 1)
    end
  end
end

function StatsPlugin:get_stats()
  return vim.deepcopy(self._stats)
end

function StatsPlugin:get_status()
  return {
    enabled = self._config.enabled,
    stats = self._stats,
    config = self._config,
  }
end

function StatsPlugin:reset_stats()
  self._stats = {
    total_runs = 0,
    total_errors = 0,
    total_files_checked = 0,
    history = {},
  }
end

function StatsPlugin:cleanup()
  -- Save stats to file if needed
end

return StatsPlugin
```

### 3. Slack Integration Plugin

```lua
local SlackPlugin = {}

function SlackPlugin.new(events, config)
  local self = {
    name = 'slack',
    version = '1.0.0',
    dependencies = {'curl'},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      enabled = false,  -- Disabled by default
      webhook_url = nil,
      channel = '#dev',
      username = 'TypeScript Bot',
      only_on_errors = true,
      min_errors_to_notify = 1,
    }, config or {}),
  }
  
  return setmetatable(self, { __index = SlackPlugin })
end

function SlackPlugin:setup()
  if not self._config.enabled or not self._config.webhook_url then
    return
  end
  
  self._events:on('tsc.completed', function(data)
    self:_maybe_send_notification(data)
  end)
end

function SlackPlugin:_maybe_send_notification(data)
  local error_count = #data.errors
  
  -- Check if we should send notification
  if self._config.only_on_errors and error_count == 0 then
    return
  end
  
  if error_count < self._config.min_errors_to_notify then
    return
  end
  
  -- Build message
  local message = self:_build_message(data)
  
  -- Send to Slack
  self:_send_to_slack(message)
end

function SlackPlugin:_build_message(data)
  local error_count = #data.errors
  local project_count = data.project_count
  
  if error_count == 0 then
    return {
      text = '✅ TypeScript compilation successful!',
      color = 'good',
    }
  else
    local files_with_errors = {}
    for _, error in ipairs(data.errors) do
      files_with_errors[error.filename] = true
    end
    
    return {
      text = string.format(
        '❌ TypeScript compilation failed: %d errors in %d files across %d projects',
        error_count,
        vim.tbl_count(files_with_errors),
        project_count
      ),
      color = 'danger',
    }
  end
end

function SlackPlugin:_send_to_slack(message)
  local payload = vim.fn.json_encode({
    channel = self._config.channel,
    username = self._config.username,
    text = message.text,
    attachments = {
      {
        color = message.color,
        text = message.text,
      }
    }
  })
  
  -- Send async request
  vim.system({
    'curl',
    '-X', 'POST',
    '-H', 'Content-type: application/json',
    '--data', payload,
    self._config.webhook_url
  }, {
    detach = true,
  }, function(result)
    if result.code ~= 0 then
      vim.notify(
        'Failed to send Slack notification: ' .. (result.stderr or 'Unknown error'),
        vim.log.levels.ERROR
      )
    end
  end)
end

function SlackPlugin:cleanup()
  -- No cleanup needed
end

return SlackPlugin
```

## Plugin Registration

### Manual Registration

```lua
-- In your configuration
require('tsc').setup({
  plugins = {
    -- Core plugins
    quickfix = { enabled = true },
    watch = { enabled = false },
    
    -- Custom plugins
    notification = {
      enabled = true,
      show_success = true,
      timeout = 3000,
    },
    stats = {
      enabled = true,
      track_history = true,
    },
    slack = {
      enabled = true,
      webhook_url = 'https://hooks.slack.com/services/...',
      channel = '#typescript',
    },
  }
})

-- Register custom plugins
local tsc_instance = require('tsc')
local plugin_manager = tsc_instance:get_plugin_manager()

plugin_manager:register('notification', function(events, config)
  return require('my.plugins.notification').new(events, config)
end)

plugin_manager:register('stats', function(events, config)
  return require('my.plugins.stats').new(events, config)
end)
```

### Plugin Discovery

You can also create plugins that auto-register:

```lua
-- lua/tsc-plugins/my-plugin.lua
local MyPlugin = require('my.plugin')

-- Auto-register when required
local tsc = require('tsc')
if tsc.register_plugin then
  tsc.register_plugin('my_plugin', MyPlugin)
end

return MyPlugin
```

## Best Practices

### 1. Error Handling

```lua
function MyPlugin:setup()
  self._events:on('tsc.completed', function(data)
    local success, err = pcall(function()
      self:_handle_completion(data)
    end)
    
    if not success then
      vim.notify(
        string.format('Plugin %s error: %s', self.name, err),
        vim.log.levels.ERROR
      )
    end
  end)
end
```

### 2. Configuration Validation

```lua
function MyPlugin.new(events, config)
  -- Validate required configuration
  if config.webhook_url and not config.webhook_url:match('^https?://') then
    error('Invalid webhook_url: must be a valid HTTP/HTTPS URL')
  end
  
  local self = {
    -- ... plugin setup
  }
  
  return setmetatable(self, { __index = MyPlugin })
end
```

### 3. Resource Management

```lua
function MyPlugin:cleanup()
  -- Stop timers
  if self._timer then
    vim.fn.timer_stop(self._timer)
  end
  
  -- Close files
  if self._log_file then
    self._log_file:close()
  end
  
  -- Clear references
  self._cache = {}
end
```

### 4. Testing

```lua
-- tests/my_plugin_spec.lua
describe('MyPlugin', function()
  local events, plugin
  
  before_each(function()
    events = require('tsc.core.events').new()
    plugin = require('my.plugin').new(events, {
      enabled = true,
      test_option = 'test_value',
    })
    plugin:setup()
  end)
  
  it('should handle completion events', function()
    local handled = false
    
    plugin._handle_completion = function()
      handled = true
    end
    
    events:emit('tsc.completed', { errors = {} })
    vim.wait(10)  -- Allow async processing
    
    assert.is_true(handled)
  end)
end)
```

## Plugin Ideas

Here are some ideas for useful plugins:

1. **Git Integration**: Commit/tag when no errors
2. **Coverage Plugin**: Track test coverage changes
3. **Performance Monitor**: Track compilation performance
4. **Error Trends**: Analyze error patterns over time
5. **Team Dashboard**: Share compilation status with team
6. **Auto-fix**: Attempt to fix common errors
7. **Documentation**: Generate docs from TypeScript types
8. **Metrics Export**: Export metrics to monitoring systems

## Conclusion

The tsc.nvim 3.0 plugin system provides a powerful and flexible way to extend TypeScript integration in Neovim. By following the patterns and examples in this guide, you can create plugins that enhance your development workflow while maintaining clean separation from the core functionality.
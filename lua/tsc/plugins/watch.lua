---@class WatchPlugin
---@field name string Plugin name
---@field version string Plugin version
---@field dependencies string[] Plugin dependencies
---@field enabled boolean Whether plugin is enabled
---@field private _events Events Event system
---@field private _config table Plugin configuration
---@field private _watchers table<string, uv_fs_event_t> Active file watchers
---@field private _debounce_timers table<string, number> Debounce timers
---@field private _watching boolean Whether watch mode is active
---@field private _paused boolean Whether watching is paused
local WatchPlugin = {}

---Create new watch plugin
---@param events Events Event system
---@param config table Plugin configuration
---@return WatchPlugin
function WatchPlugin.new(events, config)
  local self = {
    name = 'watch',
    version = '3.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      enabled = false,
      auto_start = false,
      debounce_ms = 500,
      patterns = {'*.ts', '*.tsx', '*.mts', '*.cts'},
      ignore_patterns = {'node_modules', '.git', 'dist', 'build'},
      preserve_focus = true,
      clear_on_change = false,
      notify_on_change = true,
    }, config or {}),
    _watchers = {},
    _debounce_timers = {},
    _watching = false,
    _paused = false,
  }
  
  return setmetatable(self, { __index = WatchPlugin })
end

---Initialize plugin
function WatchPlugin:setup()
  if not self._config.enabled then
    return
  end
  
  -- Subscribe to runner events
  self._events:on('tsc.started', function(data)
    if data.watch then
      self:_handle_watch_start(data)
    end
  end)
  
  self._events:on('tsc.stopped', function(data)
    self:stop_watching()
  end)
  
  -- Subscribe to completion events for incremental compilation
  self._events:on('tsc.completed', function(data)
    if self._watching and not self._paused then
      -- Re-enable watchers after compilation
      self:_update_watchers()
    end
  end)
  
  -- Set up auto-start if configured
  if self._config.auto_start then
    self:_setup_auto_start()
  end
end

---Handle watch mode start
---@param data table Start event data
function WatchPlugin:_handle_watch_start(data)
  self._watching = true
  self._paused = false
  
  -- Start watching project directories
  for _, project in ipairs(data.projects or {}) do
    self:_watch_project(project)
  end
  
  -- Emit watch started event
  self._events:emit('tsc.watch_started', {
    projects = data.projects,
    config = self._config,
  })
end

---Watch a project directory
---@param project table Project information
function WatchPlugin:_watch_project(project)
  local watch_dir = project.root
  
  -- Skip if already watching
  if self._watchers[watch_dir] then
    return
  end
  
  -- Create file watcher
  local watcher = vim.loop.new_fs_event()
  
  local function on_change(err, filename, events)
    if err then
      vim.notify(
        string.format('Watch error for %s: %s', watch_dir, err),
        vim.log.levels.ERROR
      )
      return
    end
    
    -- Check if file matches patterns
    if self:_should_watch_file(filename) then
      self:_handle_file_change(watch_dir, filename, events)
    end
  end
  
  -- Start watching with recursive flag
  local success, err = watcher:start(watch_dir, {
    recursive = true,
  }, on_change)
  
  if success then
    self._watchers[watch_dir] = watcher
  else
    vim.notify(
      string.format('Failed to watch %s: %s', watch_dir, err),
      vim.log.levels.ERROR
    )
  end
end

---Check if file should trigger recompilation
---@param filename string File name
---@return boolean
function WatchPlugin:_should_watch_file(filename)
  if not filename then
    return false
  end
  
  -- Check ignore patterns
  for _, pattern in ipairs(self._config.ignore_patterns) do
    if filename:match(pattern) then
      return false
    end
  end
  
  -- Check watch patterns
  for _, pattern in ipairs(self._config.patterns) do
    -- Convert glob pattern to lua pattern
    local lua_pattern = pattern:gsub('*', '.*'):gsub('%.', '%%.')
    if filename:match(lua_pattern .. '$') then
      return true
    end
  end
  
  return false
end

---Handle file change event
---@param watch_dir string Directory being watched
---@param filename string Changed file
---@param events table File system events
function WatchPlugin:_handle_file_change(watch_dir, filename, events)
  if self._paused then
    return
  end
  
  local full_path = vim.fn.fnamemodify(watch_dir .. '/' .. filename, ':p')
  
  -- Debounce the change
  self:_debounce_change(full_path, function()
    -- Notify about change if configured
    if self._config.notify_on_change then
      vim.notify(
        string.format('File changed: %s', filename),
        vim.log.levels.INFO
      )
    end
    
    -- Clear errors if configured
    if self._config.clear_on_change then
      local quickfix_plugin = self._events:emit('tsc.request_plugin', {plugin = 'quickfix'})
      if quickfix_plugin then
        quickfix_plugin:clear()
      end
    end
    
    -- Emit file change event
    self._events:emit('tsc.file_changed', {
      file = full_path,
      directory = watch_dir,
      event_type = events,
    })
    
    -- Trigger incremental compilation
    self._events:emit('tsc.run_requested', {
      watch = true,
      incremental = true,
      changed_file = full_path,
    })
  end)
end

---Debounce file changes
---@param key string Debounce key
---@param callback function Callback to execute
function WatchPlugin:_debounce_change(key, callback)
  -- Cancel existing timer
  if self._debounce_timers[key] then
    vim.fn.timer_stop(self._debounce_timers[key])
  end
  
  -- Set new timer
  self._debounce_timers[key] = vim.fn.timer_start(
    self._config.debounce_ms,
    function()
      self._debounce_timers[key] = nil
      callback()
    end
  )
end

---Stop watching all directories
function WatchPlugin:stop_watching()
  self._watching = false
  
  -- Stop all watchers
  for dir, watcher in pairs(self._watchers) do
    watcher:stop()
  end
  self._watchers = {}
  
  -- Cancel all debounce timers
  for _, timer in pairs(self._debounce_timers) do
    vim.fn.timer_stop(timer)
  end
  self._debounce_timers = {}
  
  -- Emit watch stopped event
  self._events:emit('tsc.watch_stopped', {})
end

---Pause watching
function WatchPlugin:pause()
  self._paused = true
  
  -- Cancel pending timers
  for _, timer in pairs(self._debounce_timers) do
    vim.fn.timer_stop(timer)
  end
  self._debounce_timers = {}
end

---Resume watching
function WatchPlugin:resume()
  self._paused = false
end

---Update watchers (e.g., after configuration change)
function WatchPlugin:_update_watchers()
  if not self._watching or self._paused then
    return
  end
  
  -- Re-evaluate watched directories
  -- This is called after compilation to ensure watchers are still active
end

---Set up auto-start functionality
function WatchPlugin:_setup_auto_start()
  vim.api.nvim_create_autocmd({'BufRead', 'BufNewFile'}, {
    pattern = self._config.patterns,
    group = vim.api.nvim_create_augroup('tsc_watch_auto_start', { clear = true }),
    desc = 'Auto-start TypeScript watch mode',
    callback = function(ev)
      -- Only start if not already watching
      if not self._watching then
        -- Find project for current buffer
        local bufname = vim.api.nvim_buf_get_name(ev.buf)
        local project_root = vim.fn.fnamemodify(bufname, ':h')
        
        -- Look for tsconfig.json
        local tsconfig = vim.fn.findfile('tsconfig.json', project_root .. ';')
        if tsconfig and tsconfig ~= '' then
          -- Request watch mode start
          self._events:emit('tsc.run_requested', {
            watch = true,
            auto_start = true,
          })
        end
      end
    end,
  })
end

---Get plugin status
---@return table Status information
function WatchPlugin:get_status()
  local watched_dirs = vim.tbl_keys(self._watchers)
  local active_timers = vim.tbl_count(self._debounce_timers)
  
  return {
    watching = self._watching,
    paused = self._paused,
    watched_directories = watched_dirs,
    watcher_count = #watched_dirs,
    active_timers = active_timers,
    config = self._config,
  }
end

---Update plugin configuration
---@param new_config table New configuration
function WatchPlugin:update_config(new_config)
  self._config = vim.tbl_deep_extend('force', self._config, new_config)
  
  -- Update watchers if needed
  if self._watching then
    self:_update_watchers()
  end
end

---Clean up plugin resources
function WatchPlugin:cleanup()
  self:stop_watching()
end

return WatchPlugin
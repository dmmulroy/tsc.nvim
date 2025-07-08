---@class Events
---@field private _listeners table<string, function[]>
---@field private _once_listeners table<string, function[]>
local Events = {}

---Create new event system
---@return Events
function Events.new()
  local self = {
    _listeners = {},
    _once_listeners = {},
  }
  return setmetatable(self, { __index = Events })
end

---Emit an event to all listeners
---@param event string Event name
---@param data? table Event data
function Events:emit(event, data)
  if not event or type(event) ~= "string" then
    vim.notify("Events:emit() requires a valid event name", vim.log.levels.ERROR)
    return
  end

  data = data or {}
  data.event = event
  data.timestamp = vim.loop.now()

  -- Call regular listeners
  local listeners = self._listeners[event] or {}
  for _, callback in ipairs(listeners) do
    vim.schedule(function()
      local success, err = pcall(callback, data)
      if not success then
        vim.notify(string.format('Error in event listener for "%s": %s', event, err), vim.log.levels.ERROR)
      end
    end)
  end

  -- Call once listeners
  local once_listeners = self._once_listeners[event] or {}
  for _, callback in ipairs(once_listeners) do
    vim.schedule(function()
      local success, err = pcall(callback, data)
      if not success then
        vim.notify(string.format('Error in once event listener for "%s": %s', event, err), vim.log.levels.ERROR)
      end
    end)
  end

  -- Clear once listeners after calling them
  self._once_listeners[event] = {}
end

---Subscribe to an event
---@param event string Event name
---@param callback function Event callback
---@return function Unsubscribe function
function Events:on(event, callback)
  if not event or type(event) ~= "string" then
    vim.notify("Events:on() requires a valid event name", vim.log.levels.ERROR)
    return function() end
  end

  if not callback or type(callback) ~= "function" then
    vim.notify("Events:on() requires a valid callback function", vim.log.levels.ERROR)
    return function() end
  end

  -- Initialize event listeners array if it doesn't exist
  if not self._listeners[event] then
    self._listeners[event] = {}
  end

  -- Add callback to listeners
  table.insert(self._listeners[event], callback)

  -- Return unsubscribe function
  return function()
    self:off(event, callback)
  end
end

---Unsubscribe from an event
---@param event string Event name
---@param callback function Event callback
function Events:off(event, callback)
  if not event or not self._listeners[event] then
    return
  end

  local listeners = self._listeners[event]
  for i, listener in ipairs(listeners) do
    if listener == callback then
      table.remove(listeners, i)
      break
    end
  end
end

---Subscribe to event once
---@param event string Event name
---@param callback function Event callback
---@return function Unsubscribe function
function Events:once(event, callback)
  if not event or type(event) ~= "string" then
    vim.notify("Events:once() requires a valid event name", vim.log.levels.ERROR)
    return function() end
  end

  if not callback or type(callback) ~= "function" then
    vim.notify("Events:once() requires a valid callback function", vim.log.levels.ERROR)
    return function() end
  end

  -- Initialize once listeners array if it doesn't exist
  if not self._once_listeners[event] then
    self._once_listeners[event] = {}
  end

  -- Add callback to once listeners
  table.insert(self._once_listeners[event], callback)

  -- Return unsubscribe function
  return function()
    local once_listeners = self._once_listeners[event]
    if once_listeners then
      for i, listener in ipairs(once_listeners) do
        if listener == callback then
          table.remove(once_listeners, i)
          break
        end
      end
    end
  end
end

---Get all listeners for an event
---@param event string Event name
---@return function[] listeners
function Events:get_listeners(event)
  return self._listeners[event] or {}
end

---Get all once listeners for an event
---@param event string Event name
---@return function[] once_listeners
function Events:get_once_listeners(event)
  return self._once_listeners[event] or {}
end

---Clear all listeners for an event
---@param event string Event name
function Events:clear(event)
  if event then
    self._listeners[event] = {}
    self._once_listeners[event] = {}
  else
    -- Clear all listeners
    self._listeners = {}
    self._once_listeners = {}
  end
end

---Get event statistics
---@return table Statistics
function Events:stats()
  local regular_count = 0
  local once_count = 0

  for _, listeners in pairs(self._listeners) do
    regular_count = regular_count + #listeners
  end

  for _, listeners in pairs(self._once_listeners) do
    once_count = once_count + #listeners
  end

  return {
    regular_listeners = regular_count,
    once_listeners = once_count,
    total_events = vim.tbl_count(self._listeners),
  }
end

-- Event constants
Events.EVENTS = {
  -- Lifecycle events
  INITIALIZED = "tsc.initialized",
  RUN_REQUESTED = "tsc.run_requested",
  STARTED = "tsc.started",
  COMPLETED = "tsc.completed",
  STOPPED = "tsc.stopped",
  ERROR = "tsc.error",

  -- Process events
  PROCESS_STARTED = "tsc.process_started",
  PROCESS_COMPLETED = "tsc.process_completed",
  PROCESS_ERROR = "tsc.process_error",

  -- Output events
  OUTPUT_RECEIVED = "tsc.output_received",
  OUTPUT_PARSED = "tsc.output_parsed",
  RESULTS_READY = "tsc.results_ready",

  -- Project events
  PROJECT_DISCOVERED = "tsc.project_discovered",
  PROJECT_VALIDATED = "tsc.project_validated",
  PROJECTS_DISCOVERED = "tsc.projects_discovered",
  DISCOVERY_PROGRESS = "tsc.discovery_progress",

  -- Batch processing events
  BATCH_STARTED = "tsc.batch_started",
  BATCH_QUEUED = "tsc.batch_queued",
  BATCH_PROCESSING = "tsc.batch_processing",
  BATCH_COMPLETED = "tsc.batch_completed",
  BATCH_CANCELLED = "tsc.batch_cancelled",
  BATCH_RETRY = "tsc.batch_retry",
  BATCH_ALL_COMPLETED = "tsc.batch_all_completed",

  -- Queue events
  QUEUE_PROGRESS = "tsc.queue_progress",
  PROJECT_QUEUED = "tsc.project_queued",
  PROJECT_DEQUEUED = "tsc.project_dequeued",
  PROJECT_COMPLETED = "tsc.project_completed",

  -- Watch events
  WATCH_STARTED = "tsc.watch_started",
  WATCH_STOPPED = "tsc.watch_stopped",
  FILE_CHANGED = "tsc.file_changed",

  -- Plugin events
  PLUGIN_LOADED = "tsc.plugin_loaded",
  PLUGIN_ERROR = "tsc.plugin_error",
}

return Events

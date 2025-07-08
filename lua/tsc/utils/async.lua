---@class AsyncUtils
local M = {}

---@class Promise
---@field private _state string State: 'pending', 'resolved', 'rejected'
---@field private _value any Resolved value
---@field private _reason any Rejection reason
---@field private _callbacks table Callback functions
local Promise = {}
Promise.__index = Promise

---Create a new promise
---@param executor function Executor function(resolve, reject)
---@return Promise
function M.promise(executor)
  local self = setmetatable({
    _state = 'pending',
    _value = nil,
    _reason = nil,
    _callbacks = { resolved = {}, rejected = {} },
  }, Promise)
  
  local function resolve(value)
    if self._state ~= 'pending' then
      return
  end
    
    self._state = 'resolved'
    self._value = value
    
    -- Execute resolved callbacks
    vim.schedule(function()
      for _, callback in ipairs(self._callbacks.resolved) do
        callback(value)
      end
    end)
  end
  
  local function reject(reason)
    if self._state ~= 'pending' then
      return
    end
    
    self._state = 'rejected'
    self._reason = reason
    
    -- Execute rejected callbacks
    vim.schedule(function()
      for _, callback in ipairs(self._callbacks.rejected) do
        callback(reason)
      end
    end)
  end
  
  -- Execute the executor
  local success, err = pcall(executor, resolve, reject)
  if not success then
    reject(err)
  end
  
  return self
end

---Add success callback
---@param on_resolved function Success callback
---@return Promise
function Promise:next(on_resolved)
  return M.promise(function(resolve, reject)
    local function handle_resolved(value)
      local success, result = pcall(on_resolved, value)
      if success then
        resolve(result)
      else
        reject(result)
      end
    end
    
    if self._state == 'resolved' then
      vim.schedule(function()
        handle_resolved(self._value)
      end)
    elseif self._state == 'pending' then
      table.insert(self._callbacks.resolved, handle_resolved)
    end
    
    -- Pass through rejections
    if self._state == 'rejected' then
      reject(self._reason)
    elseif self._state == 'pending' then
      table.insert(self._callbacks.rejected, reject)
    end
  end)
end

---Add error callback
---@param on_rejected function Error callback
---@return Promise
function Promise:catch(on_rejected)
  return M.promise(function(resolve, reject)
    local function handle_rejected(reason)
      local success, result = pcall(on_rejected, reason)
      if success then
        resolve(result)
      else
        reject(result)
      end
    end
    
    if self._state == 'rejected' then
      vim.schedule(function()
        handle_rejected(self._reason)
      end)
    elseif self._state == 'pending' then
      table.insert(self._callbacks.rejected, handle_rejected)
    end
    
    -- Pass through resolutions
    if self._state == 'resolved' then
      resolve(self._value)
    elseif self._state == 'pending' then
      table.insert(self._callbacks.resolved, resolve)
    end
  end)
end

---Add finally callback
---@param on_finally function Finally callback
---@return Promise
function Promise:finally(on_finally)
  return self:next(function(value)
    on_finally()
    return value
  end):catch(function(reason)
    on_finally()
    error(reason)
  end)
end

---Create immediately resolved promise
---@param value any Resolved value
---@return Promise
function M.resolve(value)
  return M.promise(function(resolve)
    resolve(value)
  end)
end

---Create immediately rejected promise
---@param reason any Rejection reason
---@return Promise
function M.reject(reason)
  return M.promise(function(_, reject)
    reject(reason)
  end)
end

---Wait for all promises to resolve
---@param promises Promise[] Array of promises
---@return Promise
function M.all(promises)
  return M.promise(function(resolve, reject)
    local results = {}
    local resolved_count = 0
    local total = #promises
    
    if total == 0 then
      resolve(results)
      return
    end
    
    for i, promise in ipairs(promises) do
      promise:next(function(value)
        results[i] = value
        resolved_count = resolved_count + 1
        
        if resolved_count == total then
          resolve(results)
        end
      end):catch(reject)
    end
  end)
end

---Race promises - resolve/reject with first to settle
---@param promises Promise[] Array of promises
---@return Promise
function M.race(promises)
  return M.promise(function(resolve, reject)
    for _, promise in ipairs(promises) do
      promise:next(resolve):catch(reject)
    end
  end)
end

---Create async function wrapper
---@param fn function Function to wrap
---@return function Async function
function M.async(fn)
  return function(...)
    local args = {...}
    local co = coroutine.create(fn)
    
    local function step(...)
      local success, result = coroutine.resume(co, ...)
      
      if not success then
        error(result)
      end
      
      if coroutine.status(co) == 'dead' then
        return result
      end
      
      -- Handle yielded promise
      if type(result) == 'table' and result.next then
        result:next(step):catch(function(err)
          coroutine.resume(co, nil, err)
        end)
      else
        -- Handle regular yield
        vim.schedule(function()
          step(result)
        end)
      end
    end
    
    step(unpack(args))
  end
end

---Await a promise (use in async function)
---@param promise Promise Promise to await
---@return any Resolved value
function M.await(promise)
  local value, err = coroutine.yield(promise)
  if err then
    error(err)
  end
  return value
end

---Sleep for specified milliseconds
---@param ms number Milliseconds to sleep
---@return Promise
function M.sleep(ms)
  return M.promise(function(resolve)
    vim.defer_fn(resolve, ms)
  end)
end

---Run function with timeout
---@param fn function Function to run
---@param timeout_ms number Timeout in milliseconds
---@return Promise
function M.timeout(fn, timeout_ms)
  return M.race({
    M.promise(fn),
    M.sleep(timeout_ms):next(function()
      error('Operation timed out')
    end),
  })
end

---Debounce function calls
---@param fn function Function to debounce
---@param delay_ms number Delay in milliseconds
---@return function Debounced function
function M.debounce(fn, delay_ms)
  local timer = nil
  
  return function(...)
    local args = {...}
    
    if timer then
      vim.fn.timer_stop(timer)
    end
    
    timer = vim.fn.timer_start(delay_ms, function()
      timer = nil
      fn(unpack(args))
    end)
  end
end

---Throttle function calls
---@param fn function Function to throttle
---@param limit_ms number Minimum time between calls
---@return function Throttled function
function M.throttle(fn, limit_ms)
  local last_call = 0
  local timer = nil
  local pending_args = nil
  
  return function(...)
    local now = vim.loop.now()
    local time_since_last = now - last_call
    
    if time_since_last >= limit_ms then
      last_call = now
      fn(...)
    else
      pending_args = {...}
      
      if not timer then
        local remaining = limit_ms - time_since_last
        timer = vim.fn.timer_start(remaining, function()
          timer = nil
          last_call = vim.loop.now()
          if pending_args then
            fn(unpack(pending_args))
            pending_args = nil
          end
        end)
      end
    end
  end
end

---Batch function calls
---@param fn function Function to batch (receives array of arguments)
---@param delay_ms number Delay before executing batch
---@return function Batched function
function M.batch(fn, delay_ms)
  local batch = {}
  local timer = nil
  
  return function(...)
    table.insert(batch, {...})
    
    if timer then
      vim.fn.timer_stop(timer)
    end
    
    timer = vim.fn.timer_start(delay_ms, function()
      timer = nil
      local current_batch = batch
      batch = {}
      fn(current_batch)
    end)
  end
end

---Async file read
---@param path string File path
---@return Promise
function M.read_file_async(path)
  return M.promise(function(resolve, reject)
    vim.loop.fs_open(path, 'r', 438, function(err, fd)
      if err then
        reject(err)
        return
      end
      
      vim.loop.fs_fstat(fd, function(err, stat)
        if err then
          vim.loop.fs_close(fd)
          reject(err)
          return
        end
        
        vim.loop.fs_read(fd, stat.size, 0, function(err, data)
          vim.loop.fs_close(fd)
          
          if err then
            reject(err)
          else
            resolve(data)
          end
        end)
      end)
    end)
  end)
end

---Async file write
---@param path string File path
---@param data string File content
---@return Promise
function M.write_file_async(path, data)
  return M.promise(function(resolve, reject)
    vim.loop.fs_open(path, 'w', 438, function(err, fd)
      if err then
        reject(err)
        return
      end
      
      vim.loop.fs_write(fd, data, 0, function(err, bytes)
        vim.loop.fs_close(fd)
        
        if err then
          reject(err)
        else
          resolve(bytes)
        end
      end)
    end)
  end)
end

---Async directory listing
---@param path string Directory path
---@return Promise
function M.readdir_async(path)
  return M.promise(function(resolve, reject)
    vim.loop.fs_scandir(path, function(err, handle)
      if err then
        reject(err)
        return
      end
      
      local entries = {}
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then
          break
        end
        table.insert(entries, { name = name, type = type })
      end
      
      resolve(entries)
    end)
  end)
end

---Create async event emitter
---@return table Event emitter
function M.event_emitter()
  local emitter = {
    _listeners = {},
  }
  
  function emitter:on(event, callback)
    if not self._listeners[event] then
      self._listeners[event] = {}
    end
    table.insert(self._listeners[event], callback)
    
    return function()
      self:off(event, callback)
    end
  end
  
  function emitter:off(event, callback)
    local listeners = self._listeners[event]
    if listeners then
      for i, cb in ipairs(listeners) do
        if cb == callback then
          table.remove(listeners, i)
          break
        end
      end
    end
  end
  
  function emitter:emit(event, ...)
    local listeners = self._listeners[event]
    if listeners then
      for _, callback in ipairs(listeners) do
        M.promise(function(resolve)
          callback(...)
          resolve()
        end):catch(function(err)
          vim.notify(
            string.format('Event handler error for %s: %s', event, err),
            vim.log.levels.ERROR
          )
        end)
      end
    end
  end
  
  return emitter
end

---Run tasks in parallel with concurrency limit
---@param tasks function[] Array of task functions
---@param limit number Maximum concurrent tasks
---@return Promise
function M.parallel_limit(tasks, limit)
  return M.promise(function(resolve, reject)
    local results = {}
    local running = 0
    local index = 1
    local failed = false
    
    local function run_next()
      if failed then
        return
      end
      
      if index > #tasks and running == 0 then
        resolve(results)
        return
      end
      
      while running < limit and index <= #tasks do
        local current_index = index
        index = index + 1
        running = running + 1
        
        M.promise(tasks[current_index]):next(function(result)
          results[current_index] = result
          running = running - 1
          run_next()
        end):catch(function(err)
          failed = true
          reject(err)
        end)
      end
    end
    
    run_next()
  end)
end

return M
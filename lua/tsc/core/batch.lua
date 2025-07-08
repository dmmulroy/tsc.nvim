---@class tsc.BatchProcessor
---@field private _queue tsc.Queue The project queue
---@field private _config BatchConfig Configuration
---@field private _events tsc.Events Event emitter
---@field private _active_batches table<string, Batch> Currently processing batches
---@field private _completed_count number Number of completed projects
---@field private _failed_count number Number of failed projects
---@field private _total_count number Total number of projects
---@field private _start_time number Processing start time
---@field private _is_running boolean Whether processing is active
local BatchProcessor = {}
BatchProcessor.__index = BatchProcessor

---@class BatchConfig
---@field size number Number of projects per batch
---@field concurrency number Maximum concurrent processes
---@field strategy string Batching strategy
---@field progressive_results boolean Report results as they complete
---@field retry_failed boolean Whether to retry failed projects
---@field retry_count number Maximum retry attempts
---@field memory_limit? string Maximum memory usage (e.g., "2GB")
---@field timeout_per_project number Timeout per project in ms

---@class Batch
---@field id string Unique batch identifier
---@field projects table<string, Project> Projects in this batch
---@field status string Current status (pending|processing|completed|failed)
---@field start_time number When batch started processing
---@field end_time? number When batch completed
---@field results table<string, any> Results keyed by project path

---@class Project
---@field path string Project path
---@field tsconfig string Path to tsconfig.json
---@field priority number Project priority
---@field metadata table Additional metadata
---@field retry_count number Number of retry attempts
---@field status string Current status

local async = require("tsc.utils.async")

---Create a new batch processor
---@param queue tsc.Queue The project queue
---@param config BatchConfig Configuration
---@param events tsc.Events Event emitter
---@return tsc.BatchProcessor
function BatchProcessor.new(queue, config, events)
  local self = setmetatable({}, BatchProcessor)
  
  self._queue = queue
  self._config = vim.tbl_extend("force", {
    size = 5,
    concurrency = 3,
    strategy = "size",
    progressive_results = true,
    retry_failed = true,
    retry_count = 2,
    timeout_per_project = 30000
  }, config or {})
  self._events = events
  self._active_batches = {}
  self._completed_count = 0
  self._failed_count = 0
  self._total_count = queue:size()
  self._is_running = false
  
  return self
end

---Start processing the queue
---@param runner_fn function Function to run a batch of projects
---@return tsc.Promise
function BatchProcessor:start(runner_fn)
  if self._is_running then
    return async.reject("Batch processor is already running")
  end
  
  self._is_running = true
  self._start_time = vim.loop.now()
  self._completed_count = 0
  self._failed_count = 0
  
  -- Emit start event
  self._events:emit("tsc.batch_started", {
    total_projects = self._total_count,
    batch_size = self._config.size,
    concurrency = self._config.concurrency,
    strategy = self._config.strategy
  })
  
  return async.run(function()
    return self:_process_queue(runner_fn)
  end):finally(function()
    self._is_running = false
    self:_emit_completion()
  end)
end

---Process the entire queue
---@private
---@param runner_fn function
---@return any
function BatchProcessor:_process_queue(runner_fn)
  local results = {}
  local active_count = 0
  local max_concurrent = self._config.concurrency
  
  -- Process batches with concurrency control
  local function process_next_batch()
    if self._queue:is_empty() or active_count >= max_concurrent then
      return
    end
    
    -- Get next batch of projects
    local batch_items = self._queue:pop_many(self._config.size)
    if #batch_items == 0 then
      return
    end
    
    active_count = active_count + 1
    local batch = self:_create_batch(batch_items)
    
    -- Emit batch event
    self._events:emit("tsc.batch_queued", {
      batch_id = batch.id,
      project_count = vim.tbl_count(batch.projects),
      projects = vim.tbl_keys(batch.projects)
    })
    
    -- Process batch asynchronously
    async.run(function()
      return self:_process_batch(batch, runner_fn)
    end):then(function(batch_results)
      -- Store results
      for project, result in pairs(batch_results) do
        results[project] = result
      end
      
      -- Update counts
      self:_update_counts(batch_results)
      
      -- Emit progress
      self:_emit_progress()
      
      active_count = active_count - 1
      
      -- Process next batch
      process_next_batch()
    end):catch(function(err)
      vim.notify("Batch processing error: " .. tostring(err), vim.log.levels.ERROR)
      active_count = active_count - 1
      process_next_batch()
    end)
  end
  
  -- Start initial batches up to concurrency limit
  for _ = 1, max_concurrent do
    process_next_batch()
  end
  
  -- Wait for all batches to complete
  local check_interval = 100 -- ms
  while active_count > 0 or not self._queue:is_empty() do
    async.wait(check_interval)
  end
  
  return results
end

---Create a batch from queue items
---@private
---@param items table Array of queue items
---@return Batch
function BatchProcessor:_create_batch(items)
  local batch = {
    id = string.format("batch_%d_%d", os.time(), math.random(10000)),
    projects = {},
    status = "pending",
    start_time = vim.loop.now(),
    results = {}
  }
  
  for _, item in ipairs(items) do
    local project = item.data
    batch.projects[project.path] = {
      path = project.path,
      tsconfig = project.tsconfig,
      priority = project.priority or 0,
      metadata = project.metadata or {},
      retry_count = 0,
      status = "pending"
    }
  end
  
  self._active_batches[batch.id] = batch
  return batch
end

---Process a single batch
---@private
---@param batch Batch
---@param runner_fn function
---@return table<string, any> results
function BatchProcessor:_process_batch(batch, runner_fn)
  batch.status = "processing"
  
  -- Emit batch processing event
  self._events:emit("tsc.batch_processing", {
    batch_id = batch.id,
    projects = vim.tbl_keys(batch.projects)
  })
  
  -- Run the batch through the runner
  local success, results = pcall(runner_fn, batch.projects, {
    timeout = self._config.timeout_per_project,
    progressive = self._config.progressive_results
  })
  
  if not success then
    batch.status = "failed"
    local error_msg = tostring(results)
    
    -- Mark all projects as failed
    for path, _ in pairs(batch.projects) do
      batch.results[path] = {
        success = false,
        error = error_msg,
        duration = 0
      }
    end
    
    -- Retry logic
    if self._config.retry_failed then
      self:_retry_failed_projects(batch)
    end
  else
    batch.status = "completed"
    batch.results = results or {}
    
    -- Handle any failed projects
    if self._config.retry_failed then
      local failed_projects = {}
      for path, result in pairs(batch.results) do
        if not result.success and batch.projects[path].retry_count < self._config.retry_count then
          failed_projects[path] = batch.projects[path]
        end
      end
      
      if vim.tbl_count(failed_projects) > 0 then
        self:_retry_failed_projects({ projects = failed_projects })
      end
    end
  end
  
  batch.end_time = vim.loop.now()
  
  -- Emit batch completed event
  self._events:emit("tsc.batch_completed", {
    batch_id = batch.id,
    status = batch.status,
    duration = batch.end_time - batch.start_time,
    results = batch.results
  })
  
  -- Clean up
  self._active_batches[batch.id] = nil
  
  return batch.results
end

---Retry failed projects
---@private
---@param batch table Batch with failed projects
function BatchProcessor:_retry_failed_projects(batch)
  local retry_items = {}
  
  for path, project in pairs(batch.projects) do
    if project.retry_count < self._config.retry_count then
      project.retry_count = project.retry_count + 1
      project.status = "retry"
      
      -- Re-queue with higher priority
      table.insert(retry_items, {
        path = path,
        tsconfig = project.tsconfig,
        priority = (project.priority or 0) + 10, -- Boost priority for retries
        metadata = vim.tbl_extend("force", project.metadata, {
          retry_count = project.retry_count,
          original_batch = batch.id
        })
      })
    end
  end
  
  if #retry_items > 0 then
    self._queue:push_many(retry_items, function(item)
      return item.priority
    end, function(item)
      return item.metadata
    end)
    
    self._events:emit("tsc.batch_retry", {
      project_count = #retry_items,
      projects = vim.tbl_map(function(item) return item.path end, retry_items)
    })
  end
end

---Update completion counts
---@private
---@param results table<string, any>
function BatchProcessor:_update_counts(results)
  for _, result in pairs(results) do
    if result.success then
      self._completed_count = self._completed_count + 1
    else
      self._failed_count = self._failed_count + 1
    end
  end
end

---Emit progress event
---@private
function BatchProcessor:_emit_progress()
  local processed = self._completed_count + self._failed_count
  local remaining = self._total_count - processed
  local elapsed = vim.loop.now() - self._start_time
  local rate = processed > 0 and (processed / elapsed * 1000) or 0
  local eta = rate > 0 and (remaining / rate) or 0
  
  self._events:emit("tsc.queue_progress", {
    total = self._total_count,
    completed = self._completed_count,
    failed = self._failed_count,
    remaining = remaining,
    percentage = math.floor(processed / self._total_count * 100),
    elapsed_ms = elapsed,
    eta_ms = math.floor(eta * 1000),
    rate_per_second = rate
  })
end

---Emit completion event
---@private
function BatchProcessor:_emit_completion()
  local duration = vim.loop.now() - self._start_time
  
  self._events:emit("tsc.batch_all_completed", {
    total_projects = self._total_count,
    completed_count = self._completed_count,
    failed_count = self._failed_count,
    duration_ms = duration,
    average_time_per_project = duration / self._total_count
  })
end

---Stop processing
function BatchProcessor:stop()
  self._is_running = false
  
  -- Cancel all active batches
  for batch_id, batch in pairs(self._active_batches) do
    batch.status = "cancelled"
    self._events:emit("tsc.batch_cancelled", {
      batch_id = batch_id,
      projects = vim.tbl_keys(batch.projects)
    })
  end
  
  self._active_batches = {}
end

---Get current status
---@return table
function BatchProcessor:get_status()
  local processed = self._completed_count + self._failed_count
  local remaining = self._total_count - processed
  
  return {
    is_running = self._is_running,
    total_projects = self._total_count,
    completed = self._completed_count,
    failed = self._failed_count,
    remaining = remaining,
    queue_size = self._queue:size(),
    active_batches = vim.tbl_count(self._active_batches),
    config = self._config
  }
end

---Get active batch information
---@return table<string, table>
function BatchProcessor:get_active_batches()
  local batches = {}
  
  for batch_id, batch in pairs(self._active_batches) do
    batches[batch_id] = {
      id = batch.id,
      status = batch.status,
      project_count = vim.tbl_count(batch.projects),
      projects = vim.tbl_keys(batch.projects),
      duration = vim.loop.now() - batch.start_time
    }
  end
  
  return batches
end

---Update configuration
---@param config table Partial configuration to update
function BatchProcessor:update_config(config)
  self._config = vim.tbl_extend("force", self._config, config)
  
  -- Update queue strategy if needed
  if config.strategy then
    self._queue:set_strategy(config.strategy)
  end
end

return BatchProcessor
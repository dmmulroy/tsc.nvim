local process_utils = require("tsc.utils.process")
local fs = require("tsc.utils.fs")
local Queue = require("tsc.core.queue")
local BatchProcessor = require("tsc.core.batch")
local async = require("tsc.utils.async")

---@class Runner
---@field private _config table Configuration
---@field private _events Events Event system
---@field private _process_manager ProcessManager Process manager
---@field private _active_runs table<string, table> Active runs
---@field private _batch_mode boolean Whether batch mode is enabled
---@field private _queue tsc.Queue Project queue for batch mode
---@field private _batch_processor tsc.BatchProcessor Batch processor
local Runner = {}

---Create new runner
---@param config table Configuration
---@param events Events Event system
---@return Runner
function Runner.new(config, events)
  local self = {
    _config = config,
    _events = events,
    _process_manager = process_utils.ProcessManager.new(),
    _active_runs = {},
    _batch_mode = config:get("batch.enabled") or false,
    _queue = nil,
    _batch_processor = nil,
  }
  
  -- Initialize batch mode if enabled
  if self._batch_mode then
    local queue_strategy = config:get("batch.strategy") or "size"
    self._queue = Queue.new({ strategy = queue_strategy })
    self._batch_processor = BatchProcessor.new(
      self._queue,
      config:get("batch") or {},
      events
    )
  end
  
  return setmetatable(self, { __index = Runner })
end

---Run TypeScript type-checking on projects
---@param projects table[] List of projects to check
---@param opts? table Runtime options
---@return string Run ID
function Runner:run(projects, opts)
  opts = opts or {}

  -- Generate run ID
  local run_id = tostring(vim.fn.localtime()) .. "_" .. math.random(1000, 9999)

  -- Validate TypeScript binary
  local tsc_bin = self._config:get_tsc_binary()
  if not fs.is_executable(tsc_bin) then
    self._events:emit("tsc.error", {
      run_id = run_id,
      error = "TypeScript binary not found: " .. tsc_bin,
    })
    return run_id
  end

  -- Use batch mode if enabled and not in watch mode
  if self._batch_mode and not opts.watch then
    return self:_run_batch_mode(projects, opts, run_id)
  else
    -- Legacy parallel mode
    return self:_run_parallel_mode(projects, opts, run_id)
  end
end

---Run in batch mode using queue and batch processor
---@private
---@param projects table[] List of projects
---@param opts table Runtime options
---@param run_id string Run ID
---@return string Run ID
function Runner:_run_batch_mode(projects, opts, run_id)
  -- Clear the queue
  self._queue:clear()
  
  -- Add projects to queue with metadata
  local project_items = {}
  for _, project in ipairs(projects) do
    table.insert(project_items, {
      path = project.path,
      tsconfig = project.tsconfig or project.path,
      root = project.root,
      priority = project.priority or 0,
      metadata = {
        name = vim.fn.fnamemodify(project.path, ":t"),
        size = project.size or 1, -- Could be enhanced with actual project size
        tags = project.tags or {}
      }
    })
  end
  
  -- Push all projects to queue
  self._queue:push_many(project_items, function(item)
    return item.priority
  end, function(item)
    return item.metadata
  end)
  
  -- Initialize run tracking
  self._active_runs[run_id] = {
    projects = projects,
    mode = "batch",
    start_time = vim.loop.now(),
    opts = opts,
  }
  
  -- Emit started event
  self._events:emit("tsc.started", {
    run_id = run_id,
    projects = projects,
    total_count = #projects,
    mode = "batch",
    batch_config = self._config:get("batch"),
  })
  
  -- Start batch processing
  self._batch_processor:start(function(batch_projects, batch_opts)
    return self:_run_batch(run_id, batch_projects, batch_opts)
  end):then(function(results)
    self:_handle_batch_completion(run_id, results)
  end):catch(function(err)
    self._events:emit("tsc.error", {
      run_id = run_id,
      error = "Batch processing failed: " .. tostring(err),
    })
  end)
  
  return run_id
end

---Run in legacy parallel mode
---@private
---@param projects table[] List of projects
---@param opts table Runtime options  
---@param run_id string Run ID
---@return string Run ID
function Runner:_run_parallel_mode(projects, opts, run_id)
  -- Initialize run tracking
  self._active_runs[run_id] = {
    projects = projects,
    mode = "parallel",
    processes = {},
    results = {},
    start_time = vim.loop.now(),
    completed_count = 0,
    total_count = #projects,
    opts = opts,
  }

  -- Emit started event
  self._events:emit("tsc.started", {
    run_id = run_id,
    projects = projects,
    total_count = #projects,
    mode = "parallel",
    watch = opts.watch or false,
  })

  -- Start process for each project
  for _, project in ipairs(projects) do
    self:_start_project_process(run_id, project, opts)
  end

  return run_id
end

---Run a batch of projects
---@private
---@param run_id string Run ID
---@param batch_projects table<string, table> Projects keyed by path
---@param batch_opts table Batch options
---@return table<string, table> Results keyed by project path
function Runner:_run_batch(run_id, batch_projects, batch_opts)
  local results = {}
  local completed = 0
  local total = vim.tbl_count(batch_projects)
  
  -- Use async.parallel_limit for concurrency control
  local tasks = {}
  for path, project in pairs(batch_projects) do
    table.insert(tasks, function()
      return self:_run_single_project(run_id, project, batch_opts)
    end)
  end
  
  -- Run with concurrency limit
  local concurrency = self._config:get("batch.concurrency") or 3
  local batch_results = async.parallel_limit(tasks, concurrency)
  
  -- Map results back to project paths
  local i = 1
  for path, _ in pairs(batch_projects) do
    results[path] = batch_results[i] or {
      success = false,
      error = "No result returned"
    }
    i = i + 1
  end
  
  return results
end

---Run a single project and return result
---@private
---@param run_id string Run ID
---@param project table Project info
---@param opts table Options
---@return table Result
function Runner:_run_single_project(run_id, project, opts)
  local result = {
    success = false,
    stdout = {},
    stderr = {},
    errors = {},
    duration = 0,
  }
  
  local start_time = vim.loop.now()
  
  -- Create process for this project
  local tsc_bin = self._config:get_tsc_binary()
  local flags = self._config:get_tsc_flags()
  
  -- Build command arguments
  local args = {}
  table.insert(args, "--project")
  table.insert(args, project.path)
  
  -- Add flags
  if flags and flags ~= "" then
    for flag in flags:gmatch("%S+") do
      table.insert(args, flag)
    end
  end
  
  -- Add color flag
  table.insert(args, "--color")
  table.insert(args, "false")
  
  -- Determine working directory
  local cwd = self._config:get_working_dir() or project.root
  
  -- Run process synchronously for batch
  local process_result = process_utils.run_sync({
    command = tsc_bin,
    args = args,
    cwd = cwd,
    timeout = opts.timeout or self._config:get_timeout(),
  })
  
  result.duration = vim.loop.now() - start_time
  result.stdout = process_result.stdout or {}
  result.stderr = process_result.stderr or {}
  result.exit_code = process_result.exit_code or -1
  result.success = process_result.exit_code == 0
  
  -- Parse output if successful
  if #result.stdout > 0 then
    local parser = require("tsc.core.parser")
    local parsed = parser.parse_output(result.stdout)
    result.errors = parsed.errors or {}
    
    -- Emit progressive result if enabled
    if opts.progressive then
      self._events:emit("tsc.project_completed", {
        run_id = run_id,
        project = project,
        result = result,
        errors = result.errors,
      })
    end
  end
  
  return result
end

---Handle batch completion
---@private
---@param run_id string Run ID
---@param results table All batch results
function Runner:_handle_batch_completion(run_id, results)
  local run = self._active_runs[run_id]
  if not run then
    return
  end
  
  -- Collect all errors
  local all_errors = {}
  local all_results = {}
  
  for project_path, result in pairs(results) do
    if result.errors then
      for _, error in ipairs(result.errors) do
        error.project = project_path
        table.insert(all_errors, error)
      end
    end
    
    table.insert(all_results, {
      project = project_path,
      errors = result.errors or {},
      success = result.success,
      duration = result.duration,
    })
  end
  
  -- Emit completion event
  self._events:emit("tsc.completed", {
    run_id = run_id,
    mode = "batch",
    results = all_results,
    errors = all_errors,
    duration = vim.loop.now() - run.start_time,
    project_count = vim.tbl_count(results),
  })
  
  -- Clean up
  self._active_runs[run_id] = nil
end

---Start process for a single project
---@param run_id string Run ID
---@param project table Project info
---@param opts table Runtime options
function Runner:_start_project_process(run_id, project, opts)
  local tsc_bin = self._config:get_tsc_binary()
  local flags = self._config:get_tsc_flags()

  -- Build command arguments
  local args = {}

  -- Add project flag
  table.insert(args, "--project")
  table.insert(args, project.path)

  -- Add other flags
  if flags and flags ~= "" then
    -- Split flags string and add as separate arguments
    for flag in flags:gmatch("%S+") do
      table.insert(args, flag)
    end
  end

  -- Add watch flag if needed
  if opts.watch then
    table.insert(args, "--watch")
  end

  -- Add color flag to ensure plain output
  table.insert(args, "--color")
  table.insert(args, "false")

  -- Determine working directory
  local cwd = self._config:get_working_dir() or project.root

  -- Create process options
  local process_opts = {
    command = tsc_bin,
    args = args,
    cwd = cwd,
    timeout = self._config:get_timeout(),
    on_stdout = function(data)
      self:_handle_stdout(run_id, project, data)
    end,
    on_stderr = function(data)
      self:_handle_stderr(run_id, project, data)
    end,
    on_exit = function(code)
      self:_handle_exit(run_id, project, code)
    end,
  }

  -- Start process
  local process = self._process_manager:start(process_opts)

  if process then
    -- Track process
    self._active_runs[run_id].processes[project.path] = process

    -- Emit process started event
    self._events:emit("tsc.process_started", {
      run_id = run_id,
      project = project,
      process_id = process.id,
    })
  else
    -- Handle process start failure
    self._events:emit("tsc.process_error", {
      run_id = run_id,
      project = project,
      error = "Failed to start process",
    })

    -- Mark as completed with error
    self:_handle_project_completion(run_id, project, {
      success = false,
      error = "Failed to start process",
    })
  end
end

---Handle stdout from process
---@param run_id string Run ID
---@param project table Project info
---@param data string[] Stdout lines
function Runner:_handle_stdout(run_id, project, data)
  if not self._active_runs[run_id] then
    return
  end

  -- Initialize project results if not exists
  if not self._active_runs[run_id].results[project.path] then
    self._active_runs[run_id].results[project.path] = {
      stdout = {},
      stderr = {},
      parsed = nil,
    }
  end

  -- Store stdout data
  local result = self._active_runs[run_id].results[project.path]
  for _, line in ipairs(data) do
    if line ~= "" then
      table.insert(result.stdout, line)
    end
  end

  -- Emit output received event
  self._events:emit("tsc.output_received", {
    run_id = run_id,
    project = project,
    type = "stdout",
    data = data,
  })
end

---Handle stderr from process
---@param run_id string Run ID
---@param project table Project info
---@param data string[] Stderr lines
function Runner:_handle_stderr(run_id, project, data)
  if not self._active_runs[run_id] then
    return
  end

  -- Initialize project results if not exists
  if not self._active_runs[run_id].results[project.path] then
    self._active_runs[run_id].results[project.path] = {
      stdout = {},
      stderr = {},
      parsed = nil,
    }
  end

  -- Store stderr data
  local result = self._active_runs[run_id].results[project.path]
  for _, line in ipairs(data) do
    if line ~= "" then
      table.insert(result.stderr, line)
    end
  end

  -- Emit output received event
  self._events:emit("tsc.output_received", {
    run_id = run_id,
    project = project,
    type = "stderr",
    data = data,
  })
end

---Handle process exit
---@param run_id string Run ID
---@param project table Project info
---@param code number Exit code
function Runner:_handle_exit(run_id, project, code)
  if not self._active_runs[run_id] then
    return
  end

  -- Emit process completed event
  self._events:emit("tsc.process_completed", {
    run_id = run_id,
    project = project,
    exit_code = code,
  })

  -- Mark project as completed
  self:_handle_project_completion(run_id, project, {
    success = code == 0,
    exit_code = code,
  })
end

---Handle project completion
---@param run_id string Run ID
---@param project table Project info
---@param completion table Completion info
function Runner:_handle_project_completion(run_id, project, completion)
  local run = self._active_runs[run_id]
  if not run then
    return
  end

  -- Update completion count
  run.completed_count = run.completed_count + 1

  -- Parse output if successful
  if completion.success and run.results[project.path] then
    local parser = require("tsc.core.parser")
    local parsed = parser.parse_output(run.results[project.path].stdout)
    run.results[project.path].parsed = parsed

    -- Emit output parsed event
    self._events:emit("tsc.output_parsed", {
      run_id = run_id,
      project = project,
      parsed = parsed,
    })
  end

  -- Check if all projects are completed
  if run.completed_count >= run.total_count then
    self:_handle_run_completion(run_id)
  end
end

---Handle run completion
---@param run_id string Run ID
function Runner:_handle_run_completion(run_id)
  local run = self._active_runs[run_id]
  if not run then
    return
  end

  -- Collect all results
  local all_results = {}
  local all_errors = {}

  for project_path, result in pairs(run.results) do
    if result.parsed then
      -- Add project info to each error
      for _, error in ipairs(result.parsed.errors) do
        error.project = project_path
        table.insert(all_errors, error)
      end

      table.insert(all_results, {
        project = project_path,
        errors = result.parsed.errors,
        files = result.parsed.files,
      })
    end
  end

  -- Emit completion event
  self._events:emit("tsc.completed", {
    run_id = run_id,
    results = all_results,
    errors = all_errors,
    duration = vim.loop.now() - run.start_time,
    project_count = run.total_count,
  })

  -- Clean up if not watch mode
  if not run.opts.watch then
    self._active_runs[run_id] = nil
  end
end

---Stop specific run
---@param run_id string Run ID
---@return boolean success
function Runner:stop_run(run_id)
  local run = self._active_runs[run_id]
  if not run then
    return false
  end

  -- Handle batch mode
  if run.mode == "batch" and self._batch_processor then
    self._batch_processor:stop()
    self._active_runs[run_id] = nil
    
    self._events:emit("tsc.stopped", {
      run_id = run_id,
      mode = "batch",
    })
    
    return true
  end
  
  -- Handle parallel mode
  if run.processes then
    -- Stop all processes for this run
    local stopped = 0
    for _, process in pairs(run.processes) do
      if process:stop() then
        stopped = stopped + 1
      end
    end

    -- Clean up run
    self._active_runs[run_id] = nil

    -- Emit stopped event
    self._events:emit("tsc.stopped", {
      run_id = run_id,
      mode = "parallel",
      stopped_processes = stopped,
    })

    return stopped > 0
  end
  
  return false
end

---Stop all runs
---@return number Number of runs stopped
function Runner:stop_all()
  local stopped_runs = 0

  for run_id, _ in pairs(self._active_runs) do
    if self:stop_run(run_id) then
      stopped_runs = stopped_runs + 1
    end
  end

  return stopped_runs
end

---Get run status
---@param run_id? string Run ID (optional)
---@return table Run status
function Runner:get_status(run_id)
  if run_id then
    local run = self._active_runs[run_id]
    if run then
      local status = {
        run_id = run_id,
        mode = run.mode,
        duration = vim.loop.now() - run.start_time,
        watch_mode = run.opts.watch or false,
      }
      
      -- Add mode-specific status
      if run.mode == "batch" and self._batch_processor then
        local batch_status = self._batch_processor:get_status()
        status.total_projects = batch_status.total_projects
        status.completed_projects = batch_status.completed
        status.failed_projects = batch_status.failed
        status.is_running = batch_status.is_running
        status.queue_size = batch_status.queue_size
        status.active_batches = batch_status.active_batches
      else
        status.total_projects = run.total_count
        status.completed_projects = run.completed_count
        status.is_running = run.completed_count < run.total_count
      end
      
      return status
    end
    return nil
  else
    -- Return status for all runs
    local status = {}
    for id, run in pairs(self._active_runs) do
      status[id] = self:get_status(id)
    end
    return status
  end
end

---Get runner statistics
---@return table Statistics
function Runner:get_stats()
  local active_runs = vim.tbl_count(self._active_runs)
  local total_processes = 0
  local running_processes = 0
  local batch_runs = 0
  local parallel_runs = 0

  for _, run in pairs(self._active_runs) do
    if run.mode == "batch" then
      batch_runs = batch_runs + 1
    else
      parallel_runs = parallel_runs + 1
      if run.processes then
        total_processes = total_processes + vim.tbl_count(run.processes)
        for _, process in pairs(run.processes) do
          if process:is_running() then
            running_processes = running_processes + 1
          end
        end
      end
    end
  end

  local stats = {
    active_runs = active_runs,
    batch_runs = batch_runs,
    parallel_runs = parallel_runs,
    total_processes = total_processes,
    running_processes = running_processes,
    process_manager_stats = self._process_manager:get_stats(),
  }
  
  -- Add batch processor stats if available
  if self._batch_processor then
    stats.batch_processor = self._batch_processor:get_status()
  end
  
  -- Add queue stats if available
  if self._queue then
    stats.queue = self._queue:get_stats()
  end
  
  return stats
end

---Update batch configuration
---@param config table New batch configuration
function Runner:update_batch_config(config)
  if self._batch_processor then
    self._batch_processor:update_config(config)
  end
  
  -- Update queue strategy if needed
  if config.strategy and self._queue then
    self._queue:set_strategy(config.strategy)
  end
end

---Get queue information (for debugging/monitoring)
---@return table|nil Queue info
function Runner:get_queue_info()
  if not self._queue then
    return nil
  end
  
  return {
    size = self._queue:size(),
    is_empty = self._queue:is_empty(),
    stats = self._queue:get_stats(),
    items = self._queue:get_all(),
  }
end

return Runner

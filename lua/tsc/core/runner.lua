local process_utils = require("tsc.utils.process")
local fs = require("tsc.utils.fs")

---@class Runner
---@field private _config table Configuration
---@field private _events Events Event system
---@field private _process_manager ProcessManager Process manager
---@field private _active_runs table<string, table> Active runs
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
  }
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

  -- Initialize run tracking
  self._active_runs[run_id] = {
    projects = projects,
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
    watch = opts.watch or false,
  })

  -- Start process for each project
  for _, project in ipairs(projects) do
    self:_start_project_process(run_id, project, opts)
  end

  return run_id
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
    stopped_processes = stopped,
  })

  return stopped > 0
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
      return {
        run_id = run_id,
        total_projects = run.total_count,
        completed_projects = run.completed_count,
        is_running = run.completed_count < run.total_count,
        duration = vim.loop.now() - run.start_time,
        watch_mode = run.opts.watch or false,
      }
    end
    return nil
  else
    -- Return status for all runs
    local status = {}
    for id, run in pairs(self._active_runs) do
      status[id] = {
        total_projects = run.total_count,
        completed_projects = run.completed_count,
        is_running = run.completed_count < run.total_count,
        duration = vim.loop.now() - run.start_time,
        watch_mode = run.opts.watch or false,
      }
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

  for _, run in pairs(self._active_runs) do
    total_processes = total_processes + vim.tbl_count(run.processes)
    for _, process in pairs(run.processes) do
      if process:is_running() then
        running_processes = running_processes + 1
      end
    end
  end

  return {
    active_runs = active_runs,
    total_processes = total_processes,
    running_processes = running_processes,
    process_manager_stats = self._process_manager:get_stats(),
  }
end

return Runner

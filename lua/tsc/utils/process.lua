---@class ProcessUtils
local M = {}

---@class ProcessOptions
---@field command string Command to execute
---@field args string[] Command arguments
---@field cwd? string Working directory
---@field timeout? number Timeout in milliseconds
---@field on_stdout? function Callback for stdout
---@field on_stderr? function Callback for stderr
---@field on_exit? function Callback for exit

---@class Process
---@field id number Process ID
---@field command string Command
---@field args string[] Arguments
---@field cwd string Working directory
---@field timeout number Timeout
---@field job_id number Neovim job ID
---@field status string Process status
---@field stdout string[] Stdout lines
---@field stderr string[] Stderr lines
---@field exit_code number|nil Exit code
---@field start_time number Start timestamp
---@field end_time number|nil End timestamp
local Process = {}

---Create new process
---@param opts ProcessOptions Process options
---@return Process
function Process.new(opts)
  local self = {
    id = vim.fn.localtime() .. math.random(1000, 9999),
    command = opts.command,
    args = opts.args or {},
    cwd = opts.cwd or vim.fn.getcwd(),
    timeout = opts.timeout or 30000,
    job_id = nil,
    status = 'pending',
    stdout = {},
    stderr = {},
    exit_code = nil,
    start_time = vim.loop.now(),
    end_time = nil,
    _on_stdout = opts.on_stdout,
    _on_stderr = opts.on_stderr,
    _on_exit = opts.on_exit,
  }
  
  return setmetatable(self, { __index = Process })
end

---Start the process
---@return boolean success
function Process:start()
  if self.status ~= 'pending' then
    return false
  end
  
  self.status = 'starting'
  self.start_time = vim.loop.now()
  
  -- Build command
  local cmd = self.command
  if #self.args > 0 then
    cmd = cmd .. ' ' .. table.concat(self.args, ' ')
  end
  
  -- Set up job options
  local job_opts = {
    cwd = self.cwd,
    on_stdout = function(_, data)
      self:_handle_stdout(data)
    end,
    on_stderr = function(_, data)
      self:_handle_stderr(data)
    end,
    on_exit = function(_, code)
      self:_handle_exit(code)
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  }
  
  -- Start job
  self.job_id = vim.fn.jobstart(cmd, job_opts)
  
  if self.job_id <= 0 then
    self.status = 'failed'
    self.end_time = vim.loop.now()
    return false
  end
  
  self.status = 'running'
  
  -- Set up timeout
  if self.timeout > 0 then
    vim.defer_fn(function()
      if self.status == 'running' then
        self:stop()
      end
    end, self.timeout)
  end
  
  return true
end

---Stop the process
---@return boolean success
function Process:stop()
  if self.status ~= 'running' then
    return false
  end
  
  if self.job_id and self.job_id > 0 then
    vim.fn.jobstop(self.job_id)
    self.status = 'stopped'
    self.end_time = vim.loop.now()
    return true
  end
  
  return false
end

---Check if process is running
---@return boolean
function Process:is_running()
  return self.status == 'running'
end

---Get process duration
---@return number Duration in milliseconds
function Process:get_duration()
  local end_time = self.end_time or vim.loop.now()
  return end_time - self.start_time
end

---Get process info
---@return table Process information
function Process:get_info()
  return {
    id = self.id,
    command = self.command,
    args = self.args,
    cwd = self.cwd,
    status = self.status,
    job_id = self.job_id,
    exit_code = self.exit_code,
    duration = self:get_duration(),
    stdout_lines = #self.stdout,
    stderr_lines = #self.stderr,
  }
end

---Handle stdout data
---@param data string[] Stdout lines
function Process:_handle_stdout(data)
  if data then
    for _, line in ipairs(data) do
      if line ~= '' then
        table.insert(self.stdout, line)
      end
    end
    
    if self._on_stdout then
      self._on_stdout(data)
    end
  end
end

---Handle stderr data
---@param data string[] Stderr lines
function Process:_handle_stderr(data)
  if data then
    for _, line in ipairs(data) do
      if line ~= '' then
        table.insert(self.stderr, line)
      end
    end
    
    if self._on_stderr then
      self._on_stderr(data)
    end
  end
end

---Handle process exit
---@param code number Exit code
function Process:_handle_exit(code)
  self.exit_code = code
  self.status = code == 0 and 'completed' or 'failed'
  self.end_time = vim.loop.now()
  
  if self._on_exit then
    self._on_exit(code)
  end
end

---Process manager for handling multiple processes
---@class ProcessManager
---@field private _processes table<string, Process>
local ProcessManager = {}

---Create new process manager
---@return ProcessManager
function ProcessManager.new()
  local self = {
    _processes = {},
  }
  return setmetatable(self, { __index = ProcessManager })
end

---Start a new process
---@param opts ProcessOptions Process options
---@return Process|nil
function ProcessManager:start(opts)
  local process = Process.new(opts)
  
  if process:start() then
    self._processes[process.id] = process
    return process
  end
  
  return nil
end

---Stop a process
---@param process_id string Process ID
---@return boolean success
function ProcessManager:stop(process_id)
  local process = self._processes[process_id]
  if process then
    local success = process:stop()
    if success then
      self._processes[process_id] = nil
    end
    return success
  end
  return false
end

---Stop all processes
---@return number Number of processes stopped
function ProcessManager:stop_all()
  local stopped = 0
  for process_id, process in pairs(self._processes) do
    if process:stop() then
      stopped = stopped + 1
    end
  end
  self._processes = {}
  return stopped
end

---Get process by ID
---@param process_id string Process ID
---@return Process|nil
function ProcessManager:get(process_id)
  return self._processes[process_id]
end

---Get all processes
---@return table<string, Process>
function ProcessManager:get_all()
  return vim.deepcopy(self._processes)
end

---Get running processes
---@return table<string, Process>
function ProcessManager:get_running()
  local running = {}
  for id, process in pairs(self._processes) do
    if process:is_running() then
      running[id] = process
    end
  end
  return running
end

---Clean up completed processes
---@return number Number of processes cleaned up
function ProcessManager:cleanup()
  local cleaned = 0
  for process_id, process in pairs(self._processes) do
    if not process:is_running() then
      self._processes[process_id] = nil
      cleaned = cleaned + 1
    end
  end
  return cleaned
end

---Get process manager statistics
---@return table Statistics
function ProcessManager:get_stats()
  local total = 0
  local running = 0
  local completed = 0
  local failed = 0
  
  for _, process in pairs(self._processes) do
    total = total + 1
    if process.status == 'running' then
      running = running + 1
    elseif process.status == 'completed' then
      completed = completed + 1
    elseif process.status == 'failed' then
      failed = failed + 1
    end
  end
  
  return {
    total = total,
    running = running,
    completed = completed,
    failed = failed,
  }
end

-- Export both classes
M.Process = Process
M.ProcessManager = ProcessManager

return M
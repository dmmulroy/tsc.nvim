---@class tsc.PerformanceMonitor
---@field private _metrics table<string, table> Collected metrics
---@field private _events table Event system
---@field private _start_time number Monitor start time
---@field private _active boolean Whether monitoring is active
local PerformanceMonitor = {}
PerformanceMonitor.__index = PerformanceMonitor

---@class MetricEntry
---@field timestamp number When the metric was recorded
---@field value number The metric value
---@field type string The metric type (gauge, counter, timing)
---@field tags table<string, string> Additional tags

---Create a new performance monitor
---@param events table Event system
---@return tsc.PerformanceMonitor
function PerformanceMonitor.new(events)
  local self = setmetatable({}, PerformanceMonitor)
  
  self._metrics = {}
  self._events = events
  self._start_time = vim.loop.now()
  self._active = true
  
  -- Set up event listeners for automatic metrics collection
  self:_setup_event_listeners()
  
  return self
end

---Set up event listeners for automatic metrics collection
---@private
function PerformanceMonitor:_setup_event_listeners()
  if not self._events then
    return
  end
  
  -- Track batch processing metrics
  self._events:on("tsc.batch_started", function(data)
    self:record_gauge("batch.total_projects", data.total_projects)
    self:record_gauge("batch.batch_size", data.batch_size)
    self:record_gauge("batch.concurrency", data.concurrency)
    self:record_counter("batch.starts", 1)
  end)
  
  self._events:on("tsc.batch_completed", function(data)
    self:record_timing("batch.duration", data.duration_ms)
    self:record_counter("batch.completions", 1)
    
    if data.status == "failed" then
      self:record_counter("batch.failures", 1)
    end
  end)
  
  self._events:on("tsc.queue_progress", function(data)
    self:record_gauge("queue.total", data.total)
    self:record_gauge("queue.completed", data.completed)
    self:record_gauge("queue.failed", data.failed)
    self:record_gauge("queue.remaining", data.remaining)
    self:record_gauge("queue.percentage", data.percentage)
    self:record_gauge("queue.rate_per_second", data.rate_per_second)
  end)
  
  self._events:on("tsc.project_completed", function(data)
    self:record_timing("project.duration", data.result.duration)
    self:record_counter("project.completions", 1)
    
    if data.result.success then
      self:record_counter("project.successes", 1)
    else
      self:record_counter("project.failures", 1)
    end
    
    if data.result.errors then
      self:record_gauge("project.error_count", #data.result.errors)
    end
  end)
  
  -- Track discovery metrics
  self._events:on("tsc.projects_discovered", function(data)
    self:record_gauge("discovery.project_count", data.count)
    self:record_counter("discovery.runs", 1)
  end)
  
  self._events:on("tsc.discovery_progress", function(data)
    self:record_gauge("discovery.discovered_count", data.discovered)
  end)
end

---Record a gauge metric (current value)
---@param name string Metric name
---@param value number Metric value
---@param tags? table<string, string> Additional tags
function PerformanceMonitor:record_gauge(name, value, tags)
  if not self._active then
    return
  end
  
  if not self._metrics[name] then
    self._metrics[name] = {}
  end
  
  table.insert(self._metrics[name], {
    timestamp = vim.loop.now(),
    value = value,
    type = "gauge",
    tags = tags or {}
  })
end

---Record a counter metric (incremental value)
---@param name string Metric name
---@param increment number Increment value
---@param tags? table<string, string> Additional tags
function PerformanceMonitor:record_counter(name, increment, tags)
  if not self._active then
    return
  end
  
  if not self._metrics[name] then
    self._metrics[name] = {}
  end
  
  -- Get last value for counter
  local last_value = 0
  if #self._metrics[name] > 0 then
    last_value = self._metrics[name][#self._metrics[name]].value
  end
  
  table.insert(self._metrics[name], {
    timestamp = vim.loop.now(),
    value = last_value + increment,
    type = "counter",
    tags = tags or {}
  })
end

---Record a timing metric (duration)
---@param name string Metric name
---@param duration number Duration in milliseconds
---@param tags? table<string, string> Additional tags
function PerformanceMonitor:record_timing(name, duration, tags)
  if not self._active then
    return
  end
  
  if not self._metrics[name] then
    self._metrics[name] = {}
  end
  
  table.insert(self._metrics[name], {
    timestamp = vim.loop.now(),
    value = duration,
    type = "timing",
    tags = tags or {}
  })
end

---Get system resource usage
---@return table Resource usage info
function PerformanceMonitor:get_system_resources()
  local resources = {
    timestamp = vim.loop.now(),
    memory = {},
    cpu = {},
    processes = {}
  }
  
  -- Get memory usage (basic implementation)
  local memory_info = vim.loop.resident_set_memory()
  if memory_info then
    resources.memory.rss = memory_info
  end
  
  -- Get process count (approximate)
  local process_count = 0
  local handle = io.popen("ps aux | wc -l")
  if handle then
    local output = handle:read("*a")
    handle:close()
    process_count = tonumber(output:match("%d+")) or 0
  end
  resources.processes.total = process_count
  
  return resources
end

---Get current metric value
---@param name string Metric name
---@return number|nil Current value
function PerformanceMonitor:get_current_value(name)
  if not self._metrics[name] or #self._metrics[name] == 0 then
    return nil
  end
  
  return self._metrics[name][#self._metrics[name]].value
end

---Get metric statistics
---@param name string Metric name
---@return table|nil Statistics
function PerformanceMonitor:get_metric_stats(name)
  if not self._metrics[name] or #self._metrics[name] == 0 then
    return nil
  end
  
  local entries = self._metrics[name]
  local values = {}
  
  for _, entry in ipairs(entries) do
    table.insert(values, entry.value)
  end
  
  table.sort(values)
  
  local count = #values
  local sum = 0
  for _, value in ipairs(values) do
    sum = sum + value
  end
  
  return {
    count = count,
    sum = sum,
    average = sum / count,
    min = values[1],
    max = values[count],
    median = values[math.ceil(count / 2)],
    p95 = values[math.ceil(count * 0.95)],
    p99 = values[math.ceil(count * 0.99)]
  }
end

---Get all metrics summary
---@return table Metrics summary
function PerformanceMonitor:get_summary()
  local summary = {
    uptime = vim.loop.now() - self._start_time,
    active = self._active,
    metrics = {},
    system = self:get_system_resources()
  }
  
  for name, _ in pairs(self._metrics) do
    local stats = self:get_metric_stats(name)
    if stats then
      summary.metrics[name] = {
        current = self:get_current_value(name),
        stats = stats
      }
    end
  end
  
  return summary
end

---Get performance insights
---@return table Performance insights
function PerformanceMonitor:get_insights()
  local insights = {
    performance_issues = {},
    recommendations = {},
    alerts = {}
  }
  
  -- Check for performance issues
  local avg_batch_duration = self:get_metric_stats("batch.duration")
  if avg_batch_duration and avg_batch_duration.average > 60000 then -- 1 minute
    table.insert(insights.performance_issues, {
      type = "slow_batches",
      message = "Batch processing is slower than expected",
      average_duration = avg_batch_duration.average,
      recommendation = "Consider reducing batch size or increasing concurrency"
    })
  end
  
  local failure_rate = self:get_current_value("project.failures") or 0
  local success_rate = self:get_current_value("project.successes") or 0
  local total_projects = failure_rate + success_rate
  
  if total_projects > 0 and (failure_rate / total_projects) > 0.1 then -- 10% failure rate
    table.insert(insights.performance_issues, {
      type = "high_failure_rate",
      message = "High project failure rate detected",
      failure_rate = failure_rate / total_projects,
      recommendation = "Check project configurations and TypeScript setup"
    })
  end
  
  -- Check queue efficiency
  local queue_size = self:get_current_value("queue.remaining")
  local processing_rate = self:get_current_value("queue.rate_per_second")
  
  if queue_size and processing_rate and queue_size > 0 and processing_rate < 0.5 then
    table.insert(insights.performance_issues, {
      type = "slow_processing",
      message = "Queue processing is slow",
      rate = processing_rate,
      recommendation = "Consider increasing concurrency or batch size"
    })
  end
  
  -- Generate recommendations
  local total_projects_discovered = self:get_current_value("discovery.project_count") or 0
  if total_projects_discovered > 50 then
    table.insert(insights.recommendations, {
      type = "large_monorepo",
      message = "Large monorepo detected",
      recommendation = "Consider using more aggressive filtering or smaller batch sizes"
    })
  end
  
  return insights
end

---Reset all metrics
function PerformanceMonitor:reset()
  self._metrics = {}
  self._start_time = vim.loop.now()
end

---Stop monitoring
function PerformanceMonitor:stop()
  self._active = false
end

---Start monitoring
function PerformanceMonitor:start()
  self._active = true
  self._start_time = vim.loop.now()
end

---Export metrics in a specific format
---@param format string Export format ('json', 'table', 'prometheus')
---@return string|table Exported metrics
function PerformanceMonitor:export(format)
  format = format or "table"
  
  local data = self:get_summary()
  
  if format == "json" then
    return vim.fn.json_encode(data)
  elseif format == "prometheus" then
    local lines = {}
    
    for name, metric in pairs(data.metrics) do
      local prom_name = name:gsub("%.", "_")
      table.insert(lines, string.format("# TYPE %s gauge", prom_name))
      table.insert(lines, string.format("%s %s", prom_name, metric.current or 0))
    end
    
    return table.concat(lines, "\n")
  else
    return data
  end
end

return PerformanceMonitor
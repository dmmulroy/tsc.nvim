local PerformanceMonitor = require("tsc.core.monitor")

describe("PerformanceMonitor", function()
  local monitor, mock_events
  
  before_each(function()
    mock_events = {
      _listeners = {},
      emit = function(self, event, data)
        if self._listeners[event] then
          for _, callback in ipairs(self._listeners[event]) do
            callback(data)
          end
        end
      end,
      on = function(self, event, callback)
        if not self._listeners[event] then
          self._listeners[event] = {}
        end
        table.insert(self._listeners[event], callback)
      end
    }
    
    monitor = PerformanceMonitor.new(mock_events)
  end)
  
  describe("initialization", function()
    it("should initialize with events", function()
      assert.is_table(monitor)
      assert.is_true(monitor._active)
      assert.is_number(monitor._start_time)
    end)
  end)
  
  describe("metric recording", function()
    it("should record gauge metrics", function()
      monitor:record_gauge("test.gauge", 42)
      
      local value = monitor:get_current_value("test.gauge")
      assert.equals(42, value)
    end)
    
    it("should record counter metrics", function()
      monitor:record_counter("test.counter", 5)
      monitor:record_counter("test.counter", 3)
      
      local value = monitor:get_current_value("test.counter")
      assert.equals(8, value) -- 5 + 3
    end)
    
    it("should record timing metrics", function()
      monitor:record_timing("test.timing", 1500)
      
      local value = monitor:get_current_value("test.timing")
      assert.equals(1500, value)
    end)
  end)
  
  describe("metric statistics", function()
    it("should calculate stats for metrics", function()
      monitor:record_timing("test.timing", 100)
      monitor:record_timing("test.timing", 200)
      monitor:record_timing("test.timing", 300)
      
      local stats = monitor:get_metric_stats("test.timing")
      assert.is_table(stats)
      assert.equals(3, stats.count)
      assert.equals(600, stats.sum)
      assert.equals(200, stats.average)
      assert.equals(100, stats.min)
      assert.equals(300, stats.max)
      assert.equals(200, stats.median)
    end)
    
    it("should handle empty metrics", function()
      local stats = monitor:get_metric_stats("nonexistent")
      assert.is_nil(stats)
    end)
  end)
  
  describe("event-based metrics", function()
    it("should record metrics from batch events", function()
      mock_events:emit("tsc.batch_started", {
        total_projects = 10,
        batch_size = 5,
        concurrency = 2
      })
      
      assert.equals(10, monitor:get_current_value("batch.total_projects"))
      assert.equals(5, monitor:get_current_value("batch.batch_size"))
      assert.equals(2, monitor:get_current_value("batch.concurrency"))
      assert.equals(1, monitor:get_current_value("batch.starts"))
    end)
    
    it("should record metrics from queue progress", function()
      mock_events:emit("tsc.queue_progress", {
        total = 100,
        completed = 25,
        failed = 5,
        remaining = 70,
        percentage = 25,
        rate_per_second = 2.5
      })
      
      assert.equals(100, monitor:get_current_value("queue.total"))
      assert.equals(25, monitor:get_current_value("queue.completed"))
      assert.equals(5, monitor:get_current_value("queue.failed"))
      assert.equals(70, monitor:get_current_value("queue.remaining"))
    end)
    
    it("should record metrics from project completion", function()
      mock_events:emit("tsc.project_completed", {
        result = {
          duration = 2000,
          success = true,
          errors = { "error1", "error2" }
        }
      })
      
      assert.equals(2000, monitor:get_current_value("project.duration"))
      assert.equals(1, monitor:get_current_value("project.completions"))
      assert.equals(1, monitor:get_current_value("project.successes"))
      assert.equals(2, monitor:get_current_value("project.error_count"))
    end)
  end)
  
  describe("summary", function()
    it("should provide metrics summary", function()
      monitor:record_gauge("test.gauge", 42)
      monitor:record_counter("test.counter", 5)
      
      local summary = monitor:get_summary()
      assert.is_table(summary)
      assert.is_number(summary.uptime)
      assert.is_true(summary.active)
      assert.is_table(summary.metrics)
      assert.is_table(summary.system)
      
      assert.equals(42, summary.metrics["test.gauge"].current)
      assert.equals(5, summary.metrics["test.counter"].current)
    end)
  end)
  
  describe("performance insights", function()
    it("should detect slow batch processing", function()
      -- Simulate slow batch
      mock_events:emit("tsc.batch_completed", {
        duration_ms = 120000, -- 2 minutes
        status = "completed"
      })
      
      local insights = monitor:get_insights()
      assert.is_table(insights)
      assert.is_table(insights.performance_issues)
      
      -- Should detect slow batches
      local slow_batch_issue = nil
      for _, issue in ipairs(insights.performance_issues) do
        if issue.type == "slow_batches" then
          slow_batch_issue = issue
          break
        end
      end
      
      assert.is_table(slow_batch_issue)
      assert.equals(120000, slow_batch_issue.average_duration)
    end)
    
    it("should detect high failure rates", function()
      -- Simulate failures
      monitor:record_counter("project.failures", 10)
      monitor:record_counter("project.successes", 20)
      
      local insights = monitor:get_insights()
      
      -- Should detect high failure rate (33%)
      local failure_issue = nil
      for _, issue in ipairs(insights.performance_issues) do
        if issue.type == "high_failure_rate" then
          failure_issue = issue
          break
        end
      end
      
      assert.is_table(failure_issue)
      assert.is_true(failure_issue.failure_rate > 0.1)
    end)
  end)
  
  describe("export", function()
    it("should export metrics as table", function()
      monitor:record_gauge("test.metric", 42)
      
      local exported = monitor:export("table")
      assert.is_table(exported)
      assert.is_table(exported.metrics)
      assert.equals(42, exported.metrics["test.metric"].current)
    end)
    
    it("should export metrics as JSON", function()
      monitor:record_gauge("test.metric", 42)
      
      local exported = monitor:export("json")
      assert.is_string(exported)
      assert.is_true(exported:find("test.metric"))
    end)
    
    it("should export metrics in Prometheus format", function()
      monitor:record_gauge("test.metric", 42)
      
      local exported = monitor:export("prometheus")
      assert.is_string(exported)
      assert.is_true(exported:find("# TYPE test_metric gauge"))
      assert.is_true(exported:find("test_metric 42"))
    end)
  end)
  
  describe("lifecycle", function()
    it("should stop and start monitoring", function()
      monitor:stop()
      assert.is_false(monitor._active)
      
      monitor:record_gauge("test.metric", 42)
      local value = monitor:get_current_value("test.metric")
      assert.is_nil(value) -- Should not record when stopped
      
      monitor:start()
      assert.is_true(monitor._active)
      
      monitor:record_gauge("test.metric", 42)
      local value2 = monitor:get_current_value("test.metric")
      assert.equals(42, value2) -- Should record when started
    end)
    
    it("should reset metrics", function()
      monitor:record_gauge("test.metric", 42)
      
      monitor:reset()
      
      local value = monitor:get_current_value("test.metric")
      assert.is_nil(value)
    end)
  end)
end)
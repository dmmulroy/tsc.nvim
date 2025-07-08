local Queue = require("tsc.core.queue")
local BatchProcessor = require("tsc.core.batch")

describe("BatchProcessor", function()
  local queue, events, processor
  
  before_each(function()
    queue = Queue.new({ strategy = "fifo" })
    events = {
      _listeners = {},
      emit = function(self, event, data)
        -- Mock event emission
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
    
    processor = BatchProcessor.new(queue, {
      size = 2,
      concurrency = 1,
      strategy = "fifo",
      progressive_results = true,
      retry_failed = false
    }, events)
  end)
  
  describe("initialization", function()
    it("should initialize with correct config", function()
      local status = processor:get_status()
      assert.is_false(status.is_running)
      assert.equals(0, status.total_projects)
      assert.equals(2, status.config.size)
      assert.equals(1, status.config.concurrency)
    end)
  end)
  
  describe("batch processing", function()
    it("should process projects in batches", function()
      -- Add projects to queue
      local projects = {
        { path = "/project1", tsconfig = "/project1/tsconfig.json" },
        { path = "/project2", tsconfig = "/project2/tsconfig.json" },
        { path = "/project3", tsconfig = "/project3/tsconfig.json" }
      }
      
      for _, project in ipairs(projects) do
        queue:push(project)
      end
      
      -- Mock runner function
      local processed_batches = {}
      local runner_fn = function(batch_projects, opts)
        table.insert(processed_batches, batch_projects)
        
        local results = {}
        for path, project in pairs(batch_projects) do
          results[path] = {
            success = true,
            errors = {},
            duration = 100
          }
        end
        return results
      end
      
      -- Track events
      local events_received = {}
      events:on("tsc.batch_started", function(data)
        table.insert(events_received, { event = "started", data = data })
      end)
      
      events:on("tsc.batch_completed", function(data)
        table.insert(events_received, { event = "completed", data = data })
      end)
      
      -- Process synchronously for test
      local results = processor:start(runner_fn)
      
      -- Verify batches were processed
      assert.equals(2, #processed_batches) -- 3 projects, batch size 2 = 2 batches
      assert.equals(2, vim.tbl_count(processed_batches[1])) -- First batch: 2 projects
      assert.equals(1, vim.tbl_count(processed_batches[2])) -- Second batch: 1 project
      
      -- Verify events were emitted
      assert.is_true(#events_received > 0)
      
      -- Verify results
      assert.is_table(results)
    end)
  end)
  
  describe("configuration updates", function()
    it("should update configuration", function()
      processor:update_config({
        size = 3,
        concurrency = 2
      })
      
      local status = processor:get_status()
      assert.equals(3, status.config.size)
      assert.equals(2, status.config.concurrency)
    end)
  end)
  
  describe("status tracking", function()
    it("should track processing status", function()
      -- Add some projects
      queue:push({ path = "/project1" })
      queue:push({ path = "/project2" })
      
      local status = processor:get_status()
      assert.equals(2, status.total_projects)
      assert.equals(0, status.completed)
      assert.equals(0, status.failed)
      assert.equals(2, status.remaining)
    end)
  end)
  
  describe("error handling", function()
    it("should handle runner function errors", function()
      queue:push({ path = "/project1" })
      
      local runner_fn = function(batch_projects, opts)
        error("Simulated error")
      end
      
      local error_events = {}
      events:on("tsc.batch_completed", function(data)
        if data.status == "failed" then
          table.insert(error_events, data)
        end
      end)
      
      -- This should not throw
      local success, result = pcall(function()
        return processor:start(runner_fn)
      end)
      
      -- Should handle error gracefully
      assert.is_true(success or #error_events > 0)
    end)
  end)
  
  describe("active batch tracking", function()
    it("should track active batches", function()
      queue:push({ path = "/project1" })
      queue:push({ path = "/project2" })
      
      local active_batches = processor:get_active_batches()
      assert.is_table(active_batches)
      
      -- Initially no active batches
      assert.equals(0, vim.tbl_count(active_batches))
    end)
  end)
  
  describe("stopping", function()
    it("should stop processing", function()
      queue:push({ path = "/project1" })
      
      processor:stop()
      
      local status = processor:get_status()
      assert.is_false(status.is_running)
    end)
  end)
end)
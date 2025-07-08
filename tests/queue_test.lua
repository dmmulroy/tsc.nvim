local Queue = require("tsc.core.queue")

describe("Queue", function()
  local queue
  
  before_each(function()
    queue = Queue.new()
  end)
  
  describe("basic operations", function()
    it("should start empty", function()
      assert.is_true(queue:is_empty())
      assert.equals(0, queue:size())
    end)
    
    it("should add items", function()
      local id = queue:push("item1")
      assert.is_false(queue:is_empty())
      assert.equals(1, queue:size())
      assert.is_string(id)
    end)
    
    it("should remove items FIFO by default", function()
      local id1 = queue:push("item1")
      local id2 = queue:push("item2")
      
      local item, id = queue:pop()
      assert.equals("item1", item)
      assert.equals(id1, id)
      
      local item2, id2_returned = queue:pop()
      assert.equals("item2", item2)
      assert.equals(id2, id2_returned)
      
      assert.is_true(queue:is_empty())
    end)
  end)
  
  describe("priority queue", function()
    it("should order by priority", function()
      local priority_queue = Queue.new({ strategy = "priority" })
      
      priority_queue:push("low", 1)
      priority_queue:push("high", 10)
      priority_queue:push("medium", 5)
      
      local item1, _ = priority_queue:pop()
      assert.equals("high", item1)
      
      local item2, _ = priority_queue:pop()
      assert.equals("medium", item2)
      
      local item3, _ = priority_queue:pop()
      assert.equals("low", item3)
    end)
  end)
  
  describe("size-based queue", function()
    it("should order by size", function()
      local size_queue = Queue.new({ strategy = "size" })
      
      size_queue:push("large", 0, { size = 100 })
      size_queue:push("small", 0, { size = 10 })
      size_queue:push("medium", 0, { size = 50 })
      
      local item1, _ = size_queue:pop()
      assert.equals("small", item1)
      
      local item2, _ = size_queue:pop()
      assert.equals("medium", item2)
      
      local item3, _ = size_queue:pop()
      assert.equals("large", item3)
    end)
  end)
  
  describe("batch operations", function()
    it("should add multiple items", function()
      local items = { "item1", "item2", "item3" }
      local ids = queue:push_many(items)
      
      assert.equals(3, #ids)
      assert.equals(3, queue:size())
    end)
    
    it("should remove multiple items", function()
      queue:push("item1")
      queue:push("item2")
      queue:push("item3")
      
      local items = queue:pop_many(2)
      assert.equals(2, #items)
      assert.equals("item1", items[1].data)
      assert.equals("item2", items[2].data)
      assert.equals(1, queue:size())
    end)
    
    it("should peek multiple items", function()
      queue:push("item1")
      queue:push("item2")
      queue:push("item3")
      
      local items = queue:peek_many(2)
      assert.equals(2, #items)
      assert.equals("item1", items[1].data)
      assert.equals("item2", items[2].data)
      assert.equals(3, queue:size()) -- Should not remove items
    end)
  end)
  
  describe("metadata operations", function()
    it("should update priority", function()
      local priority_queue = Queue.new({ strategy = "priority" })
      
      local id1 = priority_queue:push("item1", 1)
      local id2 = priority_queue:push("item2", 2)
      
      -- Update priority of item1 to be higher
      assert.is_true(priority_queue:update_priority(id1, 10))
      
      local item, _ = priority_queue:pop()
      assert.equals("item1", item) -- Should come first now
    end)
    
    it("should update metadata", function()
      local id = queue:push("item", 0, { original = true })
      
      assert.is_true(queue:update_metadata(id, { updated = true }))
      
      local items = queue:get_all()
      assert.equals(1, #items)
      assert.is_true(items[1].metadata.original)
      assert.is_true(items[1].metadata.updated)
    end)
  end)
  
  describe("filtering and search", function()
    it("should filter items", function()
      queue:push("item1", 0, { type = "test" })
      queue:push("item2", 0, { type = "prod" })
      queue:push("item3", 0, { type = "test" })
      
      local filtered = queue:filter(function(item, id, metadata)
        return metadata.type == "test"
      end)
      
      assert.equals(2, #filtered)
      assert.equals("item1", filtered[1].data)
      assert.equals("item3", filtered[2].data)
    end)
    
    it("should find items", function()
      queue:push("item1", 0, { name = "first" })
      queue:push("item2", 0, { name = "second" })
      
      local item, id = queue:find(function(item, id, metadata)
        return metadata.name == "second"
      end)
      
      assert.equals("item2", item)
      assert.is_string(id)
    end)
  end)
  
  describe("statistics", function()
    it("should provide queue stats", function()
      queue:push("item1", 5)
      queue:push("item2", 3)
      queue:push("item3", 5)
      
      local stats = queue:get_stats()
      assert.equals(3, stats.size)
      assert.equals("fifo", stats.strategy)
      assert.equals(2, stats.priorities[5])
      assert.equals(1, stats.priorities[3])
    end)
  end)
  
  describe("strategy changes", function()
    it("should change strategy", function()
      queue:push("item1", 1)
      queue:push("item2", 10)
      
      -- Initially FIFO
      local item1, _ = queue:peek()
      assert.equals("item1", item1)
      
      -- Change to priority
      queue:set_strategy("priority")
      
      local item2, _ = queue:peek()
      assert.equals("item2", item2) -- Higher priority should come first
    end)
  end)
end)
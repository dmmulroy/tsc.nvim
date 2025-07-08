-- Unit tests for event system
local Events = require('tsc.core.events')

describe('Events', function()
  local events
  
  before_each(function()
    events = Events.new()
  end)
  
  describe('new', function()
    it('should create a new event system', function()
      assert.is_table(events)
      assert.is_function(events.emit)
      assert.is_function(events.on)
      assert.is_function(events.off)
      assert.is_function(events.once)
    end)
  end)
  
  describe('on', function()
    it('should register event listeners', function()
      local called = false
      
      events:on('test.event', function()
        called = true
      end)
      
      events:emit('test.event')
      
      -- Give time for scheduled callback
      vim.wait(10)
      
      assert.is_true(called)
    end)
    
    it('should support multiple listeners', function()
      local count = 0
      
      events:on('test.event', function() count = count + 1 end)
      events:on('test.event', function() count = count + 1 end)
      
      events:emit('test.event')
      
      -- Give time for scheduled callbacks
      vim.wait(10)
      
      assert.equal(2, count)
    end)
    
    it('should pass event data to listeners', function()
      local received_data = nil
      
      events:on('test.event', function(data)
        received_data = data
      end)
      
      events:emit('test.event', { foo = 'bar' })
      
      -- Give time for scheduled callback
      vim.wait(10)
      
      assert.is_table(received_data)
      assert.equal('bar', received_data.foo)
      assert.equal('test.event', received_data.event)
      assert.is_number(received_data.timestamp)
    end)
    
    it('should return unsubscribe function', function()
      local called = false
      
      local unsubscribe = events:on('test.event', function()
        called = true
      end)
      
      assert.is_function(unsubscribe)
      
      unsubscribe()
      events:emit('test.event')
      
      -- Give time for potential callback
      vim.wait(10)
      
      assert.is_false(called)
    end)
  end)
  
  describe('once', function()
    it('should register one-time listeners', function()
      local count = 0
      
      events:once('test.event', function()
        count = count + 1
      end)
      
      events:emit('test.event')
      events:emit('test.event')
      
      -- Give time for callbacks
      vim.wait(10)
      
      assert.equal(1, count)
    end)
    
    it('should return unsubscribe function', function()
      local called = false
      
      local unsubscribe = events:once('test.event', function()
        called = true
      end)
      
      unsubscribe()
      events:emit('test.event')
      
      -- Give time for potential callback
      vim.wait(10)
      
      assert.is_false(called)
    end)
  end)
  
  describe('off', function()
    it('should remove event listeners', function()
      local called = false
      
      local callback = function()
        called = true
      end
      
      events:on('test.event', callback)
      events:off('test.event', callback)
      events:emit('test.event')
      
      -- Give time for potential callback
      vim.wait(10)
      
      assert.is_false(called)
    end)
  end)
  
  describe('clear', function()
    it('should clear all listeners for an event', function()
      local count = 0
      
      events:on('test.event', function() count = count + 1 end)
      events:on('test.event', function() count = count + 1 end)
      events:once('test.event', function() count = count + 1 end)
      
      events:clear('test.event')
      events:emit('test.event')
      
      -- Give time for potential callbacks
      vim.wait(10)
      
      assert.equal(0, count)
    end)
    
    it('should clear all listeners when no event specified', function()
      local count = 0
      
      events:on('test.event1', function() count = count + 1 end)
      events:on('test.event2', function() count = count + 1 end)
      
      events:clear()
      events:emit('test.event1')
      events:emit('test.event2')
      
      -- Give time for potential callbacks
      vim.wait(10)
      
      assert.equal(0, count)
    end)
  end)
  
  describe('stats', function()
    it('should return event statistics', function()
      events:on('test.event1', function() end)
      events:on('test.event1', function() end)
      events:once('test.event2', function() end)
      
      local stats = events:stats()
      
      assert.equal(2, stats.regular_listeners)
      assert.equal(1, stats.once_listeners)
      assert.equal(2, stats.total_events)
    end)
  end)
  
  describe('error handling', function()
    it('should handle listener errors gracefully', function()
      local good_called = false
      
      events:on('test.event', function()
        error('Test error')
      end)
      
      events:on('test.event', function()
        good_called = true
      end)
      
      events:emit('test.event')
      
      -- Give time for callbacks
      vim.wait(10)
      
      -- Good listener should still be called
      assert.is_true(good_called)
    end)
  end)
end)
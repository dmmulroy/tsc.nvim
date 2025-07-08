-- Unit tests for quickfix plugin
local QuickfixPlugin = require('tsc.plugins.quickfix')
local Events = require('tsc.core.events')

describe('QuickfixPlugin', function()
  local plugin
  local events
  local mock_qflist
  
  before_each(function()
    events = Events.new()
    plugin = QuickfixPlugin.new(events, {
      auto_open = true,
      auto_close = true,
      title = 'Test TSC',
    })
    
    -- Mock vim.fn.setqflist and related functions
    mock_qflist = {}
    vim.fn.setqflist = function(items, action, what)
      if action == 'r' then
        mock_qflist = what.items or {}
      end
    end
    
    vim.fn.getqflist = function(what)
      if what and what.size then
        return { size = #mock_qflist }
      elseif what and what.winid then
        return { winid = 0 }
      elseif what and what.title then
        return { title = 'Test TSC' }
      end
      return mock_qflist
    end
    
    -- Mock vim commands
    _G.test_commands = {}
    vim.cmd = function(cmd)
      table.insert(_G.test_commands, cmd)
    end
  end)
  
  after_each(function()
    _G.test_commands = nil
  end)
  
  describe('new', function()
    it('should create quickfix plugin', function()
      assert.equal('quickfix', plugin.name)
      assert.equal('3.0.0', plugin.version)
      assert.is_table(plugin._config)
      assert.is_true(plugin._config.auto_open)
      assert.equal('Test TSC', plugin._config.title)
    end)
  end)
  
  describe('setup', function()
    it('should register event listeners', function()
      local listeners_before = events:get_listeners('tsc.completed')
      assert.equal(0, #listeners_before)
      
      plugin:setup()
      
      local listeners_after = events:get_listeners('tsc.completed')
      assert.equal(1, #listeners_after)
    end)
  end)
  
  describe('event handling', function()
    before_each(function()
      plugin:setup()
    end)
    
    it('should handle completion with errors', function()
      local test_errors = {
        {
          filename = 'src/index.ts',
          lnum = 10,
          col = 5,
          text = 'TS2322: Type error',
          type = 'E',
          valid = 1,
        },
        {
          filename = 'src/utils.ts',
          lnum = 20,
          col = 10,
          text = 'TS2339: Property error',
          type = 'E',
          valid = 1,
        },
      }
      
      events:emit('tsc.completed', { errors = test_errors })
      
      -- Allow event processing
      vim.wait(10)
      
      -- Check that quickfix list was updated
      assert.equal(2, #mock_qflist)
      assert.equal('src/index.ts', mock_qflist[1].filename)
      assert.equal(10, mock_qflist[1].lnum)
      
      -- Check that quickfix was opened
      assert.is_true(vim.tbl_contains(_G.test_commands, 'copen 3'))
    end)
    
    it('should handle completion with no errors', function()
      events:emit('tsc.completed', { errors = {} })
      
      -- Allow event processing
      vim.wait(10)
      
      -- Check that quickfix list was cleared
      assert.equal(0, #mock_qflist)
      
      -- Check that quickfix was closed
      assert.is_true(vim.tbl_contains(_G.test_commands, 'cclose'))
    end)
    
    it('should not auto-open when disabled', function()
      plugin._config.auto_open = false
      
      local test_errors = {
        {
          filename = 'src/index.ts',
          lnum = 10,
          col = 5,
          text = 'TS2322: Type error',
          type = 'E',
          valid = 1,
        },
      }
      
      events:emit('tsc.completed', { errors = test_errors })
      
      -- Allow event processing
      vim.wait(10)
      
      -- Check that quickfix was not opened
      assert.is_false(vim.tbl_contains(_G.test_commands, 'copen 3'))
    end)
  end)
  
  describe('manual control', function()
    it('should update quickfix list', function()
      local items = {
        {
          filename = 'src/test.ts',
          lnum = 5,
          col = 1,
          text = 'Test error',
          type = 'E',
          valid = 1,
        },
      }
      
      plugin:update(items)
      
      assert.equal(1, #mock_qflist)
      assert.equal('src/test.ts', mock_qflist[1].filename)
    end)
    
    it('should open quickfix list', function()
      plugin:open()
      
      assert.is_true(vim.tbl_contains(_G.test_commands, 'copen 3'))
    end)
    
    it('should close quickfix list', function()
      plugin:close()
      
      assert.is_true(vim.tbl_contains(_G.test_commands, 'cclose'))
    end)
    
    it('should clear quickfix list', function()
      plugin:clear()
      
      assert.equal(0, #mock_qflist)
    end)
    
    it('should toggle quickfix list', function()
      -- Mock getqflist to return no window initially
      vim.fn.getqflist = function(what)
        if what and what.winid then
          return { winid = 0 }
        end
        return {}
      end
      
      plugin:toggle()
      
      assert.is_true(vim.tbl_contains(_G.test_commands, 'copen 3'))
    end)
  end)
  
  describe('configuration', function()
    it('should calculate quickfix height', function()
      -- Mock getqflist to return different sizes
      local sizes = { 2, 5, 15 }
      local heights = {}
      
      for _, size in ipairs(sizes) do
        vim.fn.getqflist = function()
          return {}
        end
        vim.fn.len = function()
          return size
        end
        
        plugin:open()
        
        -- Extract height from command
        local last_command = _G.test_commands[#_G.test_commands]
        local height = last_command:match('copen (%d+)')
        table.insert(heights, tonumber(height))
      end
      
      -- Heights should be: 3 (min), 5, 10 (max)
      assert.equal(3, heights[1])  -- min_height
      assert.equal(5, heights[2])  -- actual size
      assert.equal(10, heights[3]) -- max_height
    end)
    
    it('should update configuration', function()
      plugin:update_config({
        auto_open = false,
        title = 'New Title',
      })
      
      assert.is_false(plugin._config.auto_open)
      assert.equal('New Title', plugin._config.title)
    end)
  end)
  
  describe('status', function()
    it('should return plugin status', function()
      local status = plugin:get_status()
      
      assert.is_table(status)
      assert.is_boolean(status.is_open)
      assert.is_number(status.item_count)
      assert.is_table(status.config)
    end)
  end)
  
  describe('cleanup', function()
    it('should clear quickfix on cleanup', function()
      -- Add some items first
      plugin:update({
        { filename = 'test.ts', lnum = 1, col = 1, text = 'Error' },
      })
      
      assert.equal(1, #mock_qflist)
      
      plugin:cleanup()
      
      assert.equal(0, #mock_qflist)
    end)
  end)
end)
-- Integration tests for watch mode
local tsc = require('tsc')
local fs = require('tsc.utils.fs')

describe('Watch Mode Integration', function()
  local temp_dir
  local original_cwd
  local mock_watchers = {}
  
  before_each(function()
    original_cwd = vim.fn.getcwd()
    temp_dir = vim.fn.tempname()
    
    -- Create temporary project
    vim.fn.mkdir(temp_dir, 'p')
    vim.fn.mkdir(temp_dir .. '/src', 'p')
    vim.cmd('cd ' .. temp_dir)
    
    -- Create project files
    fs.write_file(temp_dir .. '/tsconfig.json', vim.fn.json_encode({
      compilerOptions = { strict = true, noEmit = true },
      include = { 'src/**/*' },
    }))
    
    fs.write_file(temp_dir .. '/package.json', vim.fn.json_encode({
      name = 'test-project',
      devDependencies = { typescript = '^4.0.0' },
    }))
    
    -- Mock file system watcher
    mock_watchers = {}
    local original_new_fs_event = vim.loop.new_fs_event
    vim.loop.new_fs_event = function()
      local watcher = {
        _callbacks = {},
        _path = nil,
        _opts = nil,
      }
      
      function watcher:start(path, opts, callback)
        self._path = path
        self._opts = opts
        self._callback = callback
        mock_watchers[path] = self
        return true, nil
      end
      
      function watcher:stop()
        if self._path then
          mock_watchers[self._path] = nil
        end
      end
      
      -- Method to simulate file changes
      function watcher:simulate_change(filename, events)
        if self._callback then
          self._callback(nil, filename, events)
        end
      end
      
      return watcher
    end
  end)
  
  after_each(function()
    vim.cmd('cd ' .. original_cwd)
    if temp_dir and fs.dir_exists(temp_dir) then
      vim.fn.delete(temp_dir, 'rf')
    end
    
    mock_watchers = {}
    
    if tsc.cleanup then
      tsc.cleanup()
    end
  end)
  
  describe('watch mode setup', function()
    it('should start file watchers when watch mode enabled', function()
      -- Initialize with watch mode
      local instance = tsc.setup({
        mode = 'project',
        plugins = {
          quickfix = { enabled = false },
          watch = { 
            enabled = true,
            patterns = {'*.ts', '*.tsx'},
          },
          diagnostics = { enabled = false },
        },
      })
      
      -- Mock TypeScript execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function() return true end
      
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        -- Simulate watch mode output
        if opts.on_stdout then
          vim.schedule(function()
            opts.on_stdout(nil, {'Starting compilation in watch mode...'})
          end)
        end
        
        return 123
      end
      
      -- Run in watch mode
      instance:run({ watch = true })
      
      -- Wait for setup
      vim.wait(100)
      
      -- Check that watcher was created
      assert.is_true(vim.tbl_count(mock_watchers) > 0)
      
      local watcher_path = next(mock_watchers)
      assert.is_true(watcher_path:match(temp_dir))
      
      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
    
    it('should stop watchers when watch mode stopped', function()
      local instance = tsc.setup({
        plugins = {
          watch = { enabled = true },
          quickfix = { enabled = false },
        },
      })
      
      -- Mock execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function() return true end
      
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 123 end
      
      -- Start watch mode
      instance:run({ watch = true })
      vim.wait(50)
      
      -- Verify watcher exists
      assert.is_true(vim.tbl_count(mock_watchers) > 0)
      
      -- Stop watch mode
      instance:stop()
      vim.wait(50)
      
      -- Verify watchers are stopped
      assert.equal(0, vim.tbl_count(mock_watchers))
      
      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
  end)
  
  describe('file change detection', function()
    it('should trigger recompilation on file changes', function()
      local compilation_count = 0
      local run_requests = {}
      
      local instance = tsc.setup({
        plugins = {
          watch = { 
            enabled = true,
            debounce_ms = 100,
            patterns = {'*.ts'},
          },
          quickfix = { enabled = false },
        },
      })
      
      -- Listen for run requests
      local events = instance:get_events()
      events:on('tsc.run_requested', function(data)
        table.insert(run_requests, data)
      end)
      
      -- Mock execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function() return true end
      
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function(cmd, opts)
        compilation_count = compilation_count + 1
        return 123
      end
      
      -- Start watch mode
      instance:run({ watch = true })
      vim.wait(50)
      
      -- Simulate file change
      local watcher = next(mock_watchers)
      if mock_watchers[watcher] then
        mock_watchers[watcher]:simulate_change('src/index.ts', {})
      end
      
      -- Wait for debounce and processing
      vim.wait(200)
      
      -- Should have triggered recompilation
      assert.is_true(#run_requests > 1) -- Initial + file change
      assert.is_true(run_requests[2].watch)
      assert.is_true(run_requests[2].incremental)
      
      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
    
    it('should debounce rapid file changes', function()
      local run_count = 0
      
      local instance = tsc.setup({
        plugins = {
          watch = { 
            enabled = true,
            debounce_ms = 200,
          },
          quickfix = { enabled = false },
        },
      })
      
      -- Count run requests
      local events = instance:get_events()
      events:on('tsc.run_requested', function()
        run_count = run_count + 1
      end)
      
      -- Mock execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function() return true end
      
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 123 end
      
      -- Start watch mode
      instance:run({ watch = true })
      vim.wait(50)
      
      -- Simulate rapid file changes
      local watcher = next(mock_watchers)
      if mock_watchers[watcher] then
        for i = 1, 5 do
          mock_watchers[watcher]:simulate_change('src/test.ts', {})
          vim.wait(10) -- Short interval
        end
      end
      
      -- Wait for debounce period
      vim.wait(300)
      
      -- Should have debounced to only 2 runs (initial + debounced)
      assert.equal(2, run_count)
      
      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
    
    it('should filter files by patterns', function()
      local file_change_events = {}
      
      local instance = tsc.setup({
        plugins = {
          watch = { 
            enabled = true,
            patterns = {'*.ts', '*.tsx'},
            ignore_patterns = {'node_modules', '*.test.ts'},
          },
          quickfix = { enabled = false },
        },
      })
      
      -- Listen for file change events
      local events = instance:get_events()
      events:on('tsc.file_changed', function(data)
        table.insert(file_change_events, data)
      end)
      
      -- Mock execution
      local original_is_executable = fs.is_executable
      fs.is_executable = function() return true end
      
      local original_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 123 end
      
      -- Start watch mode
      instance:run({ watch = true })
      vim.wait(50)
      
      -- Simulate various file changes
      local watcher = next(mock_watchers)
      if mock_watchers[watcher] then
        local test_files = {
          'src/index.ts',        -- Should trigger
          'src/component.tsx',   -- Should trigger
          'src/test.js',         -- Should not trigger (wrong extension)
          'src/index.test.ts',   -- Should not trigger (ignore pattern)
          'node_modules/lib.ts', -- Should not trigger (ignore pattern)
        }
        
        for _, file in ipairs(test_files) do
          mock_watchers[watcher]:simulate_change(file, {})
          vim.wait(10)
        end
      end
      
      -- Wait for processing
      vim.wait(300)
      
      -- Should only have events for valid TypeScript files
      assert.equal(2, #file_change_events)
      
      local changed_files = {}
      for _, event in ipairs(file_change_events) do
        table.insert(changed_files, fs.basename(event.file))
      end
      
      assert.is_true(vim.tbl_contains(changed_files, 'index.ts'))
      assert.is_true(vim.tbl_contains(changed_files, 'component.tsx'))
      
      -- Restore mocks
      fs.is_executable = original_is_executable
      vim.fn.jobstart = original_jobstart
    end)
  end)
  
  describe('auto-start functionality', function()
    it('should auto-start watch mode on TypeScript file open', function()
      local auto_start_triggered = false
      
      local instance = tsc.setup({
        plugins = {
          watch = { 
            enabled = true,
            auto_start = true,
          },
          quickfix = { enabled = false },
        },
      })
      
      -- Listen for run requests
      local events = instance:get_events()
      events:on('tsc.run_requested', function(data)
        if data.auto_start then
          auto_start_triggered = true
        end
      end)
      
      -- Mock file system
      local original_findfile = vim.fn.findfile
      vim.fn.findfile = function(filename, path)
        if filename == 'tsconfig.json' then
          return temp_dir .. '/tsconfig.json'
        end
        return ''
      end
      
      local original_fnamemodify = vim.fn.fnamemodify
      vim.fn.fnamemodify = function(path, modifier)
        if modifier == ':h' then
          return temp_dir .. '/src'
        end
        return path
      end
      
      -- Mock buffer operations
      vim.api.nvim_buf_get_name = function()
        return temp_dir .. '/src/index.ts'
      end
      
      -- Simulate opening a TypeScript file
      vim.api.nvim_exec_autocmds('BufRead', {
        pattern = '*.ts',
        buffer = 1,
      })
      
      -- Wait for processing
      vim.wait(100)
      
      assert.is_true(auto_start_triggered)
      
      -- Restore mocks
      vim.fn.findfile = original_findfile
      vim.fn.fnamemodify = original_fnamemodify
    end)
  end)
end)
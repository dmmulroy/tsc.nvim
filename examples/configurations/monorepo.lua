-- Monorepo tsc.nvim 3.0 configuration
-- For large TypeScript monorepos with multiple packages

require('tsc').setup({
  -- Mode: Check all projects in monorepo
  mode = 'monorepo',
  
  -- Project discovery for monorepos
  discovery = {
    -- Look for these files to identify project roots
    root_markers = { 'package.json', 'tsconfig.json' },
    
    -- TypeScript config file name
    tsconfig_name = 'tsconfig.json',
    
    -- Limit number of projects to prevent overwhelming
    max_projects = 50,
    
    -- Exclude common directories
    exclude_patterns = {
      'node_modules',
      '.git',
      'dist',
      'build',
      '.turbo',
      '.next',
      'coverage',
    },
  },
  
  -- TypeScript configuration
  typescript = {
    -- Use local TypeScript version
    bin = nil,
    
    -- Strict checking with performance optimizations
    flags = '--noEmit --incremental',
    
    -- Longer timeout for large codebases
    timeout = 120000,  -- 2 minutes
    
    -- Let each project use its own working directory
    working_dir = nil,
  },
  
  -- Output configuration
  output = {
    auto_open = true,
    auto_close = false,  -- Keep open to see patterns across projects
  },
  
  -- Plugin configuration
  plugins = {
    -- Enhanced quickfix for monorepos
    quickfix = {
      enabled = true,
      auto_focus = false,
      title = 'TypeScript (Monorepo)',
      max_height = 15,  -- More space for multiple project errors
      min_height = 5,
    },
    
    -- Enable watch mode for development
    watch = {
      enabled = true,
      auto_start = false,  -- Manual start to avoid overwhelming
      debounce_ms = 1000,  -- Longer debounce for large repos
      patterns = { '*.ts', '*.tsx', '*.mts', '*.cts' },
      ignore_patterns = {
        'node_modules',
        '.git',
        'dist',
        'build',
        '*.test.ts',
        '*.spec.ts',
        '.turbo',
        '.next',
      },
      preserve_focus = true,
      clear_on_change = false,
      notify_on_change = false,  -- Reduce noise
    },
    
    -- Enable diagnostics for better IDE integration
    diagnostics = {
      enabled = true,
      namespace = 'tsc_monorepo',
      virtual_text = {
        enabled = false,  -- Disable to reduce visual clutter
      },
      signs = {
        enabled = true,
        priority = 8,  -- Lower priority than LSP
      },
      underline = {
        enabled = true,
        severity_limit = vim.diagnostic.severity.ERROR,
      },
      float = {
        enabled = true,
        source = 'always',
        border = 'rounded',
      },
    },
    
    -- Enhanced error messages
    better_messages = {
      enabled = true,
      cache_templates = true,
      strip_markdown_links = true,
    },
  },
})

-- Enhanced key mappings for monorepo workflow
vim.keymap.set('n', '<leader>tc', ':TSC<CR>', { desc = 'Check all packages' })
vim.keymap.set('n', '<leader>tw', ':TSC watch<CR>', { desc = 'Start watch mode' })
vim.keymap.set('n', '<leader>ts', ':TSCStop<CR>', { desc = 'Stop type checking' })
vim.keymap.set('n', '<leader>to', ':TSCOpen<CR>', { desc = 'Open errors' })
vim.keymap.set('n', '<leader>tx', ':TSCClose<CR>', { desc = 'Close errors' })
vim.keymap.set('n', '<leader>tS', ':TSCStatus<CR>', { desc = 'Show status' })

-- Package-specific type checking (check current package only)
vim.keymap.set('n', '<leader>tp', function()
  local tsc = require('tsc')
  tsc.run({ mode = 'package' })
end, { desc = 'Check current package' })

-- Auto-start watch mode for TypeScript files in development
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'typescript', 'typescriptreact' },
  group = vim.api.nvim_create_augroup('tsc_monorepo_auto', { clear = true }),
  callback = function()
    -- Only auto-start in development environment
    if vim.env.NODE_ENV == 'development' or vim.env.ENVIRONMENT == 'dev' then
      vim.defer_fn(function()
        local tsc = require('tsc')
        local status = tsc.status()
        
        -- Start watch mode if not already running
        if status.runner.active_runs == 0 then
          tsc.run({ watch = true })
        end
      end, 1000)  -- Delay to allow project setup
    end
  end,
})

-- Customize quickfix appearance for monorepo
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    -- Add buffer-local mappings for quickfix
    vim.keymap.set('n', 'q', ':close<CR>', { buffer = true, silent = true })
    vim.keymap.set('n', '<CR>', '<CR>zz', { buffer = true, silent = true })
    
    -- Show package name in quickfix entries
    vim.opt_local.statusline = '%t [%{len(getqflist())} errors across packages]'
  end,
})

-- Performance monitoring for large monorepos
local function setup_performance_monitoring()
  local start_time
  
  local tsc = require('tsc')
  local events = tsc.get_events()
  
  if events then
    events:on('tsc.started', function(data)
      start_time = vim.loop.now()
      if data.watch then
        print(string.format('🔍 Watching %d packages...', #data.projects))
      else
        print(string.format('⏳ Type-checking %d packages...', #data.projects))
      end
    end)
    
    events:on('tsc.completed', function(data)
      if start_time then
        local duration = vim.loop.now() - start_time
        local error_count = #data.errors
        
        print(string.format(
          '✅ Checked %d packages in %.1fs - %d errors found',
          data.project_count,
          duration / 1000,
          error_count
        ))
      end
    end)
  end
end

-- Set up performance monitoring after tsc is initialized
vim.defer_fn(setup_performance_monitoring, 100)
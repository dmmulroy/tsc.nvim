-- Advanced tsc.nvim 3.0 configuration
-- Full-featured setup with custom plugins and integrations

require('tsc').setup({
  mode = 'project',
  
  discovery = {
    root_markers = { 'package.json', 'tsconfig.json', '.git' },
    tsconfig_name = 'tsconfig.json',
    max_projects = 30,
    exclude_patterns = {
      'node_modules',
      '.git',
      'dist',
      'build',
      'coverage',
      '.turbo',
      '.next',
      '.nuxt',
      'out',
    },
  },
  
  typescript = {
    bin = nil,  -- Auto-detect
    flags = '--noEmit --listFiles',  -- Include file listing
    timeout = 60000,
    working_dir = nil,
  },
  
  output = {
    auto_open = true,
    auto_close = false,
  },
  
  plugins = {
    -- Enhanced quickfix with custom styling
    quickfix = {
      enabled = true,
      auto_focus = false,
      auto_close = false,
      title = 'TypeScript Issues',
      max_height = 20,
      min_height = 3,
    },
    
    -- Advanced watch mode configuration
    watch = {
      enabled = true,
      auto_start = true,
      debounce_ms = 750,
      patterns = { '*.ts', '*.tsx', '*.mts', '*.cts', '*.vue' },
      ignore_patterns = {
        'node_modules',
        '.git',
        'dist',
        'build',
        '*.test.*',
        '*.spec.*',
        '*.d.ts',
        'coverage',
      },
      preserve_focus = true,
      clear_on_change = true,
      notify_on_change = false,
    },
    
    -- Full diagnostics integration
    diagnostics = {
      enabled = true,
      namespace = 'tsc_advanced',
      virtual_text = {
        enabled = true,
        prefix = '●',
        spacing = 2,
        severity_limit = vim.diagnostic.severity.WARN,
      },
      signs = {
        enabled = true,
        priority = 9,
      },
      underline = {
        enabled = true,
        severity_limit = vim.diagnostic.severity.INFO,
      },
      update_in_insert = false,
      severity_sort = true,
      float = {
        enabled = true,
        source = 'if_many',
        border = 'rounded',
        focusable = false,
      },
    },
    
    -- Enhanced error messages with custom templates
    better_messages = {
      enabled = true,
      cache_templates = true,
      strip_markdown_links = true,
      custom_templates = {
        -- Add custom error message templates
        ['2322'] = {
          original = "Type '{0}' is not assignable to type '{1}'",
          better = "❌ Cannot assign {0} to {1} - check your type definitions",
        },
        ['2339'] = {
          original = "Property '{0}' does not exist on type '{1}'",
          better = "🔍 Property {0} not found on {1} - check spelling or type definition",
        },
      },
    },
  },
})

-- Advanced key mappings with which-key.nvim integration
local function setup_keymaps()
  -- Basic mappings
  vim.keymap.set('n', '<leader>tc', ':TSC<CR>', { desc = 'Type check' })
  vim.keymap.set('n', '<leader>tw', ':TSC watch<CR>', { desc = 'Watch mode' })
  vim.keymap.set('n', '<leader>ts', ':TSCStop<CR>', { desc = 'Stop checking' })
  vim.keymap.set('n', '<leader>to', ':TSCOpen<CR>', { desc = 'Open errors' })
  vim.keymap.set('n', '<leader>tx', ':TSCClose<CR>', { desc = 'Close errors' })
  
  -- Advanced mappings
  vim.keymap.set('n', '<leader>tS', ':TSCStatus<CR>', { desc = 'Status' })
  vim.keymap.set('n', '<leader>tT', ':TSCToggle<CR>', { desc = 'Toggle errors' })
  
  -- Mode-specific checking
  vim.keymap.set('n', '<leader>tp', function()
    require('tsc').run({ mode = 'project' })
  end, { desc = 'Check project' })
  
  vim.keymap.set('n', '<leader>tm', function()
    require('tsc').run({ mode = 'monorepo' })
  end, { desc = 'Check monorepo' })
  
  -- Diagnostic navigation
  vim.keymap.set('n', ']d', function()
    vim.diagnostic.goto_next({ namespace = vim.diagnostic.get_namespace('tsc_advanced') })
  end, { desc = 'Next TSC diagnostic' })
  
  vim.keymap.set('n', '[d', function()
    vim.diagnostic.goto_prev({ namespace = vim.diagnostic.get_namespace('tsc_advanced') })
  end, { desc = 'Previous TSC diagnostic' })
  
  -- Show diagnostic float
  vim.keymap.set('n', '<leader>td', function()
    vim.diagnostic.open_float({ namespace = vim.diagnostic.get_namespace('tsc_advanced') })
  end, { desc = 'Show TSC diagnostic' })
  
  -- which-key.nvim integration
  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.register({
      ['<leader>t'] = {
        name = 'TypeScript',
        c = 'Type check',
        w = 'Watch mode',
        s = 'Stop checking',
        o = 'Open errors',
        x = 'Close errors',
        S = 'Status',
        T = 'Toggle errors',
        p = 'Check project',
        m = 'Check monorepo',
        d = 'Show diagnostic',
      },
    })
  end
end

-- Custom status line integration
local function setup_statusline()
  local function tsc_status()
    local tsc = require('tsc')
    local status = tsc.status()
    
    if not status.initialized then
      return ''
    end
    
    local running = status.runner.running_processes
    if running > 0 then
      return string.format('TSC ⏳%d', running)
    end
    
    -- Get error count from quickfix
    local qf_list = vim.fn.getqflist()
    local error_count = 0
    for _, item in ipairs(qf_list) do
      if item.valid == 1 then
        error_count = error_count + 1
      end
    end
    
    if error_count > 0 then
      return string.format('TSC ❌%d', error_count)
    else
      return 'TSC ✅'
    end
  end
  
  -- Add to statusline (example for lualine.nvim)
  local ok, lualine = pcall(require, 'lualine')
  if ok then
    local config = lualine.get_config()
    table.insert(config.sections.lualine_x, tsc_status)
    lualine.setup(config)
  end
  
  -- For custom statusline
  vim.opt.statusline:append('%{luaeval("tsc_status()")}')
  _G.tsc_status = tsc_status
end

-- Custom notification system integration
local function setup_notifications()
  local tsc = require('tsc')
  local events = tsc.get_events()
  
  if not events then
    return
  end
  
  -- nvim-notify integration
  local ok, notify = pcall(require, 'notify')
  if ok then
    events:on('tsc.started', function(data)
      if data.watch then
        notify('👀 TypeScript watch mode started', 'info', {
          title = 'TSC',
          timeout = 2000,
        })
      else
        notify(string.format('⏳ Checking %d projects...', #data.projects), 'info', {
          title = 'TSC',
          timeout = 1000,
        })
      end
    end)
    
    events:on('tsc.completed', function(data)
      local error_count = #data.errors
      local duration = math.floor(data.duration / 1000 * 10) / 10  -- Round to 1 decimal
      
      if error_count == 0 then
        notify(string.format('✅ No errors found (%.1fs)', duration), 'info', {
          title = 'TSC',
          timeout = 3000,
        })
      else
        notify(string.format('❌ %d errors found (%.1fs)', error_count, duration), 'error', {
          title = 'TSC',
          timeout = 5000,
        })
      end
    end)
    
    events:on('tsc.stopped', function()
      notify('⏹️ TypeScript checking stopped', 'warn', {
        title = 'TSC',
        timeout = 2000,
      })
    end)
  end
end

-- Performance monitoring and optimization
local function setup_performance_monitoring()
  local tsc = require('tsc')
  local events = tsc.get_events()
  
  if not events then
    return
  end
  
  local performance_data = {
    runs = {},
    avg_duration = 0,
    total_runs = 0,
  }
  
  events:on('tsc.completed', function(data)
    -- Track performance data
    table.insert(performance_data.runs, {
      timestamp = os.time(),
      duration = data.duration,
      project_count = data.project_count,
      error_count = #data.errors,
    })
    
    -- Keep only last 50 runs
    if #performance_data.runs > 50 then
      table.remove(performance_data.runs, 1)
    end
    
    -- Calculate average
    local total_duration = 0
    for _, run in ipairs(performance_data.runs) do
      total_duration = total_duration + run.duration
    end
    performance_data.avg_duration = total_duration / #performance_data.runs
    performance_data.total_runs = performance_data.total_runs + 1
    
    -- Warn about slow compilation
    if data.duration > 30000 then  -- 30 seconds
      vim.notify(
        string.format('⚠️  Slow TypeScript compilation: %.1fs', data.duration / 1000),
        vim.log.levels.WARN
      )
    end
  end)
  
  -- Command to show performance stats
  vim.api.nvim_create_user_command('TSCPerf', function()
    local recent_runs = vim.list_slice(performance_data.runs, -10)  -- Last 10 runs
    local lines = {
      'TypeScript Performance Statistics',
      '================================',
      string.format('Total runs: %d', performance_data.total_runs),
      string.format('Average duration: %.1fs', performance_data.avg_duration / 1000),
      '',
      'Recent runs:',
    }
    
    for i, run in ipairs(recent_runs) do
      table.insert(lines, string.format(
        '%d. %.1fs (%d projects, %d errors) - %s',
        i,
        run.duration / 1000,
        run.project_count,
        run.error_count,
        os.date('%H:%M:%S', run.timestamp)
      ))
    end
    
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end, { desc = 'Show TypeScript performance statistics' })
end

-- Auto-commands for advanced workflow
local function setup_autocommands()
  local group = vim.api.nvim_create_augroup('tsc_advanced', { clear = true })
  
  -- Auto-run on specific file saves
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = { 'tsconfig.json', 'package.json' },
    desc = 'Auto-run TSC on config changes',
    callback = function()
      -- Delay to allow file system to update
      vim.defer_fn(function()
        require('tsc').run()
      end, 500)
    end,
  })
  
  -- Clear cache on git branch changes
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'FugitiveChanged',
    desc = 'Clear TSC cache on git branch change',
    callback = function()
      local tsc = require('tsc')
      local discovery = tsc._discovery
      if discovery and discovery.clear_cache then
        discovery:clear_cache()
      end
    end,
  })
  
  -- Enhance quickfix appearance
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'qf',
    callback = function()
      -- Custom quickfix mappings
      vim.keymap.set('n', 'q', ':close<CR>', { buffer = true, silent = true })
      vim.keymap.set('n', '<Tab>', ':cnext<CR>zz', { buffer = true, silent = true })
      vim.keymap.set('n', '<S-Tab>', ':cprev<CR>zz', { buffer = true, silent = true })
      vim.keymap.set('n', 'o', '<CR>zz', { buffer = true, silent = true })
      
      -- Syntax highlighting for TypeScript errors
      vim.cmd([[
        syntax match qfError /error TS\d\+:/
        syntax match qfWarning /warning TS\d\+:/
        syntax match qfInfo /info TS\d\+:/
        highlight link qfError ErrorMsg
        highlight link qfWarning WarningMsg
        highlight link qfInfo InfoMsg
      ]])
    end,
  })
end

-- Initialize all advanced features
local function init_advanced_features()
  setup_keymaps()
  
  -- Delay other setups to ensure tsc is fully initialized
  vim.defer_fn(function()
    setup_statusline()
    setup_notifications()
    setup_performance_monitoring()
    setup_autocommands()
  end, 100)
end

-- Run initialization
init_advanced_features()
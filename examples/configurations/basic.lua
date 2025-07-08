-- Basic tsc.nvim 3.0 configuration
-- For simple TypeScript projects

require('tsc').setup({
  -- Mode: Check single project
  mode = 'project',
  
  -- TypeScript configuration
  typescript = {
    -- Auto-detect TypeScript binary (checks node_modules/.bin/tsc first)
    bin = nil,
    
    -- Basic flags for type-checking only
    flags = '--noEmit',
    
    -- 30 second timeout
    timeout = 30000,
  },
  
  -- Output configuration
  output = {
    -- Use quickfix list for errors
    format = 'quickfix',
    
    -- Auto-open quickfix when errors found
    auto_open = true,
    
    -- Auto-close quickfix when no errors
    auto_close = true,
  },
  
  -- Plugin configuration
  plugins = {
    -- Enable quickfix integration
    quickfix = {
      enabled = true,
      auto_focus = false,  -- Don't focus quickfix automatically
      title = 'TypeScript',
      max_height = 10,
    },
    
    -- Disable watch mode by default
    watch = {
      enabled = false,
    },
    
    -- Disable diagnostics (use LSP instead)
    diagnostics = {
      enabled = false,
    },
    
    -- Enable better error messages
    better_messages = {
      enabled = true,
    },
  },
})

-- Optional: Set up key mappings
vim.keymap.set('n', '<leader>tc', ':TSC<CR>', { desc = 'Run TypeScript check' })
vim.keymap.set('n', '<leader>to', ':TSCOpen<CR>', { desc = 'Open TypeScript errors' })
vim.keymap.set('n', '<leader>tx', ':TSCClose<CR>', { desc = 'Close TypeScript errors' })
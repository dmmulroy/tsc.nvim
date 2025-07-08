# tsc.nvim 3.0

<img width="569" alt="image" src="https://user-images.githubusercontent.com/2755722/233876554-efb9cfe6-c038-46c8-a7cb-b7a4aa9eac5b.png">

A modern, scalable TypeScript compiler integration for Neovim with intelligent batch processing, unlimited project support, and comprehensive monitoring.

## ✨ Features

### Core Capabilities
- **Unlimited Project Support**: Handle monorepos of any size with intelligent queue-based batch processing
- **Smart Scheduling**: Projects prioritized by size, dependencies, and importance
- **Progressive Results**: See type-checking results as they complete, not all at once
- **Resource Management**: Configurable concurrency limits prevent system overload
- **Real-time Monitoring**: Performance insights, failure tracking, and optimization recommendations

### Execution Modes
- **Project Mode**: Single project type-checking
- **Package Mode**: Target specific packages within monorepos
- **Monorepo Mode**: Full monorepo analysis with intelligent batching
- **Watch Mode**: Continuous type-checking with file change detection

### Advanced Features
- **Retry Logic**: Automatic retry of failed projects with exponential backoff
- **Better Error Messages**: Enhanced TypeScript error explanations with suggestions
- **Performance Analytics**: Built-in monitoring with Prometheus-style metrics
- **Plugin Architecture**: Extensible system with quickfix, diagnostics, and watch plugins

## 📊 Demo Videos

### Type-checking with Errors
https://user-images.githubusercontent.com/2755722/233818168-de95bc9a-c406-4c71-9ef9-021f80db1da9.mov

### Type-checking without Errors
https://user-images.githubusercontent.com/2755722/233818163-bd2c2dda-88fc-41ea-a4bc-40972ad3ce9e.mov

### Usage without [nvim-notify](https://github.com/rcarriga/nvim-notify)
https://user-images.githubusercontent.com/2755722/233843746-ee116863-bef5-4e26-ba0a-afb906a2f111.mov

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)
```lua
{
  "dmmulroy/tsc.nvim",
  config = function()
    require("tsc").setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use {
  "dmmulroy/tsc.nvim",
  config = function()
    require("tsc").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)
```vim
Plug 'dmmulroy/tsc.nvim'
```

### Recommended: Install [nvim-notify](https://github.com/rcarriga/nvim-notify)
For enhanced progress notifications and better user experience:
```lua
{
  "rcarriga/nvim-notify",
  config = function()
    vim.notify = require("notify")
  end
}
```

## ⚡ Quick Start

### Basic Setup
```lua
require("tsc").setup()
```

### Recommended Configuration
```lua
require("tsc").setup({
  -- Execution mode
  mode = "monorepo", -- "project" | "package" | "monorepo"
  
  -- Batch processing (new in 3.0)
  batch = {
    enabled = true,
    size = 5,                    -- Projects per batch
    concurrency = 3,             -- Max concurrent processes
    strategy = "size",           -- "priority" | "size" | "alpha" | "fifo"
    progressive_results = true,  -- Show results as they complete
  },
  
  -- Project discovery
  discovery = {
    max_projects = 0,  -- 0 = no limit (use batch system)
    exclude_patterns = { "node_modules", ".git", "dist" },
  },
  
  -- TypeScript configuration
  typescript = {
    bin = nil,  -- Auto-detect tsc binary
    flags = "--noEmit --strict",
    timeout = 30000,
  },
  
  -- Plugin configuration
  plugins = {
    quickfix = { enabled = true, auto_open = true },
    watch = { enabled = false, auto_start = false },
    diagnostics = { enabled = false },
    better_messages = { enabled = true },
  },
})
```

## 🚀 Usage

### Commands
- `:TSC` - Run type-checking
- `:TSCStop` - Stop current type-checking
- `:TSCOpen` - Open quickfix list
- `:TSCClose` - Close quickfix list

### API Usage
```lua
local tsc = require("tsc")

-- Run type-checking
tsc.run()

-- Stop current run
tsc.stop()

-- Get status
local status = tsc.get_status()
print("Projects remaining:", status.remaining)

-- Monitor progress
tsc.on("tsc.queue_progress", function(data)
  print(string.format("Progress: %d%% (%d/%d)", 
    data.percentage, data.completed, data.total))
end)
```

## ⚙️ Configuration

### Discovery Modes

#### Project Mode (Single Project)
```lua
require("tsc").setup({
  mode = "project",
  -- Finds nearest tsconfig.json from current directory
})
```

#### Package Mode (Monorepo Package)
```lua
require("tsc").setup({
  mode = "package",
  -- Finds package.json + tsconfig.json in current package
})
```

#### Monorepo Mode (All Projects)
```lua
require("tsc").setup({
  mode = "monorepo",
  discovery = {
    exclude_patterns = { "node_modules", ".git", "dist", "build" },
  },
  batch = {
    enabled = true,
    size = 3,           -- Smaller batches for large repos
    concurrency = 2,    -- Conservative concurrency
    strategy = "size",  -- Process smaller projects first
  },
})
```

### Batch Processing Strategies

#### Size-based (Recommended)
```lua
batch = {
  strategy = "size",  -- Process smaller projects first
  size = 5,
  concurrency = 3,
}
```

#### Priority-based
```lua
batch = {
  strategy = "priority",  -- Process high-priority projects first
  size = 5,
  concurrency = 3,
}
```

#### Alphabetical
```lua
batch = {
  strategy = "alpha",  -- Process projects alphabetically
  size = 5,
  concurrency = 3,
}
```

### Performance Tuning

#### For Large Monorepos (100+ projects)
```lua
require("tsc").setup({
  mode = "monorepo",
  batch = {
    enabled = true,
    size = 3,           -- Small batches
    concurrency = 2,    -- Conservative concurrency
    strategy = "size",
    progressive_results = true,
    retry_failed = true,
    retry_count = 2,
  },
  discovery = {
    max_projects = 0,   -- No limit
    exclude_patterns = { 
      "node_modules", ".git", "dist", "build", 
      "coverage", ".next", ".nuxt" 
    },
  },
})
```

#### For Fast Development Feedback
```lua
require("tsc").setup({
  mode = "package",
  batch = {
    enabled = true,
    size = 10,          -- Larger batches
    concurrency = 5,    -- Higher concurrency
    strategy = "priority",
    progressive_results = true,
  },
  plugins = {
    quickfix = { 
      enabled = true, 
      auto_open = true,
      auto_focus = true 
    },
  },
})
```

### Plugin Configuration

#### Quickfix Integration
```lua
plugins = {
  quickfix = {
    enabled = true,
    auto_open = true,      -- Open on errors
    auto_close = true,     -- Close when no errors
    auto_focus = false,    -- Don't steal focus
    title = "TypeScript",  -- Quickfix title
    max_height = 10,       -- Max window height
  },
}
```

#### Watch Mode
```lua
plugins = {
  watch = {
    enabled = true,
    auto_start = false,              -- Don't auto-start
    debounce_ms = 500,              -- File change debounce
    patterns = { "**/*.ts", "**/*.tsx" },
    ignore_patterns = { "node_modules/**" },
  },
}
```

#### LSP Diagnostics Integration
```lua
plugins = {
  diagnostics = {
    enabled = true,
    namespace = "tsc",               -- Diagnostic namespace
    virtual_text = true,             -- Show virtual text
    signs = true,                    -- Show signs in gutter
    underline = true,                -- Underline errors
  },
}
```

#### Better Error Messages
```lua
plugins = {
  better_messages = {
    enabled = true,
    template_dir = "better-messages", -- Custom templates
    cache_templates = true,           -- Cache for performance
    custom_templates = {
      -- Custom error message templates
      ["TS2322"] = "Type mismatch: Expected {1}, got {0}",
    },
  },
}
```

## 📊 Performance Monitoring

### Built-in Metrics
```lua
local tsc = require("tsc")

-- Get performance summary
local summary = tsc.get_performance_summary()
print("Average batch duration:", summary.metrics["batch.duration"].stats.average, "ms")

-- Get performance insights
local insights = tsc.get_performance_insights()
for _, issue in ipairs(insights.performance_issues) do
  print("Issue:", issue.message)
  print("Recommendation:", issue.recommendation)
end
```

### Export Metrics
```lua
-- Export as JSON
local json_metrics = tsc.export_metrics("json")
vim.fn.writefile({json_metrics}, "tsc-metrics.json")

-- Export as Prometheus format
local prom_metrics = tsc.export_metrics("prometheus")
print(prom_metrics)
```

## 🔧 Advanced Usage

### Event System
```lua
local tsc = require("tsc")

-- Listen for batch progress
tsc.on("tsc.queue_progress", function(data)
  local msg = string.format("TypeScript: %d%% complete (%d/%d projects)", 
    data.percentage, data.completed, data.total)
  vim.notify(msg, vim.log.levels.INFO, { title = "TypeScript" })
end)

-- Listen for project completion
tsc.on("tsc.project_completed", function(data)
  if data.result.success then
    print("✅ " .. data.project.name .. " completed")
  else
    print("❌ " .. data.project.name .. " failed")
  end
end)

-- Listen for batch completion
tsc.on("tsc.batch_completed", function(data)
  print(string.format("Batch %s completed in %dms", 
    data.batch_id, data.duration))
end)
```

### Custom Key Mappings
```lua
-- Basic commands
vim.keymap.set('n', '<leader>tc', ':TSC<CR>', { desc = "Run TypeScript check" })
vim.keymap.set('n', '<leader>ts', ':TSCStop<CR>', { desc = "Stop TypeScript check" })
vim.keymap.set('n', '<leader>to', ':TSCOpen<CR>', { desc = "Open TypeScript errors" })

-- Advanced usage
vim.keymap.set('n', '<leader>tp', function()
  local tsc = require("tsc")
  local status = tsc.get_status()
  if status.is_running then
    print(string.format("TypeScript: %d%% complete", status.percentage or 0))
  else
    print("TypeScript: Not running")
  end
end, { desc = "Show TypeScript progress" })
```

## 🆕 Migration from 2.x

### Automatic Configuration Migration
tsc.nvim 3.0 automatically migrates 2.x configurations:

```lua
-- 2.x configuration (still works)
require("tsc").setup({
  auto_open_qflist = true,
  run_as_monorepo = true,
  flags = { noEmit = true },
})

-- Automatically becomes:
-- {
--   mode = "monorepo",
--   plugins = { quickfix = { auto_open = true } },
--   typescript = { flags = "--noEmit" },
--   batch = { enabled = true },
-- }
```

### Breaking Changes
- `max_tsconfig_files` removed (use batch system instead)
- `bin_path` renamed to `typescript.bin`
- `flags` moved to `typescript.flags`
- Watch mode moved to `plugins.watch`

### Recommended Migration
1. Update your configuration to use the new 3.0 format
2. Enable batch processing for better performance
3. Configure discovery mode explicitly
4. Test with your specific monorepo setup

## ❓ FAQ

### How does batch processing improve performance?
Batch processing prevents resource exhaustion by:
- **Limiting concurrent processes**: Prevents overwhelming your system
- **Intelligent scheduling**: Processes smaller/faster projects first
- **Progressive feedback**: Shows results as they complete
- **Automatic retry**: Handles transient failures gracefully

### Can I disable batch processing?
Yes, set `batch.enabled = false` to use legacy parallel processing:
```lua
require("tsc").setup({
  batch = { enabled = false },
  -- Will process all projects in parallel (2.x behavior)
})
```

### How do I optimize for my monorepo?
1. **Profile your setup**: Run with monitoring enabled
2. **Adjust batch size**: Smaller for large projects, larger for small projects
3. **Tune concurrency**: Start with 2-3, increase based on system resources
4. **Use size strategy**: Processes smaller projects first for faster feedback

### Why is my configuration not working?
- Check that you're using the 3.0 configuration format
- Verify TypeScript binary is accessible
- Ensure your tsconfig.json files are valid
- Check the console for migration warnings

### How do I troubleshoot performance issues?
```lua
-- Enable detailed monitoring
require("tsc").setup({
  batch = { enabled = true },
  -- ... other config
})

-- After running type-checking:
local insights = require("tsc").get_performance_insights()
for _, issue in ipairs(insights.performance_issues) do
  print("⚠️  " .. issue.message)
  print("💡 " .. issue.recommendation)
end
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup
```bash
git clone https://github.com/dmmulroy/tsc.nvim.git
cd tsc.nvim

# Run tests
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Format code
stylua lua/

# Lint code
luacheck lua/
```

## 📄 License

This plugin is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [TypeScript](https://www.typescriptlang.org/) team for the excellent compiler
- [Neovim](https://neovim.io/) community for the amazing editor
- All contributors and users who make this project better

---

**tsc.nvim 3.0** - Bringing scalable TypeScript integration to Neovim 🚀
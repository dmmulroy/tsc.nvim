---@class DefaultConfig
local M = {}

---Default configuration for tsc.nvim 3.0
---@type table
M.DEFAULT_CONFIG = {
  -- Core execution mode
  mode = "project", -- 'project' | 'package' | 'monorepo'

  -- Project discovery configuration
  discovery = {
    root_markers = { "package.json", "tsconfig.json" },
    tsconfig_name = "tsconfig.json",
    max_projects = 0, -- 0 = no limit (use batch system instead)
    exclude_patterns = { "node_modules", ".git", "dist", "build" },
  },

  -- TypeScript execution
  typescript = {
    bin = nil, -- Auto-detect if nil
    flags = "--noEmit", -- Simple string flags
    timeout = 30000, -- 30 second timeout
    working_dir = nil, -- Auto-detect project root
  },

  -- Output configuration
  output = {
    auto_open = true, -- Auto-open quickfix on errors
    auto_close = true, -- Auto-close quickfix when no errors
  },

  -- Batch processing configuration
  batch = {
    enabled = true, -- Enable queue-based batch processing
    size = 5, -- Number of projects per batch
    concurrency = 3, -- Maximum concurrent processes
    strategy = "size", -- 'priority' | 'size' | 'alpha' | 'fifo'
    progressive_results = true, -- Report results as they complete
    retry_failed = true, -- Retry failed projects
    retry_count = 2, -- Maximum retry attempts
    timeout_per_project = 30000, -- Timeout per project in milliseconds
  },

  -- Plugin configuration (extensible)
  plugins = {
    quickfix = { enabled = true },
    watch = { enabled = false },
    diagnostics = { enabled = false },
    better_messages = { enabled = true },
  },
}

---Get the default configuration
---@return table
function M.get_defaults()
  return vim.deepcopy(M.DEFAULT_CONFIG)
end

---Get default configuration for a specific section
---@param section string Configuration section name
---@return table|nil
function M.get_section_defaults(section)
  if M.DEFAULT_CONFIG[section] then
    return vim.deepcopy(M.DEFAULT_CONFIG[section])
  end
  return nil
end

return M

---@class DiagnosticsPlugin
---@field name string Plugin name
---@field version string Plugin version
---@field dependencies string[] Plugin dependencies
---@field enabled boolean Whether plugin is enabled
---@field private _events Events Event system
---@field private _config table Plugin configuration
---@field private _namespace number Diagnostic namespace ID
---@field private _diagnostics table<string, table[]> Diagnostics by buffer
local DiagnosticsPlugin = {}

---Create new diagnostics plugin
---@param events Events Event system
---@param config table Plugin configuration
---@return DiagnosticsPlugin
function DiagnosticsPlugin.new(events, config)
  local self = {
    name = 'diagnostics',
    version = '3.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      enabled = false,
      namespace = 'tsc',
      virtual_text = {
        enabled = true,
        prefix = '■',
        spacing = 4,
        severity_limit = vim.diagnostic.severity.HINT,
      },
      signs = {
        enabled = true,
        priority = 10,
      },
      underline = {
        enabled = true,
        severity_limit = vim.diagnostic.severity.WARN,
      },
      update_in_insert = false,
      severity_sort = true,
      float = {
        enabled = true,
        source = 'always',
        border = 'rounded',
        focusable = false,
      },
    }, config or {}),
    _namespace = nil,
    _diagnostics = {},
  }
  
  return setmetatable(self, { __index = DiagnosticsPlugin })
end

---Initialize plugin
function DiagnosticsPlugin:setup()
  if not self._config.enabled then
    return
  end
  
  -- Create diagnostic namespace
  self._namespace = vim.api.nvim_create_namespace('tsc_' .. self._config.namespace)
  
  -- Configure diagnostic display
  self:_configure_diagnostics()
  
  -- Subscribe to completion events
  self._events:on('tsc.completed', function(data)
    self:_handle_completion(data)
  end)
  
  -- Subscribe to start events to optionally clear diagnostics
  self._events:on('tsc.started', function(data)
    if self._config.clear_on_start then
      self:clear_all()
    end
  end)
  
  -- Subscribe to stop events
  self._events:on('tsc.stopped', function(data)
    if self._config.clear_on_stop then
      self:clear_all()
    end
  end)
  
  -- Subscribe to file change events for clearing
  self._events:on('tsc.file_changed', function(data)
    if self._config.clear_on_change then
      self:clear_buffer(data.file)
    end
  end)
end

---Configure diagnostic display options
function DiagnosticsPlugin:_configure_diagnostics()
  local config = {
    virtual_text = self._config.virtual_text.enabled and self._config.virtual_text or false,
    signs = self._config.signs.enabled and self._config.signs or false,
    underline = self._config.underline.enabled and self._config.underline or false,
    update_in_insert = self._config.update_in_insert,
    severity_sort = self._config.severity_sort,
    float = self._config.float.enabled and self._config.float or false,
  }
  
  -- Set namespace-specific configuration
  vim.diagnostic.config(config, self._namespace)
  
  -- Define signs if enabled
  if self._config.signs.enabled then
    self:_define_signs()
  end
end

---Define diagnostic signs
function DiagnosticsPlugin:_define_signs()
  local signs = {
    { name = 'DiagnosticSignError', text = '✘', texthl = 'DiagnosticSignError' },
    { name = 'DiagnosticSignWarn',  text = '▲', texthl = 'DiagnosticSignWarn' },
    { name = 'DiagnosticSignInfo',  text = '●', texthl = 'DiagnosticSignInfo' },
    { name = 'DiagnosticSignHint',  text = '○', texthl = 'DiagnosticSignHint' },
  }
  
  for _, sign in ipairs(signs) do
    vim.fn.sign_define(sign.name, {
      text = sign.text,
      texthl = sign.texthl,
      numhl = sign.texthl,
    })
  end
end

---Handle completion event
---@param data table Completion data
function DiagnosticsPlugin:_handle_completion(data)
  -- Clear existing diagnostics
  self:clear_all()
  
  local errors = data.errors or {}
  local diagnostics_by_file = {}
  
  -- Group errors by file
  for _, error in ipairs(errors) do
    local filename = error.filename
    if not diagnostics_by_file[filename] then
      diagnostics_by_file[filename] = {}
    end
    
    local diagnostic = self:_error_to_diagnostic(error)
    table.insert(diagnostics_by_file[filename], diagnostic)
  end
  
  -- Set diagnostics for each file
  for filename, diagnostics in pairs(diagnostics_by_file) do
    self:set_buffer_diagnostics(filename, diagnostics)
  end
end

---Convert TypeScript error to diagnostic
---@param error table TypeScript error
---@return table LSP diagnostic
function DiagnosticsPlugin:_error_to_diagnostic(error)
  -- Parse error code and severity
  local code, severity = self:_parse_error_info(error.text)
  
  return {
    lnum = error.lnum - 1,  -- Convert to 0-based
    col = error.col - 1,    -- Convert to 0-based
    end_lnum = error.lnum - 1,
    end_col = error.col - 1,
    severity = severity,
    message = error.text,
    source = 'tsc',
    code = code,
  }
end

---Parse error information from message
---@param message string Error message
---@return string|nil, number Error code and severity
function DiagnosticsPlugin:_parse_error_info(message)
  -- Extract TypeScript error code
  local code = message:match('TS(%d+):')
  if code then
    code = 'TS' .. code
  end
  
  -- Determine severity based on error code or message
  local severity = vim.diagnostic.severity.ERROR
  
  if code then
    local code_num = tonumber(code:sub(3))
    if code_num then
      -- Warning codes (suggestions)
      if code_num >= 6133 and code_num <= 6140 then
        severity = vim.diagnostic.severity.WARN
      -- Info codes
      elseif code_num >= 7000 and code_num <= 7999 then
        severity = vim.diagnostic.severity.INFO
      -- Hint codes
      elseif code_num >= 80000 then
        severity = vim.diagnostic.severity.HINT
      end
    end
  end
  
  -- Check for warning keywords in message
  if message:lower():match('warning') then
    severity = vim.diagnostic.severity.WARN
  end
  
  return code, severity
end

---Set diagnostics for a buffer
---@param filename string File path
---@param diagnostics table[] Diagnostics to set
function DiagnosticsPlugin:set_buffer_diagnostics(filename, diagnostics)
  -- Get or create buffer
  local bufnr = self:_get_or_create_buffer(filename)
  if not bufnr then
    return
  end
  
  -- Store diagnostics
  self._diagnostics[filename] = diagnostics
  
  -- Set diagnostics
  vim.diagnostic.set(self._namespace, bufnr, diagnostics, {})
end

---Get or create buffer for file
---@param filename string File path
---@return number|nil Buffer number
function DiagnosticsPlugin:_get_or_create_buffer(filename)
  -- Check if file exists
  if vim.fn.filereadable(filename) ~= 1 then
    return nil
  end
  
  -- Find existing buffer
  local bufnr = vim.fn.bufnr(filename)
  
  -- Create buffer if it doesn't exist but don't load it
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(filename)
  end
  
  return bufnr
end

---Clear diagnostics for a buffer
---@param filename string File path
function DiagnosticsPlugin:clear_buffer(filename)
  local bufnr = vim.fn.bufnr(filename)
  if bufnr ~= -1 then
    vim.diagnostic.reset(self._namespace, bufnr)
  end
  
  self._diagnostics[filename] = nil
end

---Clear all diagnostics
function DiagnosticsPlugin:clear_all()
  vim.diagnostic.reset(self._namespace)
  self._diagnostics = {}
end

---Get diagnostics for a buffer
---@param filename string File path
---@return table[] Diagnostics
function DiagnosticsPlugin:get_buffer_diagnostics(filename)
  return self._diagnostics[filename] or {}
end

---Get all diagnostics
---@return table<string, table[]> All diagnostics by file
function DiagnosticsPlugin:get_all_diagnostics()
  return vim.deepcopy(self._diagnostics)
end

---Refresh diagnostics display
function DiagnosticsPlugin:refresh()
  for filename, diagnostics in pairs(self._diagnostics) do
    self:set_buffer_diagnostics(filename, diagnostics)
  end
end

---Show diagnostics in floating window
---@param opts? table Options for floating window
function DiagnosticsPlugin:show_float(opts)
  opts = opts or {}
  opts.namespace = self._namespace
  vim.diagnostic.open_float(opts)
end

---Jump to next diagnostic
---@param opts? table Navigation options
function DiagnosticsPlugin:goto_next(opts)
  opts = opts or {}
  opts.namespace = self._namespace
  vim.diagnostic.goto_next(opts)
end

---Jump to previous diagnostic
---@param opts? table Navigation options
function DiagnosticsPlugin:goto_prev(opts)
  opts = opts or {}
  opts.namespace = self._namespace
  vim.diagnostic.goto_prev(opts)
end

---Set diagnostic list (quickfix or location list)
---@param opts? table List options
function DiagnosticsPlugin:set_list(opts)
  opts = opts or {}
  opts.namespace = self._namespace
  vim.diagnostic.setqflist(opts)
end

---Get plugin status
---@return table Status information
function DiagnosticsPlugin:get_status()
  local total_diagnostics = 0
  local files_with_diagnostics = 0
  local severity_counts = {
    [vim.diagnostic.severity.ERROR] = 0,
    [vim.diagnostic.severity.WARN] = 0,
    [vim.diagnostic.severity.INFO] = 0,
    [vim.diagnostic.severity.HINT] = 0,
  }
  
  for filename, diagnostics in pairs(self._diagnostics) do
    files_with_diagnostics = files_with_diagnostics + 1
    total_diagnostics = total_diagnostics + #diagnostics
    
    for _, diagnostic in ipairs(diagnostics) do
      local severity = diagnostic.severity or vim.diagnostic.severity.ERROR
      severity_counts[severity] = severity_counts[severity] + 1
    end
  end
  
  return {
    namespace = self._namespace,
    total_diagnostics = total_diagnostics,
    files_with_diagnostics = files_with_diagnostics,
    severity_counts = {
      error = severity_counts[vim.diagnostic.severity.ERROR],
      warn = severity_counts[vim.diagnostic.severity.WARN],
      info = severity_counts[vim.diagnostic.severity.INFO],
      hint = severity_counts[vim.diagnostic.severity.HINT],
    },
    config = self._config,
  }
end

---Update plugin configuration
---@param new_config table New configuration
function DiagnosticsPlugin:update_config(new_config)
  self._config = vim.tbl_deep_extend('force', self._config, new_config)
  
  -- Reconfigure diagnostics
  self:_configure_diagnostics()
  
  -- Refresh display
  self:refresh()
end

---Clean up plugin resources
function DiagnosticsPlugin:cleanup()
  self:clear_all()
  
  -- Reset namespace configuration
  vim.diagnostic.config({}, self._namespace)
end

return DiagnosticsPlugin
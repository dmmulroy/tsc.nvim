---@class QuickfixPlugin
---@field name string Plugin name
---@field version string Plugin version
---@field dependencies string[] Plugin dependencies
---@field enabled boolean Whether plugin is enabled
---@field private _events Events Event system
---@field private _config table Plugin configuration
local QuickfixPlugin = {}

---Create new quickfix plugin
---@param events Events Event system
---@param config table Plugin configuration
---@return QuickfixPlugin
function QuickfixPlugin.new(events, config)
  local self = {
    name = 'quickfix',
    version = '3.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      auto_open = true,
      auto_close = true,
      auto_focus = false,
      title = 'TSC',
      max_height = 10,
      min_height = 3,
    }, config or {}),
  }
  
  return setmetatable(self, { __index = QuickfixPlugin })
end

---Initialize plugin
function QuickfixPlugin:setup()
  -- Subscribe to completion events
  self._events:on('tsc.completed', function(data)
    self:_handle_completion(data)
  end)
  
  -- Subscribe to start events to optionally clear quickfix
  self._events:on('tsc.started', function(data)
    if self._config.clear_on_start then
      self:clear()
    end
  end)
  
  -- Subscribe to stop events
  self._events:on('tsc.stopped', function(data)
    if self._config.clear_on_stop then
      self:clear()
    end
  end)
end

---Handle completion event
---@param data table Completion data
function QuickfixPlugin:_handle_completion(data)
  local errors = data.errors or {}
  
  -- Format errors for quickfix
  local qf_items = {}
  for _, error in ipairs(errors) do
    table.insert(qf_items, {
      filename = error.filename,
      lnum = error.lnum,
      col = error.col,
      text = error.text,
      type = error.type,
      valid = error.valid or 1,
    })
  end
  
  -- Update quickfix list
  self:update(qf_items)
  
  -- Handle auto open/close
  if #qf_items > 0 then
    if self._config.auto_open then
      self:open()
    end
  else
    if self._config.auto_close then
      self:close()
    end
  end
end

---Update quickfix list
---@param items table[] Quickfix items
function QuickfixPlugin:update(items)
  vim.fn.setqflist({}, 'r', {
    title = self._config.title,
    items = items,
  })
end

---Open quickfix list
function QuickfixPlugin:open()
  local win = vim.api.nvim_get_current_win()
  
  -- Calculate height
  local qf_size = vim.fn.len(vim.fn.getqflist())
  local height = math.max(
    self._config.min_height,
    math.min(self._config.max_height, qf_size)
  )
  
  -- Open quickfix
  vim.cmd(string.format('copen %d', height))
  
  -- Handle auto focus
  if not self._config.auto_focus then
    vim.api.nvim_set_current_win(win)
  end
end

---Close quickfix list
function QuickfixPlugin:close()
  vim.cmd('cclose')
end

---Clear quickfix list
function QuickfixPlugin:clear()
  vim.fn.setqflist({}, 'r', { title = self._config.title })
end

---Toggle quickfix list
function QuickfixPlugin:toggle()
  -- Check if quickfix is open
  local qf_winid = vim.fn.getqflist({winid = 0}).winid
  
  if qf_winid > 0 then
    self:close()
  else
    self:open()
  end
end

---Get quickfix list contents
---@return table[] Quickfix items
function QuickfixPlugin:get_items()
  return vim.fn.getqflist()
end

---Get quickfix list info
---@return table Quickfix info
function QuickfixPlugin:get_info()
  return vim.fn.getqflist({
    size = 0,
    winid = 0,
    title = 0,
    nr = 0,
  })
end

---Check if quickfix is open
---@return boolean
function QuickfixPlugin:is_open()
  local qf_winid = vim.fn.getqflist({winid = 0}).winid
  return qf_winid > 0
end

---Get plugin status
---@return table Status information
function QuickfixPlugin:get_status()
  local info = self:get_info()
  
  return {
    is_open = self:is_open(),
    item_count = info.size,
    title = info.title,
    window_id = info.winid,
    config = self._config,
  }
end

---Update plugin configuration
---@param new_config table New configuration
function QuickfixPlugin:update_config(new_config)
  self._config = vim.tbl_deep_extend('force', self._config, new_config)
end

---Clean up plugin resources
function QuickfixPlugin:cleanup()
  -- Clear quickfix list
  self:clear()
  
  -- No other cleanup needed as event listeners are automatically removed
end

return QuickfixPlugin
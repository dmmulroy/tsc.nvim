---@class BetterMessagesPlugin
---@field name string Plugin name
---@field version string Plugin version
---@field dependencies string[] Plugin dependencies
---@field enabled boolean Whether plugin is enabled
---@field private _events Events Event system
---@field private _config table Plugin configuration
---@field private _templates table<string, table> Cached message templates
---@field private _template_dir string Template directory path
local BetterMessagesPlugin = {}

-- Regex pattern for capturing numbered parameters like {0}, {1}, etc.
local PARAMETER_REGEX = "({%d})"

---Create new better messages plugin
---@param events Events Event system
---@param config table Plugin configuration
---@return BetterMessagesPlugin
function BetterMessagesPlugin.new(events, config)
  local self = {
    name = 'better_messages',
    version = '3.0.0',
    dependencies = {},
    enabled = true,
    _events = events,
    _config = vim.tbl_deep_extend('force', {
      enabled = true,
      template_dir = nil, -- Auto-detect if nil
      cache_templates = true,
      strip_markdown_links = true,
      custom_templates = {},
      fallback_to_original = true,
    }, config or {}),
    _templates = {},
    _template_dir = nil,
  }
  
  -- Initialize template directory
  self._template_dir = self._config.template_dir or self:_find_template_dir()
  
  return setmetatable(self, { __index = BetterMessagesPlugin })
end

---Initialize plugin
function BetterMessagesPlugin:setup()
  if not self._config.enabled then
    return
  end
  
  -- Subscribe to output parsed events
  self._events:on('tsc.output_parsed', function(data)
    self:_handle_output_parsed(data)
  end)
  
  -- Load custom templates if provided
  if self._config.custom_templates then
    self:_load_custom_templates()
  end
end

---Find template directory
---@return string Template directory path
function BetterMessagesPlugin:_find_template_dir()
  local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':p:h:h')
  return plugin_path .. '/better-messages'
end

---Handle output parsed event
---@param data table Event data
function BetterMessagesPlugin:_handle_output_parsed(data)
  if not data.parsed or not data.parsed.errors then
    return
  end
  
  -- Enhance each error message
  for _, error in ipairs(data.parsed.errors) do
    local enhanced_text = self:translate(error.text)
    if enhanced_text ~= error.text then
      error.original_text = error.text
      error.text = enhanced_text
      error.enhanced = true
    end
  end
end

---Translate an error message to a better version
---@param message string Original error message
---@return string Enhanced error message
function BetterMessagesPlugin:translate(message)
  -- Extract error number and message
  local error_num, original_message = message:match("^.*TS(%d+):%s(.*)")
  if not error_num then
    return message
  end
  
  -- Get template (from cache or file)
  local template = self:_get_template(error_num)
  if not template then
    return message
  end
  
  -- Apply template transformation
  local enhanced = self:_apply_template(original_message, template)
  
  -- Strip markdown links if configured
  if self._config.strip_markdown_links then
    enhanced = self:_strip_markdown_links(enhanced)
  end
  
  return "TS" .. error_num .. ": " .. enhanced
end

---Get template for error number
---@param error_num string Error number
---@return table|nil Template data
function BetterMessagesPlugin:_get_template(error_num)
  -- Check cache first
  if self._config.cache_templates and self._templates[error_num] then
    return self._templates[error_num]
  end
  
  -- Check custom templates
  if self._config.custom_templates[error_num] then
    return self._config.custom_templates[error_num]
  end
  
  -- Load from file
  local template = self:_load_template_file(error_num)
  
  -- Cache if enabled
  if template and self._config.cache_templates then
    self._templates[error_num] = template
  end
  
  return template
end

---Load template from markdown file
---@param error_num string Error number
---@return table|nil Template data
function BetterMessagesPlugin:_load_template_file(error_num)
  local filename = self._template_dir .. '/' .. error_num .. '.md'
  local file = io.open(filename, 'r')
  
  if not file then
    return nil
  end
  
  local content = file:read('*all')
  file:close()
  
  return self:_parse_template(content)
end

---Parse template from markdown content
---@param content string Markdown content
---@return table Template data
function BetterMessagesPlugin:_parse_template(content)
  -- Remove leading and trailing '---'
  local trimmed = content:gsub("^%-%-%-%s*", ""):gsub("%s*%-%-%-$", "")
  
  -- Split at the '---' separator
  local original_content, better_content = trimmed:match("^(.-)%s*%-%-%-%s*(.-)$")
  
  if not original_content or not better_content then
    return nil
  end
  
  -- Extract original template
  local original = original_content:gsub('^original:%s*"(.-)"%s*$', "%1")
  
  -- Clean up better content
  local better = better_content:gsub("^%s*(.-)%s*$", "%1")
  
  return {
    original = original,
    better = better,
  }
end

---Apply template to message
---@param message string Original message
---@param template table Template data
---@return string Enhanced message
function BetterMessagesPlugin:_apply_template(message, template)
  -- Extract parameters from original template
  local params = self:_get_params(template.original)
  
  -- Extract matches from message
  local matches = self:_get_matches(message)
  
  -- If no parameters or mismatch, return template as-is
  if #params == 0 then
    return template.better
  end
  
  if #params ~= #matches then
    return self._config.fallback_to_original and message or template.better
  end
  
  -- Replace parameters in better template
  local enhanced = template.better
  for i = 1, #params do
    enhanced = enhanced:gsub(params[i], matches[i])
  end
  
  return enhanced
end

---Extract parameter placeholders from template
---@param template string Template string
---@return table List of parameters
function BetterMessagesPlugin:_get_params(template)
  local params = {}
  for param in template:gmatch(PARAMETER_REGEX) do
    table.insert(params, param)
  end
  return params
end

---Extract quoted strings from message
---@param message string Message string
---@return table List of matches
function BetterMessagesPlugin:_get_matches(message)
  local matches = {}
  for match in message:gmatch("'(.-)'") do
    table.insert(matches, match)
  end
  return matches
end

---Strip markdown links from text
---@param text string Text with potential markdown links
---@return string Text without markdown links
function BetterMessagesPlugin:_strip_markdown_links(text)
  -- Replace [text](url) with just text
  text = text:gsub('%[([^%]]+)%]%(.-%)' , '%1')
  
  -- Replace [text][ref] with just text
  text = text:gsub('%[([^%]]+)%]%[.-]' , '%1')
  
  return text
end

---Load custom templates
function BetterMessagesPlugin:_load_custom_templates()
  for error_num, template in pairs(self._config.custom_templates) do
    if type(template) == 'string' then
      -- Simple string replacement
      self._config.custom_templates[error_num] = {
        original = '',
        better = template,
      }
    elseif type(template) == 'table' and template.original and template.better then
      -- Already in correct format
    else
      vim.notify(
        string.format('Invalid custom template for TS%s', error_num),
        vim.log.levels.WARN
      )
      self._config.custom_templates[error_num] = nil
    end
  end
end

---Add custom template
---@param error_num string Error number
---@param template string|table Template (string or {original, better})
function BetterMessagesPlugin:add_custom_template(error_num, template)
  if type(template) == 'string' then
    self._config.custom_templates[error_num] = {
      original = '',
      better = template,
    }
  else
    self._config.custom_templates[error_num] = template
  end
  
  -- Clear cache for this error
  if self._config.cache_templates then
    self._templates[error_num] = nil
  end
end

---Clear template cache
function BetterMessagesPlugin:clear_cache()
  self._templates = {}
end

---Get template statistics
---@return table Statistics
function BetterMessagesPlugin:get_stats()
  local stats = {
    cached_templates = vim.tbl_count(self._templates),
    custom_templates = vim.tbl_count(self._config.custom_templates),
    template_dir = self._template_dir,
  }
  
  -- Count available template files
  local template_files = vim.fn.glob(self._template_dir .. '/*.md', false, true)
  stats.available_templates = #template_files
  
  return stats
end

---Get plugin status
---@return table Status information
function BetterMessagesPlugin:get_status()
  return {
    enabled = self._config.enabled,
    stats = self:get_stats(),
    config = self._config,
  }
end

---Update plugin configuration
---@param new_config table New configuration
function BetterMessagesPlugin:update_config(new_config)
  self._config = vim.tbl_deep_extend('force', self._config, new_config)
  
  -- Update template directory if changed
  if new_config.template_dir then
    self._template_dir = new_config.template_dir
  end
  
  -- Clear cache if caching disabled
  if not self._config.cache_templates then
    self:clear_cache()
  end
  
  -- Reload custom templates
  if new_config.custom_templates then
    self:_load_custom_templates()
  end
end

---Clean up plugin resources
function BetterMessagesPlugin:cleanup()
  self:clear_cache()
end

return BetterMessagesPlugin
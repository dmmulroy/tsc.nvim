---@class ValidateUtils
local M = {}

---@class ValidationResult
---@field valid boolean Whether validation passed
---@field errors string[] List of validation errors
---@field warnings string[] List of validation warnings

---Type checking functions
M.type = {
  ---Check if value is string
  ---@param value any Value to check
  ---@return boolean
  is_string = function(value)
    return type(value) == 'string'
  end,
  
  ---Check if value is number
  ---@param value any Value to check
  ---@return boolean
  is_number = function(value)
    return type(value) == 'number'
  end,
  
  ---Check if value is boolean
  ---@param value any Value to check
  ---@return boolean
  is_boolean = function(value)
    return type(value) == 'boolean'
  end,
  
  ---Check if value is table
  ---@param value any Value to check
  ---@return boolean
  is_table = function(value)
    return type(value) == 'table'
  end,
  
  ---Check if value is function
  ---@param value any Value to check
  ---@return boolean
  is_function = function(value)
    return type(value) == 'function'
  end,
  
  ---Check if value is nil
  ---@param value any Value to check
  ---@return boolean
  is_nil = function(value)
    return value == nil
  end,
  
  ---Check if value is array
  ---@param value any Value to check
  ---@return boolean
  is_array = function(value)
    if type(value) ~= 'table' then
      return false
    end
    
    local count = 0
    for _ in pairs(value) do
      count = count + 1
    end
    
    for i = 1, count do
      if value[i] == nil then
        return false
      end
    end
    
    return true
  end,
  
  ---Check if value is empty
  ---@param value any Value to check
  ---@return boolean
  is_empty = function(value)
    if value == nil then
      return true
    elseif type(value) == 'string' then
      return value == ''
    elseif type(value) == 'table' then
      return next(value) == nil
    end
    return false
  end,
}

---Create a new validator
---@return table Validator instance
function M.validator()
  local validator = {
    errors = {},
    warnings = {},
  }
  
  ---Add error
  ---@param message string Error message
  function validator:error(message)
    table.insert(self.errors, message)
  end
  
  ---Add warning
  ---@param message string Warning message
  function validator:warning(message)
    table.insert(self.warnings, message)
  end
  
  ---Check if valid
  ---@return boolean
  function validator:is_valid()
    return #self.errors == 0
  end
  
  ---Get result
  ---@return ValidationResult
  function validator:result()
    return {
      valid = self:is_valid(),
      errors = vim.deepcopy(self.errors),
      warnings = vim.deepcopy(self.warnings),
    }
  end
  
  ---Reset validator
  function validator:reset()
    self.errors = {}
    self.warnings = {}
  end
  
  return validator
end

---Validate value against schema
---@param value any Value to validate
---@param schema table Schema definition
---@param path? string Current path in object
---@return ValidationResult
function M.validate_schema(value, schema, path)
  path = path or 'root'
  local validator = M.validator()
  
  -- Check type
  if schema.type then
    local expected_type = schema.type
    local actual_type = type(value)
    
    -- Special handling for array type
    if expected_type == 'array' then
      if not M.type.is_array(value) then
        validator:error(string.format('%s: expected array, got %s', path, actual_type))
      end
    elseif actual_type ~= expected_type then
      validator:error(string.format('%s: expected %s, got %s', path, expected_type, actual_type))
    end
  end
  
  -- Check enum values
  if schema.enum and not validator:is_valid() then
    local found = false
    for _, allowed in ipairs(schema.enum) do
      if value == allowed then
        found = true
        break
      end
    end
    if not found then
      validator:error(string.format('%s: value must be one of: %s', path, table.concat(schema.enum, ', ')))
    end
  end
  
  -- Check string constraints
  if type(value) == 'string' then
    if schema.min_length and #value < schema.min_length then
      validator:error(string.format('%s: string must be at least %d characters', path, schema.min_length))
    end
    if schema.max_length and #value > schema.max_length then
      validator:error(string.format('%s: string must be at most %d characters', path, schema.max_length))
    end
    if schema.pattern and not value:match(schema.pattern) then
      validator:error(string.format('%s: string does not match pattern: %s', path, schema.pattern))
    end
  end
  
  -- Check number constraints
  if type(value) == 'number' then
    if schema.minimum and value < schema.minimum then
      validator:error(string.format('%s: number must be at least %g', path, schema.minimum))
    end
    if schema.maximum and value > schema.maximum then
      validator:error(string.format('%s: number must be at most %g', path, schema.maximum))
    end
    if schema.integer and value ~= math.floor(value) then
      validator:error(string.format('%s: number must be an integer', path))
    end
  end
  
  -- Check array constraints
  if M.type.is_array(value) then
    if schema.min_items and #value < schema.min_items then
      validator:error(string.format('%s: array must have at least %d items', path, schema.min_items))
    end
    if schema.max_items and #value > schema.max_items then
      validator:error(string.format('%s: array must have at most %d items', path, schema.max_items))
    end
    
    -- Validate array items
    if schema.items then
      for i, item in ipairs(value) do
        local item_result = M.validate_schema(item, schema.items, path .. '[' .. i .. ']')
        for _, err in ipairs(item_result.errors) do
          validator:error(err)
        end
        for _, warn in ipairs(item_result.warnings) do
          validator:warning(warn)
        end
      end
    end
  end
  
  -- Check object constraints
  if type(value) == 'table' and not M.type.is_array(value) then
    -- Check required properties
    if schema.required then
      for _, prop in ipairs(schema.required) do
        if value[prop] == nil then
          validator:error(string.format('%s.%s: required property missing', path, prop))
        end
      end
    end
    
    -- Validate properties
    if schema.properties then
      for prop, prop_schema in pairs(schema.properties) do
        if value[prop] ~= nil then
          local prop_result = M.validate_schema(value[prop], prop_schema, path .. '.' .. prop)
          for _, err in ipairs(prop_result.errors) do
            validator:error(err)
          end
          for _, warn in ipairs(prop_result.warnings) do
            validator:warning(warn)
          end
        end
      end
    end
    
    -- Check additional properties
    if schema.additional_properties == false then
      for prop, _ in pairs(value) do
        if not schema.properties or not schema.properties[prop] then
          validator:warning(string.format('%s.%s: unexpected property', path, prop))
        end
      end
    elseif type(schema.additional_properties) == 'table' then
      -- Validate additional properties against schema
      for prop, prop_value in pairs(value) do
        if not schema.properties or not schema.properties[prop] then
          local prop_result = M.validate_schema(prop_value, schema.additional_properties, path .. '.' .. prop)
          for _, err in ipairs(prop_result.errors) do
            validator:error(err)
          end
          for _, warn in ipairs(prop_result.warnings) do
            validator:warning(warn)
          end
        end
      end
    end
  end
  
  -- Custom validation function
  if schema.validate and type(schema.validate) == 'function' then
    local valid, message = schema.validate(value)
    if not valid then
      validator:error(string.format('%s: %s', path, message or 'custom validation failed'))
    end
  end
  
  return validator:result()
end

---Assert condition with message
---@param condition boolean Condition to check
---@param message string Error message
---@param level? number Stack level for error
function M.assert(condition, message, level)
  if not condition then
    error(message, (level or 1) + 1)
  end
end

---Assert type with message
---@param value any Value to check
---@param expected_type string Expected type
---@param name? string Variable name for error message
function M.assert_type(value, expected_type, name)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    local message = string.format(
      '%s: expected %s, got %s',
      name or 'value',
      expected_type,
      actual_type
    )
    error(message, 2)
  end
end

---Assert argument types
---@param args table Arguments to validate
---@param specs table Type specifications
function M.assert_args(args, specs)
  for i, spec in ipairs(specs) do
    local value = args[i]
    local expected_type = spec.type
    local name = spec.name or ('argument ' .. i)
    local optional = spec.optional
    
    if value == nil and optional then
      goto continue
    end
    
    if type(expected_type) == 'string' then
      M.assert_type(value, expected_type, name)
    elseif type(expected_type) == 'table' then
      -- Multiple allowed types
      local valid = false
      for _, t in ipairs(expected_type) do
        if type(value) == t then
          valid = true
          break
        end
      end
      if not valid then
        error(string.format(
          '%s: expected one of %s, got %s',
          name,
          table.concat(expected_type, ', '),
          type(value)
        ), 2)
      end
    end
    
    ::continue::
  end
end

---Create schema builder
---@return table Schema builder
function M.schema()
  local builder = {}
  
  function builder.string(opts)
    return vim.tbl_extend('force', { type = 'string' }, opts or {})
  end
  
  function builder.number(opts)
    return vim.tbl_extend('force', { type = 'number' }, opts or {})
  end
  
  function builder.boolean(opts)
    return vim.tbl_extend('force', { type = 'boolean' }, opts or {})
  end
  
  function builder.array(items, opts)
    return vim.tbl_extend('force', {
      type = 'array',
      items = items,
    }, opts or {})
  end
  
  function builder.object(properties, opts)
    return vim.tbl_extend('force', {
      type = 'object',
      properties = properties,
    }, opts or {})
  end
  
  function builder.enum(values, opts)
    return vim.tbl_extend('force', {
      enum = values,
    }, opts or {})
  end
  
  function builder.optional(schema)
    schema.optional = true
    return schema
  end
  
  function builder.required(schema)
    schema.optional = false
    return schema
  end
  
  return builder
end

---Validate plugin configuration
---@param config table Plugin configuration
---@param spec table Plugin specification
---@return ValidationResult
function M.validate_plugin_config(config, spec)
  local validator = M.validator()
  
  -- Check plugin name
  if not spec.name or type(spec.name) ~= 'string' then
    validator:error('Plugin specification must have a name')
  end
  
  -- Check version
  if not spec.version or type(spec.version) ~= 'string' then
    validator:error('Plugin specification must have a version')
  end
  
  -- Validate configuration if schema provided
  if spec.config_schema then
    local config_result = M.validate_schema(config, spec.config_schema)
    for _, err in ipairs(config_result.errors) do
      validator:error(err)
    end
    for _, warn in ipairs(config_result.warnings) do
      validator:warning(warn)
    end
  end
  
  -- Check required methods
  local required_methods = {'setup', 'cleanup'}
  for _, method in ipairs(required_methods) do
    if spec[method] and type(spec[method]) ~= 'function' then
      validator:error(string.format('Plugin must have %s method', method))
    end
  end
  
  return validator:result()
end

---Create runtime assertion helper
---@param name string Assertion set name
---@return table Assertion functions
function M.runtime_assert(name)
  local asserts = {}
  local enabled = true
  
  ---Enable/disable assertions
  ---@param state boolean
  function asserts.set_enabled(state)
    enabled = state
  end
  
  ---Assert condition
  ---@param condition boolean
  ---@param message string
  function asserts.assert(condition, message)
    if enabled and not condition then
      error(string.format('[%s] %s', name, message), 2)
    end
  end
  
  ---Assert not nil
  ---@param value any
  ---@param name string
  function asserts.not_nil(value, name)
    if enabled and value == nil then
      error(string.format('[%s] %s must not be nil', name, name), 2)
    end
  end
  
  ---Assert type
  ---@param value any
  ---@param expected string
  ---@param name string
  function asserts.type(value, expected, name)
    if enabled then
      M.assert_type(value, expected, string.format('[%s] %s', name, name))
    end
  end
  
  return asserts
end

return M
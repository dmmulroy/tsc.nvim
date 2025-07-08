---@class ConfigSchema
local M = {}

---@class SchemaProperty
---@field type string
---@field enum? string[]
---@field description? string
---@field properties? table<string, SchemaProperty>
---@field items? SchemaProperty
---@field minimum? number
---@field additionalProperties? boolean

---@class Schema
---@field type string
---@field properties table<string, SchemaProperty>
---@field additionalProperties boolean

---Configuration schema for validation
---@type Schema
M.schema = {
  type = "object",
  properties = {
    mode = {
      type = "string",
      enum = { "project", "package", "monorepo" },
      description = "Type-checking scope",
    },

    discovery = {
      type = "object",
      properties = {
        root_markers = {
          type = "array",
          items = { type = "string" },
          description = "Files that indicate project root",
        },
        tsconfig_name = {
          type = "string",
          description = "TypeScript config file name",
        },
        max_projects = {
          type = "integer",
          minimum = 1,
          description = "Maximum projects to check in monorepo mode",
        },
        exclude_patterns = {
          type = "array",
          items = { type = "string" },
          description = "Patterns to exclude from project discovery",
        },
      },
      additionalProperties = false,
    },

    typescript = {
      type = "object",
      properties = {
        bin = {
          type = "string",
          description = "Path to TypeScript binary (auto-detected if nil)",
        },
        flags = {
          type = "string",
          description = "TypeScript compiler flags",
        },
        timeout = {
          type = "integer",
          minimum = 1000,
          description = "Process timeout in milliseconds",
        },
        working_dir = {
          type = "string",
          description = "Working directory (auto-detected if nil)",
        },
      },
      additionalProperties = false,
    },

    output = {
      type = "object",
      properties = {
        auto_open = {
          type = "boolean",
          description = "Auto-open quickfix on errors",
        },
        auto_close = {
          type = "boolean",
          description = "Auto-close quickfix when no errors",
        },
      },
      additionalProperties = false,
    },

    plugins = {
      type = "object",
      additionalProperties = true,
      description = "Plugin-specific configuration",
    },
  },
  additionalProperties = false,
}

---@class DiscoveryConfig
---@field root_markers? string[]
---@field tsconfig_name? string
---@field max_projects? number
---@field exclude_patterns? string[]

---@class TypeScriptConfig
---@field bin? string
---@field flags? string
---@field timeout? number
---@field working_dir? string

---@class OutputConfig
---@field auto_open? boolean
---@field auto_close? boolean

---@class PluginConfig
---@field enabled? boolean

---@class ConfigTable
---@field mode? string
---@field discovery? DiscoveryConfig
---@field typescript? TypeScriptConfig
---@field output? OutputConfig
---@field plugins? table<string, PluginConfig>

---Validate configuration against schema
---@param config ConfigTable Configuration to validate
---@return boolean success
---@return string? error_message
function M.validate(config)
  if type(config) ~= "table" then
    return false, "Configuration must be a table"
  end

  -- Validate mode
  if config.mode and not vim.tbl_contains({ "project", "package", "monorepo" }, config.mode) then
    return false, "mode must be one of: project, package, monorepo"
  end

  -- Validate discovery section
  if config.discovery then
    if type(config.discovery) ~= "table" then
      return false, "discovery must be a table"
    end

    if config.discovery.root_markers then
      if type(config.discovery.root_markers) ~= "table" then
        return false, "discovery.root_markers must be an array"
      end
      for i, marker in ipairs(config.discovery.root_markers) do
        if type(marker) ~= "string" then
          return false, string.format("discovery.root_markers[%d] must be a string", i)
        end
      end
    end

    if config.discovery.tsconfig_name and type(config.discovery.tsconfig_name) ~= "string" then
      return false, "discovery.tsconfig_name must be a string"
    end

    if config.discovery.max_projects then
      if type(config.discovery.max_projects) ~= "number" or config.discovery.max_projects < 1 then
        return false, "discovery.max_projects must be a positive integer"
      end
    end

    if config.discovery.exclude_patterns then
      if type(config.discovery.exclude_patterns) ~= "table" then
        return false, "discovery.exclude_patterns must be an array"
      end
      for i, pattern in ipairs(config.discovery.exclude_patterns) do
        if type(pattern) ~= "string" then
          return false, string.format("discovery.exclude_patterns[%d] must be a string", i)
        end
      end
    end
  end

  -- Validate typescript section
  if config.typescript then
    if type(config.typescript) ~= "table" then
      return false, "typescript must be a table"
    end

    if config.typescript.bin and type(config.typescript.bin) ~= "string" then
      return false, "typescript.bin must be a string"
    end

    if config.typescript.flags and type(config.typescript.flags) ~= "string" then
      return false, "typescript.flags must be a string"
    end

    if config.typescript.timeout then
      if type(config.typescript.timeout) ~= "number" or config.typescript.timeout < 1000 then
        return false, "typescript.timeout must be at least 1000ms"
      end
    end

    if config.typescript.working_dir and type(config.typescript.working_dir) ~= "string" then
      return false, "typescript.working_dir must be a string"
    end
  end

  -- Validate output section
  if config.output then
    if type(config.output) ~= "table" then
      return false, "output must be a table"
    end


    if config.output.auto_open ~= nil and type(config.output.auto_open) ~= "boolean" then
      return false, "output.auto_open must be a boolean"
    end

    if config.output.auto_close ~= nil and type(config.output.auto_close) ~= "boolean" then
      return false, "output.auto_close must be a boolean"
    end
  end

  -- Validate plugins section
  if config.plugins then
    if type(config.plugins) ~= "table" then
      return false, "plugins must be a table"
    end

    -- Basic validation for core plugins
    ---@type string[]
    local core_plugins = { "quickfix", "watch", "diagnostics", "better_messages" }
    for _, plugin_name in ipairs(core_plugins) do
      if config.plugins[plugin_name] then
        if type(config.plugins[plugin_name]) ~= "table" then
          return false, string.format("plugins.%s must be a table", plugin_name)
        end

        if config.plugins[plugin_name].enabled ~= nil and type(config.plugins[plugin_name].enabled) ~= "boolean" then
          return false, string.format("plugins.%s.enabled must be a boolean", plugin_name)
        end
      end
    end
  end

  return true, nil
end

---Get schema for a specific section
---@param section string Section name
---@return SchemaProperty|nil
function M.get_section_schema(section)
  if M.schema.properties and M.schema.properties[section] then
    ---@type SchemaProperty
    return vim.deepcopy(M.schema.properties[section])
  end
  return nil
end

return M

local fs = require("tsc.utils.fs")

---@class ProjectDiscovery
---@field private _config table Discovery configuration
---@field private _cache table Cache for discovered projects
local ProjectDiscovery = {}

---Create new project discovery instance
---@param config table Discovery configuration
---@return ProjectDiscovery
function ProjectDiscovery.new(config)
  local self = {
    _config = config,
    _cache = {},
  }
  return setmetatable(self, { __index = ProjectDiscovery })
end

---Find projects based on mode
---@param mode string Discovery mode ('project', 'package', 'monorepo')
---@return table[] List of discovered projects
function ProjectDiscovery:find_projects(mode)
  local cache_key = mode .. ":" .. fs.cwd()

  -- Check cache first
  if self._cache[cache_key] then
    return self._cache[cache_key]
  end

  local projects = {}

  if mode == "project" then
    projects = self:_find_single_project()
  elseif mode == "package" then
    projects = self:_find_package_in_monorepo()
  elseif mode == "monorepo" then
    projects = self:_find_monorepo_projects()
  else
    vim.notify(string.format("Unknown discovery mode: %s", mode), vim.log.levels.ERROR)
    return {}
  end

  -- Validate projects
  projects = self:_validate_projects(projects)

  -- Apply max_projects limit
  if #projects > self._config.max_projects then
    vim.notify(
      string.format("Too many projects found (%d), limiting to %d", #projects, self._config.max_projects),
      vim.log.levels.WARN
    )
    projects = vim.list_slice(projects, 1, self._config.max_projects)
  end

  -- Cache results
  self._cache[cache_key] = projects

  return projects
end

---Find single project (nearest tsconfig.json)
---@return table[] Single project or empty array
function ProjectDiscovery:_find_single_project()
  local tsconfig = fs.find_file_upward(self._config.tsconfig_name)

  if tsconfig and tsconfig ~= "" then
    local absolute_path = fs.absolute_path(tsconfig)
    return { {
      path = absolute_path,
      root = fs.dirname(absolute_path),
      type = "project",
    } }
  end

  return {}
end

---Find package within monorepo (nearest package.json with tsconfig.json)
---@return table[] Package project or empty array
function ProjectDiscovery:_find_package_in_monorepo()
  local package_json = fs.find_file_upward("package.json")

  if package_json and package_json ~= "" then
    local package_dir = fs.dirname(package_json)
    local tsconfig = fs.join(package_dir, self._config.tsconfig_name)

    if fs.file_exists(tsconfig) then
      return {
        {
          path = fs.absolute_path(tsconfig),
          root = package_dir,
          type = "package",
        },
      }
    end
  end

  return {}
end

---Find all projects in monorepo
---@return table[] All projects in monorepo
function ProjectDiscovery:_find_monorepo_projects()
  local pattern = "**/tsconfig*.json"
  local tsconfigs = fs.find_files_recursive(pattern, self._config.exclude_patterns)

  local projects = {}
  local seen_roots = {}

  for _, tsconfig in ipairs(tsconfigs) do
    local absolute_path = fs.absolute_path(tsconfig)
    local root = fs.dirname(absolute_path)

    -- Avoid duplicate roots
    if not seen_roots[root] then
      seen_roots[root] = true
      table.insert(projects, {
        path = absolute_path,
        root = root,
        type = "monorepo",
      })
    end
  end

  -- Sort by path for consistent ordering
  table.sort(projects, function(a, b)
    return a.path < b.path
  end)

  return projects
end

---Validate discovered projects
---@param projects table[] List of projects to validate
---@return table[] Validated projects
function ProjectDiscovery:_validate_projects(projects)
  local valid_projects = {}

  for _, project in ipairs(projects) do
    if self:_is_valid_project(project) then
      table.insert(valid_projects, project)
    else
      vim.notify(string.format("Invalid project: %s", project.path), vim.log.levels.WARN)
    end
  end

  return valid_projects
end

---Check if project is valid
---@param project table Project to validate
---@return boolean
function ProjectDiscovery:_is_valid_project(project)
  -- Check if tsconfig file exists and is readable
  if not fs.file_exists(project.path) then
    return false
  end

  -- Check if project root exists
  if not fs.dir_exists(project.root) then
    return false
  end

  -- Try to read tsconfig.json to ensure it's valid JSON
  local content = fs.read_file(project.path)
  if not content then
    return false
  end

  -- Basic JSON validation (just check if it starts with '{')
  local trimmed = content:gsub("^%s*", "")
  if not trimmed:match("^{") then
    return false
  end

  return true
end

---Get project root for a tsconfig path
---@param tsconfig_path string Path to tsconfig.json
---@return string|nil Project root directory
function ProjectDiscovery:get_project_root(tsconfig_path)
  if tsconfig_path then
    return fs.dirname(tsconfig_path)
  end
  return nil
end

---Find nearest root marker
---@param markers string[] List of root markers to look for
---@param start_dir? string Starting directory
---@return string|nil Found root directory
function ProjectDiscovery:find_root_by_markers(markers, start_dir)
  start_dir = start_dir or fs.cwd()

  for _, marker in ipairs(markers) do
    local found = fs.find_file_upward(marker, start_dir)
    if found and found ~= "" then
      return fs.dirname(found)
    end
  end

  return nil
end

---Clear discovery cache
function ProjectDiscovery:clear_cache()
  self._cache = {}
end

---Get cached results
---@return table Cache contents
function ProjectDiscovery:get_cache()
  return vim.deepcopy(self._cache)
end

---Get discovery statistics
---@return table Statistics
function ProjectDiscovery:get_stats()
  local total_cached = 0
  local cache_keys = {}

  for key, projects in pairs(self._cache) do
    total_cached = total_cached + #projects
    table.insert(cache_keys, key)
  end

  return {
    total_cached_projects = total_cached,
    cache_entries = #cache_keys,
    cache_keys = cache_keys,
    total_estimated_size = total_size,
    average_project_size = total_cached > 0 and (total_size / total_cached) or 0,
    largest_project_size = #project_sizes > 0 and math.max(unpack(project_sizes)) or 0,
    smallest_project_size = #project_sizes > 0 and math.min(unpack(project_sizes)) or 0,
  }
end

---Create a streaming discovery iterator for large monorepos
---@param mode string Discovery mode
---@param batch_size? number Number of projects per batch
---@return function Iterator function
function ProjectDiscovery:stream_projects(mode, batch_size)
  batch_size = batch_size or 10
  local all_projects = self:find_projects(mode, { force_refresh = true })
  local index = 1
  
  return function()
    if index > #all_projects then
      return nil
    end
    
    local end_index = math.min(index + batch_size - 1, #all_projects)
    local batch = {}
    
    for i = index, end_index do
      table.insert(batch, all_projects[i])
    end
    
    index = end_index + 1
    
    return batch, index - 1, #all_projects
  end
end

return ProjectDiscovery

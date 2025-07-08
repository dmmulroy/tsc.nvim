---@class PathUtils
local M = {}

-- Platform detection
local is_windows = vim.loop.os_uname().sysname:match('Windows') ~= nil
local path_separator = is_windows and '\\' or '/'
local path_separator_pattern = is_windows and '\\' or '/'

---Normalize path separators for current platform
---@param path string Path to normalize
---@return string Normalized path
function M.normalize(path)
  if not path then
    return ''
  end
  
  -- Replace all separators with platform separator
  path = path:gsub('[/\\]', path_separator)
  
  -- Remove duplicate separators
  path = path:gsub(path_separator .. '+', path_separator)
  
  -- Remove trailing separator (unless root)
  if #path > 1 and path:sub(-1) == path_separator then
    path = path:sub(1, -2)
  end
  
  return path
end

---Join path components
---@param ... string Path components
---@return string Joined path
function M.join(...)
  local parts = {...}
  local result = {}
  
  for _, part in ipairs(parts) do
    if part and part ~= '' then
      -- Remove leading/trailing separators from parts
      part = part:gsub('^[/\\]+', ''):gsub('[/\\]+$', '')
      if part ~= '' then
        table.insert(result, part)
      end
    end
  end
  
  local joined = table.concat(result, path_separator)
  return M.normalize(joined)
end

---Get directory name from path
---@param path string File path
---@return string Directory path
function M.dirname(path)
  if not path or path == '' then
    return '.'
  end
  
  path = M.normalize(path)
  
  -- Handle root directory
  if path == path_separator then
    return path
  end
  
  -- Find last separator
  local last_sep = path:match('.*()' .. path_separator_pattern)
  
  if not last_sep then
    return '.'
  end
  
  -- Return everything before last separator
  local dir = path:sub(1, last_sep - 1)
  
  -- Handle root directory
  if dir == '' then
    return path_separator
  end
  
  return dir
end

---Get base name from path
---@param path string File path
---@param suffix? string Optional suffix to remove
---@return string Base name
function M.basename(path, suffix)
  if not path or path == '' then
    return ''
  end
  
  path = M.normalize(path)
  
  -- Find last separator
  local last_sep = path:match('.*()' .. path_separator_pattern)
  
  local name
  if last_sep then
    name = path:sub(last_sep + 1)
  else
    name = path
  end
  
  -- Remove suffix if provided
  if suffix and name:sub(-#suffix) == suffix then
    name = name:sub(1, -#suffix - 1)
  end
  
  return name
end

---Get file extension
---@param path string File path
---@return string Extension (including dot)
function M.extname(path)
  local name = M.basename(path)
  local ext = name:match('(%.[^.]*)$')
  return ext or ''
end

---Check if path is absolute
---@param path string Path to check
---@return boolean
function M.is_absolute(path)
  if not path or path == '' then
    return false
  end
  
  if is_windows then
    -- Windows: C:\ or \\server\share
    return path:match('^[A-Za-z]:[\\/]') ~= nil or path:match('^[\\/][\\/]') ~= nil
  else
    -- Unix: starts with /
    return path:sub(1, 1) == '/'
  end
end

---Get relative path from one path to another
---@param from string Source path
---@param to string Target path
---@return string Relative path
function M.relative(from, to)
  from = M.normalize(M.absolute(from))
  to = M.normalize(M.absolute(to))
  
  -- Split paths into components
  local from_parts = M.split(from)
  local to_parts = M.split(to)
  
  -- Find common prefix
  local common = 0
  for i = 1, math.min(#from_parts, #to_parts) do
    if from_parts[i] == to_parts[i] then
      common = i
    else
      break
    end
  end
  
  -- Build relative path
  local result = {}
  
  -- Add .. for each directory we need to go up
  for i = common + 1, #from_parts do
    table.insert(result, '..')
  end
  
  -- Add remaining path components
  for i = common + 1, #to_parts do
    table.insert(result, to_parts[i])
  end
  
  if #result == 0 then
    return '.'
  end
  
  return M.join(unpack(result))
end

---Make path absolute
---@param path string Path to make absolute
---@param base? string Base directory (defaults to cwd)
---@return string Absolute path
function M.absolute(path, base)
  if M.is_absolute(path) then
    return M.normalize(path)
  end
  
  base = base or vim.fn.getcwd()
  return M.normalize(M.join(base, path))
end

---Split path into components
---@param path string Path to split
---@return string[] Path components
function M.split(path)
  path = M.normalize(path)
  local parts = {}
  
  -- Handle Windows drive letter
  if is_windows then
    local drive = path:match('^([A-Za-z]:)')
    if drive then
      table.insert(parts, drive)
      path = path:sub(#drive + 1)
    end
  end
  
  -- Split remaining path
  for part in path:gmatch('[^' .. path_separator_pattern .. ']+') do
    table.insert(parts, part)
  end
  
  return parts
end

---Resolve path (expand ~, .., ., and make absolute)
---@param path string Path to resolve
---@return string Resolved path
function M.resolve(path)
  -- Expand ~ to home directory
  if path:sub(1, 1) == '~' then
    local home = vim.loop.os_homedir()
    path = home .. path:sub(2)
  end
  
  -- Make absolute
  path = M.absolute(path)
  
  -- Split into components
  local parts = M.split(path)
  local resolved = {}
  
  for _, part in ipairs(parts) do
    if part == '..' and #resolved > 0 and resolved[#resolved] ~= '..' then
      -- Go up one directory
      table.remove(resolved)
    elseif part ~= '.' and part ~= '' then
      -- Add normal component
      table.insert(resolved, part)
    end
  end
  
  -- Handle empty result (root directory)
  if #resolved == 0 then
    return path_separator
  end
  
  -- Rejoin components
  local result = M.join(unpack(resolved))
  
  -- Ensure Windows paths keep their drive letter format
  if is_windows and result:match('^[A-Za-z]:') and not result:match('^[A-Za-z]:[/\\]') then
    result = result:sub(1, 2) .. path_separator .. result:sub(3)
  end
  
  return result
end

---Check if path matches pattern
---@param path string Path to check
---@param pattern string Pattern (supports * and ** wildcards)
---@return boolean
function M.matches(path, pattern)
  -- Convert glob pattern to Lua pattern
  local lua_pattern = pattern
    :gsub('%.', '%%.')           -- Escape dots
    :gsub('%-', '%%-')           -- Escape dashes
    :gsub('%*%*', '\001')        -- Temporary replacement for **
    :gsub('%*', '[^' .. path_separator_pattern .. ']*')  -- * matches anything except separator
    :gsub('\001', '.*')          -- ** matches anything including separator
    :gsub('^', '^')              -- Anchor to start
    :gsub('$', '$')              -- Anchor to end
  
  return path:match(lua_pattern) ~= nil
end

---Check if path is inside directory
---@param path string Path to check
---@param dir string Directory path
---@return boolean
function M.is_inside(path, dir)
  path = M.normalize(M.absolute(path))
  dir = M.normalize(M.absolute(dir))
  
  -- Add separator to ensure exact directory match
  if not dir:match(path_separator_pattern .. '$') then
    dir = dir .. path_separator
  end
  
  return path:sub(1, #dir) == dir
end

---Find common ancestor of paths
---@param paths string[] List of paths
---@return string|nil Common ancestor path
function M.common_ancestor(paths)
  if #paths == 0 then
    return nil
  end
  
  if #paths == 1 then
    return M.dirname(paths[1])
  end
  
  -- Normalize and split all paths
  local split_paths = {}
  for _, path in ipairs(paths) do
    table.insert(split_paths, M.split(M.normalize(M.absolute(path))))
  end
  
  -- Find common prefix
  local common = {}
  local min_length = math.huge
  
  -- Find minimum path length
  for _, parts in ipairs(split_paths) do
    min_length = math.min(min_length, #parts)
  end
  
  -- Check each component
  for i = 1, min_length do
    local component = split_paths[1][i]
    local all_match = true
    
    for j = 2, #split_paths do
      if split_paths[j][i] ~= component then
        all_match = false
        break
      end
    end
    
    if all_match then
      table.insert(common, component)
    else
      break
    end
  end
  
  if #common == 0 then
    return path_separator
  end
  
  return M.join(unpack(common))
end

---Walk directory tree
---@param root string Root directory
---@param callback function Callback function(path, type)
---@param opts? table Options: {max_depth, follow_symlinks, include_hidden}
function M.walk(root, callback, opts)
  opts = opts or {}
  local max_depth = opts.max_depth or math.huge
  local follow_symlinks = opts.follow_symlinks ~= false
  local include_hidden = opts.include_hidden ~= false
  
  local function walk_recursive(dir, depth)
    if depth > max_depth then
      return
    end
    
    local handle = vim.loop.fs_scandir(dir)
    if not handle then
      return
    end
    
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end
      
      -- Skip hidden files if not included
      if not include_hidden and name:sub(1, 1) == '.' then
        goto continue
      end
      
      local full_path = M.join(dir, name)
      
      -- Handle symlinks
      if type == 'link' and not follow_symlinks then
        goto continue
      end
      
      -- Call callback
      local continue = callback(full_path, type)
      if continue == false then
        return
      end
      
      -- Recurse into directories
      if type == 'directory' or (type == 'link' and follow_symlinks) then
        walk_recursive(full_path, depth + 1)
      end
      
      ::continue::
    end
  end
  
  walk_recursive(root, 1)
end

---Get path separator for current platform
---@return string
function M.separator()
  return path_separator
end

---Check if running on Windows
---@return boolean
function M.is_windows()
  return is_windows
end

return M
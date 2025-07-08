---@class FSUtils
local M = {}

---Check if file exists
---@param path string File path
---@return boolean
function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

---Check if directory exists
---@param path string Directory path
---@return boolean
function M.dir_exists(path)
  return vim.fn.isdirectory(path) == 1
end

---Check if path is executable
---@param path string Path to check
---@return boolean
function M.is_executable(path)
  return vim.fn.executable(path) == 1
end

---Get absolute path
---@param path string Relative or absolute path
---@return string Absolute path
function M.absolute_path(path)
  return vim.fn.fnamemodify(path, ":p")
end

---Get directory name from path
---@param path string File path
---@return string Directory path
function M.dirname(path)
  return vim.fn.fnamemodify(path, ":h")
end

---Get filename from path
---@param path string File path
---@return string Filename
function M.basename(path)
  return vim.fn.fnamemodify(path, ":t")
end

---Join path components
---@param ... string Path components
---@return string Joined path
function M.join(...)
  local parts = { ... }
  local path = table.concat(parts, "/")
  -- Normalize path separators and remove duplicate slashes
  path = path:gsub("//+", "/")
  return path
end

---Find file upward from current directory
---@param filename string Filename to find
---@param start_dir? string Starting directory (defaults to current)
---@return string|nil Found file path or nil
function M.find_file_upward(filename, start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  return vim.fn.findfile(filename, start_dir .. ";")
end

---Find directory upward from current directory
---@param dirname string Directory name to find
---@param start_dir? string Starting directory (defaults to current)
---@return string|nil Found directory path or nil
function M.find_dir_upward(dirname, start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  return vim.fn.finddir(dirname, start_dir .. ";")
end

---Get files matching pattern
---@param pattern string Glob pattern
---@param exclude_patterns? string[] Patterns to exclude
---@return string[] Found files
function M.find_files(pattern, exclude_patterns)
  exclude_patterns = exclude_patterns or {}

  local files = vim.fn.glob(pattern, false, true)
  local result = {}

  for _, file in ipairs(files) do
    local should_exclude = false

    for _, exclude_pattern in ipairs(exclude_patterns) do
      if file:match(exclude_pattern) then
        should_exclude = true
        break
      end
    end

    if not should_exclude then
      table.insert(result, file)
    end
  end

  return result
end

---Get files recursively using ripgrep if available
---@param pattern string File pattern
---@param exclude_patterns? string[] Patterns to exclude
---@return string[] Found files
function M.find_files_recursive(pattern, exclude_patterns)
  exclude_patterns = exclude_patterns or { "node_modules", ".git" }

  if M.is_executable("rg") then
    -- Use ripgrep for better performance
    local exclude_args = ""
    for _, exclude in ipairs(exclude_patterns) do
      exclude_args = exclude_args .. ' -g "!' .. exclude .. '"'
    end

    local cmd = string.format('rg --files%s | rg "%s"', exclude_args, pattern)
    local output = vim.fn.system(cmd)

    if vim.v.shell_error == 0 then
      local files = {}
      for line in output:gmatch("[^\r\n]+") do
        table.insert(files, line)
      end
      return files
    end
  end

  -- Fallback to find command
  local exclude_args = ""
  for _, exclude in ipairs(exclude_patterns) do
    exclude_args = exclude_args .. ' -not -path "*/' .. exclude .. '/*"'
  end

  local cmd = string.format('find . -type f -name "%s"%s', pattern, exclude_args)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error == 0 then
    local files = {}
    for line in output:gmatch("[^\r\n]+") do
      table.insert(files, line)
    end
    return files
  end

  return {}
end

---Check if file matches any pattern
---@param file string File path
---@param patterns string[] Patterns to check
---@return boolean
function M.matches_any_pattern(file, patterns)
  for _, pattern in ipairs(patterns) do
    if file:match(pattern) then
      return true
    end
  end
  return false
end

---Get current working directory
---@return string
function M.cwd()
  return vim.fn.getcwd()
end

---Change current working directory
---@param path string New working directory
---@return boolean success
function M.cd(path)
  if M.dir_exists(path) then
    vim.cmd("cd " .. path)
    return true
  end
  return false
end

---Get file modification time
---@param path string File path
---@return number|nil Modification time or nil if file doesn't exist
function M.get_mtime(path)
  if M.file_exists(path) then
    return vim.fn.getftime(path)
  end
  return nil
end

---Read file contents
---@param path string File path
---@return string|nil File contents or nil if error
function M.read_file(path)
  if not M.file_exists(path) then
    return nil
  end

  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  return content
end

---Write file contents
---@param path string File path
---@param content string File contents
---@return boolean success
function M.write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end

  file:write(content)
  file:close()

  return true
end

return M

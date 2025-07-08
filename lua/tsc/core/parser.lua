---@class OutputParser
local M = {}

---Parse TypeScript compiler output
---@param output string[] Raw output lines
---@return table Parsed results
function M.parse_output(output)
  local errors = {}
  local files = {}
  local files_set = {}

  if not output then
    return { errors = errors, files = files }
  end

  for _, line in ipairs(output) do
    local parsed_error = M.parse_error_line(line)
    if parsed_error then
      table.insert(errors, parsed_error)

      -- Track unique files
      if not files_set[parsed_error.filename] then
        files_set[parsed_error.filename] = true
        table.insert(files, parsed_error.filename)
      end
    end
  end

  return {
    errors = errors,
    files = files,
    total_errors = #errors,
    total_files = #files,
  }
end

---Parse a single error line
---@param line string Error line
---@return table|nil Parsed error or nil
function M.parse_error_line(line)
  -- TypeScript error format: filename(line,col): error TS####: message
  local filename, lineno, colno, message = line:match("^(.+)%((%d+),(%d+)%)%s*:%s*(.+)$")

  if filename and lineno and colno and message then
    return {
      filename = filename,
      lnum = tonumber(lineno),
      col = tonumber(colno),
      text = message,
      type = "E",
      valid = 1,
    }
  end

  return nil
end

---Parse watch mode output
---@param output string[] Raw output lines
---@return table Parsed results with watch info
function M.parse_watch_output(output)
  local results = M.parse_output(output)

  -- Look for watch mode indicators
  local watch_info = {
    is_watch = false,
    is_initial = false,
    is_incremental = false,
    file_changes = {},
  }

  for _, line in ipairs(output) do
    if line:match("Watching for file changes") then
      watch_info.is_watch = true
      watch_info.is_initial = true
    elseif line:match("File change detected") then
      watch_info.is_incremental = true
      -- Extract changed file if possible
      local changed_file = line:match("Starting incremental compilation")
      if changed_file then
        table.insert(watch_info.file_changes, changed_file)
      end
    end
  end

  results.watch_info = watch_info
  return results
end

---Parse specific TypeScript error codes
---@param message string Error message
---@return table Enhanced error info
function M.parse_error_code(message)
  local error_info = {
    code = nil,
    category = "error",
    severity = "error",
    original_message = message,
    enhanced_message = message,
  }

  -- Extract TypeScript error code
  local code = message:match("TS(%d+):")
  if code then
    error_info.code = "TS" .. code
    error_info.numeric_code = tonumber(code)
  end

  -- Categorize common errors
  if error_info.numeric_code then
    error_info.category = M.categorize_error(error_info.numeric_code)
  end

  return error_info
end

---Categorize TypeScript error by code
---@param code number Error code
---@return string Category
function M.categorize_error(code)
  local categories = {
    -- Type errors
    [2322] = "type_assignment",
    [2339] = "property_missing",
    [2345] = "type_argument",
    [2304] = "name_not_found",
    [2551] = "property_not_exist",

    -- Syntax errors
    [1002] = "syntax",
    [1003] = "syntax",
    [1005] = "syntax",
    [1109] = "syntax",

    -- Import/Export errors
    [2307] = "module_resolution",
    [2345] = "import_export",
    [2503] = "module_resolution",

    -- Configuration errors
    [5023] = "config",
    [5024] = "config",
    [5025] = "config",

    -- Compiler option errors
    [5042] = "compiler_option",
    [5043] = "compiler_option",
    [5044] = "compiler_option",
  }

  return categories[code] or "general"
end

---Format error for display
---@param error table Error info
---@param format? string Format type ('quickfix', 'json', 'plain')
---@return string|table Formatted error
function M.format_error(error, format)
  format = format or "quickfix"

  if format == "quickfix" then
    return {
      filename = error.filename,
      lnum = error.lnum,
      col = error.col,
      text = error.text,
      type = error.type,
      valid = error.valid,
    }
  elseif format == "json" then
    return {
      file = error.filename,
      line = error.lnum,
      column = error.col,
      message = error.text,
      severity = error.type == "E" and "error" or "warning",
    }
  elseif format == "plain" then
    return string.format("%s:%d:%d: %s", error.filename, error.lnum, error.col, error.text)
  end

  return error
end

---Format all errors for display
---@param errors table[] List of errors
---@param format? string Format type
---@return table|string Formatted errors
function M.format_errors(errors, format)
  format = format or "quickfix"

  local formatted = {}
  for _, error in ipairs(errors) do
    table.insert(formatted, M.format_error(error, format))
  end

  if format == "json" then
    return vim.fn.json_encode(formatted)
  end

  return formatted
end

---Group errors by file
---@param errors table[] List of errors
---@return table<string, table[]> Errors grouped by file
function M.group_errors_by_file(errors)
  local grouped = {}

  for _, error in ipairs(errors) do
    local filename = error.filename
    if not grouped[filename] then
      grouped[filename] = {}
    end
    table.insert(grouped[filename], error)
  end

  return grouped
end

---Group errors by category
---@param errors table[] List of errors
---@return table<string, table[]> Errors grouped by category
function M.group_errors_by_category(errors)
  local grouped = {}

  for _, error in ipairs(errors) do
    local error_info = M.parse_error_code(error.text)
    local category = error_info.category

    if not grouped[category] then
      grouped[category] = {}
    end

    table.insert(grouped[category], error)
  end

  return grouped
end

---Get error statistics
---@param errors table[] List of errors
---@return table Statistics
function M.get_error_stats(errors)
  local stats = {
    total_errors = #errors,
    files_with_errors = 0,
    error_categories = {},
    severity_counts = { error = 0, warning = 0 },
  }

  local files_set = {}
  local categories = {}

  for _, error in ipairs(errors) do
    -- Count unique files
    if not files_set[error.filename] then
      files_set[error.filename] = true
      stats.files_with_errors = stats.files_with_errors + 1
    end

    -- Count categories
    local error_info = M.parse_error_code(error.text)
    local category = error_info.category
    categories[category] = (categories[category] or 0) + 1

    -- Count severity
    if error.type == "E" then
      stats.severity_counts.error = stats.severity_counts.error + 1
    else
      stats.severity_counts.warning = stats.severity_counts.warning + 1
    end
  end

  stats.error_categories = categories

  return stats
end

---Filter errors by criteria
---@param errors table[] List of errors
---@param criteria table Filter criteria
---@return table[] Filtered errors
function M.filter_errors(errors, criteria)
  local filtered = {}

  for _, error in ipairs(errors) do
    local include = true

    -- Filter by filename pattern
    if criteria.filename_pattern and not error.filename:match(criteria.filename_pattern) then
      include = false
    end

    -- Filter by error code
    if criteria.error_code then
      local error_info = M.parse_error_code(error.text)
      if error_info.code ~= criteria.error_code then
        include = false
      end
    end

    -- Filter by category
    if criteria.category then
      local error_info = M.parse_error_code(error.text)
      if error_info.category ~= criteria.category then
        include = false
      end
    end

    -- Filter by severity
    if criteria.severity then
      local severity = error.type == "E" and "error" or "warning"
      if severity ~= criteria.severity then
        include = false
      end
    end

    if include then
      table.insert(filtered, error)
    end
  end

  return filtered
end

---Sort errors by criteria
---@param errors table[] List of errors
---@param sort_by? string Sort criteria ('filename', 'line', 'column', 'message')
---@param order? string Sort order ('asc', 'desc')
---@return table[] Sorted errors
function M.sort_errors(errors, sort_by, order)
  sort_by = sort_by or "filename"
  order = order or "asc"

  local sorted = vim.deepcopy(errors)

  table.sort(sorted, function(a, b)
    local result = false

    if sort_by == "filename" then
      result = a.filename < b.filename
    elseif sort_by == "line" then
      result = a.lnum < b.lnum
    elseif sort_by == "column" then
      result = a.col < b.col
    elseif sort_by == "message" then
      result = a.text < b.text
    end

    return order == "asc" and result or not result
  end)

  return sorted
end

return M

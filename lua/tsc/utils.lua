local M = {}

M.is_executable = function(cmd)
  return cmd and vim.fn.executable(cmd) == 1 or false
end

M.find_tsc_bin = function()
  local node_modules_tsc_binary = vim.fn.findfile("node_modules/.bin/tsc", ".;")

  if node_modules_tsc_binary ~= "" then
    return node_modules_tsc_binary
  end

  return "tsc"
end

M.find_nearest_tsconfig = function()
  local tsconfig = vim.fn.findfile("tsconfig.json", ".;")

  if tsconfig ~= "" then
    return tsconfig
  end

  return nil
end

M.parse_flags = function(flags)
  if type(flags) == "string" then
    return flags
  end

  local parsed_flags = {}

  for key, value in pairs(flags) do
    if type(value) == "function" then
      value = value()
    end

    if type(value) ~= "string" and type(value) ~= "boolean" then
      vim.notify(
        string.format(
          "Skipping flag '%s' because of an invalid value. Valid values include strings, booleans, or a function that returns a string or boolean.",
          key
        ),
        vim.log.levels.ERROR
      )
    else
      parsed_flags[string.gsub(key, "%-%-", "")] = value
    end
  end

  local flags_string = ""

  for key, value in pairs(parsed_flags) do
    if value == true then
      flags_string = flags_string .. string.format("--%s ", key)
    else
      flags_string = flags_string .. string.format("--%s %s ", key, value)
    end
  end

  return flags_string
end

M.parse_tsc_output = function(output)
  local errors = {}
  local files = {}

  if output == nil then
    return { errors = errors, files = files }
  end

  for _, line in ipairs(output) do
    local filename, lineno, colno, message = line:match("^(.+)%((%d+),(%d+)%)%s*:%s*(.+)$")
    if filename ~= nil then
      table.insert(errors, {
        filename = filename,
        lnum = tonumber(lineno),
        col = tonumber(colno),
        text = message,
        type = "E",
      })

      if vim.tbl_contains(files, filename) == false then
        table.insert(files, filename)
      end
    end
  end

  return { errors = errors, files = files }
end

M.set_qflist = function(errors, auto_open)
  auto_open = auto_open or true

  vim.fn.setqflist({}, "r", { title = "TSC", items = errors })

  if #errors > 0 and auto_open then
    vim.cmd("copen")
  end
end

return M

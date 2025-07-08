local better_messages = require("tsc.better-messages")

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
    return vim.fn.fnamemodify(tsconfig, ":p")
  end

  return nil
end

M.get_project_root = function(tsconfig_path)
  if tsconfig_path then
    return vim.fn.fnamemodify(tsconfig_path, ":h")
  end
  return nil
end

M.parse_flags = function(flags)
  if type(flags) == "string" then
    return flags
  end

  local parsed_flags = ""

  -- Auto-detect project if not explicitly configured
  if not flags.project then
    local nearest_tsconfig = M.find_nearest_tsconfig()
    if nearest_tsconfig then
      flags.project = nearest_tsconfig
    end
  end
  
  -- Add --color false to ensure plain text output for parsing, unless user explicitly set color
  if flags.color == nil then
    flags.color = false
  end

  for key, value in pairs(flags) do
    key = string.gsub(key, "%-%-", "")

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
      if type(value) == "boolean" then
        if value == true then
          parsed_flags = parsed_flags .. string.format("--%s ", key)
        end
      else
        parsed_flags = parsed_flags .. string.format("--%s %s ", key, value)
      end
    end
  end

  return parsed_flags
end

M.parse_tsc_output = function(output, config)
  local errors = {}
  local files = {}

  if output == nil then
    return { errors = errors, files = files }
  end

  for _, line in ipairs(output) do
    local filename, lineno, colno, message = line:match("^(.+)%((%d+),(%d+)%)%s*:%s*(.+)$")
    if filename ~= nil then
      local text = message
      if config.pretty_errors then
        text = better_messages.translate(message)
      end
      table.insert(errors, {
        filename = filename,
        lnum = tonumber(lineno),
        col = tonumber(colno),
        text = text,
        type = "E",
      })

      if vim.tbl_contains(files, filename) == false then
        table.insert(files, filename)
      end
    end
  end

  return { errors = errors, files = files }
end

M.set_qflist = function(errors, opts)
  local DEFAULT_OPTS = { auto_open = true, auto_close = false }
  local final_opts = vim.tbl_extend("force", DEFAULT_OPTS, opts or {})

  vim.fn.setqflist({}, "r", { title = "TSC", items = errors })

  if #errors > 0 and final_opts.auto_open then
    local win = vim.api.nvim_get_current_win()

    vim.cmd("copen")

    if not final_opts.auto_focus then
      vim.api.nvim_set_current_win(win)
    end
  elseif #errors == 0 and final_opts.auto_close then
    vim.cmd("cclose")
  end
end

return M

---@class Utils
local better_messages = require("tsc.better-messages")

local has_trouble, pcall_trouble = pcall(require, "trouble")
local trouble = has_trouble and pcall_trouble or nil

local M = {}

---Check if a command is executable
---@param cmd string|nil Command to check
---@return boolean Whether the command is executable
M.is_executable = function(cmd)
  return cmd and vim.fn.executable(cmd) == 1 or false
end

---Find TypeScript compiler binary
---@return string Path to tsc binary
M.find_tsc_bin = function()
  local node_modules_tsc_binary = vim.fn.findfile("node_modules/.bin/tsc", ".;")

  if node_modules_tsc_binary ~= "" then
    return node_modules_tsc_binary
  end

  return "tsc"
end

---Find TypeScript configuration files
---@param run_mono_repo boolean Whether to search for monorepo configs
---@return string[] List of tsconfig.json paths
M.find_tsconfigs = function(run_mono_repo)
  if not run_mono_repo then
    return M.find_nearest_tsconfig()
  end

  local tsconfigs = {}

  local found_configs
  if M.is_executable("rg") then
    found_configs = vim.fn.system("rg -g '!node_modules' --files | rg 'tsconfig.*.json'")
  else
    found_configs = vim.fn.system('find . -not -path "*/node_modules/*" -name "tsconfig.*.json" -type f')
  end

  if not found_configs or found_configs == "" then
    return {}
  end

  for s in found_configs:gmatch("[^\r\n]+") do
    table.insert(tsconfigs, s)
  end

  return tsconfigs
end

---Find nearest tsconfig.json file
---@return string[] List containing single tsconfig path or empty
M.find_nearest_tsconfig = function()
  local tsconfig = vim.fn.findfile("tsconfig.json", ".;")

  if tsconfig ~= "" then
    return { vim.fn.fnamemodify(tsconfig, ":p") }
  end

  return {}
end

---Get project root directory from tsconfig path
---@param tsconfig_path string|nil Path to tsconfig.json
---@return string|nil Project root directory
M.get_project_root = function(tsconfig_path)
  if tsconfig_path then
    return vim.fn.fnamemodify(tsconfig_path, ":h")
  end
  return nil
end

---Parse TypeScript compiler flags
---@param flags string|table Flags to parse
---@return string Parsed flags string
M.parse_flags = function(flags)
  if type(flags) == "string" then
    return flags
  end

  local parsed_flags = ""

  -- Auto-detect project if not explicitly configured
  if not flags.project then
    local nearest_tsconfigs = M.find_nearest_tsconfig()
    if #nearest_tsconfigs > 0 then
      flags.project = nearest_tsconfigs[1]
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
        if value then
          parsed_flags = parsed_flags .. string.format("--%s ", key)
        end
      else
        parsed_flags = parsed_flags .. string.format("--%s %s ", key, value)
      end
    end
  end

  return parsed_flags
end

---Parse TypeScript compiler output into errors and files
---@param output string[]|nil Raw compiler output lines
---@param config table Configuration options
---@return table Parsed output with errors and files
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

      if not vim.tbl_contains(files, filename) then
        table.insert(files, filename)
      end
    end
  end

  return { errors = errors, files = files }
end

---Set quickfix list with errors
---@param errors table[] List of error items
---@param opts table|nil Options for quickfix behavior
M.set_qflist = function(errors, opts)
  local DEFAULT_OPTS = { auto_open = true, auto_close = false, use_trouble = false }
  local final_opts = vim.tbl_extend("force", DEFAULT_OPTS, opts or {})

  vim.fn.setqflist({}, "r", { title = "TSC", items = errors })

  if #errors > 0 and final_opts.auto_open then
    M.open_qflist(final_opts.use_trouble, final_opts.auto_focus)
  end

  -- trouble needs to be refreshed when list is empty.
  if final_opts.use_trouble and trouble ~= nil then
    trouble.refresh()
  end

  if #errors == 0 then
    if final_opts.auto_close then
      M.close_qflist(final_opts.use_trouble)
    end
  end
end

---Open the quickfix list
---@param use_trouble boolean Whether to use trouble.nvim as qflist provider
---@param auto_focus boolean Whether to focus the qflist on open
M.open_qflist = function(use_trouble, auto_focus)
  local win = vim.api.nvim_get_current_win()
  if use_trouble and trouble ~= nil then
    trouble.open("quickfix")
  else
    vim.cmd("copen")
  end

  if not auto_focus then
    vim.api.nvim_set_current_win(win)
  end
end

---Close the quickfix list
---@param use_trouble boolean Whether to use trouble.nvim as qflist provider
M.close_qflist = function(use_trouble)
  if use_trouble and trouble ~= nil then
    trouble.close()
  else
    vim.cmd("cclose")
  end
end

return M

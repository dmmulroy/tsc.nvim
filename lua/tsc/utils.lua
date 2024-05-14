local better_messages = require("tsc.better-messages")

local has_trouble, pcall_trouble = pcall(require, "trouble")
local trouble = has_trouble and pcall_trouble or nil

local M = {}

M.is_executable = function(cmd)
  return cmd and vim.fn.executable(cmd) == 1 or false
end

M.find_tsc_bin = function()
  local node_modules_tsc_binary = vim.fn.findfile("node_modules/.bin/tsc", ".;")

  if node_modules_tsc_binary == "" then
    node_modules_tsc_binary = vim.fn.findfile(".yarn/sdks/typescript/bin/tsc", ".;")
  end

  if node_modules_tsc_binary ~= "" then
    return node_modules_tsc_binary
  end

  return "tsc"
end

--- @param run_mono_repo boolean
--- @return table<string>
M.find_tsconfigs = function(run_mono_repo)
  if not run_mono_repo then
    return M.find_nearest_tsconfig()
  end

  local tsconfigs = {}

  local found_configs = nil
  if M.is_executable("rg") then
    found_configs = vim.fn.system("rg -g '!node_modules' --files | rg 'tsconfig.*.json'")
  else
    found_configs = vim.fn.system('find . -not -path "*/node_modules/*" -name "tsconfig.*.json" -type f')
  end

  if found_configs == nil then
    return {}
  end

  for s in found_configs:gmatch("[^\r\n]+") do
    table.insert(tsconfigs, s)
  end

  assert(tsconfigs)
  return tsconfigs
end

M.find_nearest_tsconfig = function()
  local tsconfig = vim.fn.findfile("tsconfig.json", ".;")

  if tsconfig ~= "" then
    return { tsconfig }
  end

  return {}
end

M.parse_flags = function(flags)
  if type(flags) == "string" then
    return flags
  end

  local parsed_flags = ""

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

--- open the qflist
--- @param use_trouble boolean: if trouble should be used as qflist provider
--- @param auto_focus boolean: if the qflist should be focused on open
--- @return nil
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

--- close the qflist
--- @param use_trouble boolean: if trouble should be used as qflist provider
--- @return nil
M.close_qflist = function(use_trouble)
  if use_trouble and trouble ~= nil then
    trouble.close()
  else
    vim.cmd("cclose")
  end
end

return M

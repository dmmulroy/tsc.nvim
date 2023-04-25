local success, pcall_result = pcall(require, "notify")
local utils = require("utils")

local M = {}

local nvim_notify

if success then
  nvim_notify = pcall_result
end

local is_running = false

local spinner = {
  "⣾",
  "⣽",
  "⣻",
  "⢿",
  "⡿",
  "⣟",
  "⣯",
  "⣷",
}

local function open_qf_list(errors)
  vim.fn.setqflist({}, "r", { title = "TSC", items = errors })

  if #errors > 0 then
    vim.cmd("copen")
  end
end

local function parse_tsc_output(output)
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

local function format_notification_msg(msg, spinner_idx)
  if spinner_idx == 0 or spinner_idx == nil then
    return string.format(" %s ", msg)
  end

  return string.format(" %s %s ", spinner[spinner_idx], msg)
end

M.run = function()
  -- Closed over state
  local cmd = utils.get_tsc_cmd()
  local args = "--noEmit"
  local errors = {}
  local files_with_errors = {}
  local notify_record
  local spinner_idx = 0

  if vim.fn.executable(cmd) == 0 then
    vim.notify(
      format_notification_msg(
        "tsc was not available or found in your node_modules or $PATH. Please run install and try again."
      ),
      vim.log.levels.ERROR,
      { title = "TSC" }
    )

    return
  end

  if is_running then
    vim.notify(format_notification_msg("Type-checking already in progress"), vim.log.levels.WARN, { title = "TSC" })
    return
  end

  is_running = true

  local function notify()
    if not is_running then
      return
    end

    local notify_opts = { title = "TSC" }

    if notify_record ~= nil then
      notify_opts = vim.tbl_extend("force", { replace = notify_record.id }, notify_opts)
    end

    notify_record = vim.notify(
      format_notification_msg("Type-checking your project, kick back and relax 🚀", spinner_idx),
      nil,
      notify_opts
    )

    spinner_idx = spinner_idx + 1

    if spinner_idx > #spinner then
      spinner_idx = 1
    end

    vim.defer_fn(notify, 125)
  end

  notify()

  local function on_stdout(_, output)
    local result = parse_tsc_output(output)

    errors = result.errors
    files_with_errors = result.files

    if #errors > 0 then
      open_qf_list(errors)
    end
  end

  local on_exit = function()
    is_running = false
    local notify_opts = { title = "TSC" }

    if notify_record ~= nil and #errors == 0 then
      notify_opts = vim.tbl_extend("force", { replace = notify_record.id }, notify_opts)
    end

    if #errors == 0 then
      vim.notify(format_notification_msg("Type-checking complete. No errors found 🎉"), nil, notify_opts)
      return
    end

    -- Clear any previous notifications if the user has nvim-notify installed
    if nvim_notify ~= nil then
      nvim_notify.dismiss()
    end

    vim.notify(
      format_notification_msg(
        string.format("Type-checking complete. Found %s errors across %s files 💥", #errors, #files_with_errors)
      ),
      vim.log.levels.ERROR,
      notify_opts
    )
  end

  local opts = {
    on_stdout = on_stdout,
    on_exit = on_exit,
    stdout_buffered = true,
  }

  vim.fn.jobstart(cmd .. " " .. args, opts)
end

function M.is_running()
  return is_running
end

function M.setup()
  vim.api.nvim_create_user_command(
    "TSC",
    M.run,
    { desc = "Run `tsc` asynchronously and load the results into a qflist", force = true }
  )
end

return M

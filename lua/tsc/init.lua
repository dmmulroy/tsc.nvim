local success, pcall_result = pcall(require, "notify")
local utils = require("tsc.utils")

local M = {}

local nvim_notify

if success then
  nvim_notify = pcall_result
end

local DEFAULT_CONFIG = {
  auto_open_qflist = true,
  enable_progress_notifications = true,
  flags = "--noEmit",
  hide_progress_notifications_from_history = true,
  spinner = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
}

local DEFAULT_NOTIFY_OPTIONS = {
  title = "TSC",
  hide_from_history = false,
}

local config = {}

local is_running = false

local function get_notify_options(...)
  local overrides = {}

  for _, opts in ipairs({ ... }) do
    for key, value in pairs(opts) do
      overrides[key] = value
    end
  end

  return vim.tbl_deep_extend("force", {}, DEFAULT_NOTIFY_OPTIONS, overrides)
end

local function set_qflist(errors)
  vim.fn.setqflist({}, "r", { title = "TSC", items = errors })

  if #errors > 0 and config.auto_open_qflist then
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

  return string.format(" %s %s ", config.spinner[spinner_idx], msg)
end

M.run = function()
  -- Closed over state
  local cmd = utils.get_tsc_cmd()
  local errors = {}
  local files_with_errors = {}
  local notify_record
  local notify_called = false
  local spinner_idx = 0

  if not utils.is_executable(cmd) then
    vim.notify(
      format_notification_msg(
        "tsc was not available or found in your node_modules or $PATH. Please run install and try again."
      ),
      vim.log.levels.ERROR,
      get_notify_options()
    )

    return
  end

  if is_running then
    vim.notify(format_notification_msg("Type-checking already in progress"), vim.log.levels.WARN, get_notify_options())
    return
  end

  is_running = true

  local function notify()
    if not is_running then
      return
    end

    notify_record = vim.notify(
      format_notification_msg("Type-checking your project, kick back and relax 🚀", spinner_idx),
      nil,
      get_notify_options(
        (notify_record and { replace = notify_record.id }),
        (config.hide_progress_notifications_from_history and notify_called and { hide_from_history = true })
      )
    )

    notify_called = true

    spinner_idx = spinner_idx + 1

    if spinner_idx > #config.spinner then
      spinner_idx = 1
    end

    vim.defer_fn(notify, 125)
  end

  if config.enable_progress_notifications then
    notify()
  end

  local function on_stdout(_, output)
    local result = parse_tsc_output(output)

    errors = result.errors
    files_with_errors = result.files

    set_qflist(errors)
  end

  local on_exit = function()
    is_running = false

    if not config.enable_progress_notifications then
      return
    end

    if #errors == 0 then
      vim.notify(
        format_notification_msg("Type-checking complete. No errors found 🎉"),
        nil,
        get_notify_options((notify_record and { replace = notify_record.id }))
      )
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
      get_notify_options()
    )
  end

  local opts = {
    on_stdout = on_stdout,
    on_exit = on_exit,
    stdout_buffered = true,
  }

  vim.fn.jobstart(cmd .. " " .. config.flags, opts)
end

function M.is_running()
  return is_running
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, DEFAULT_CONFIG, opts or {})

  vim.api.nvim_create_user_command("TSC", function()
    vim.cmd("silent cd %:h")
    M.run()
    vim.cmd("silent cd-")
  end, { desc = "Run `tsc` asynchronously and load the results into a qflist", force = true })
end

return M

local success, pcall_result = pcall(require, "notify")
local utils = require("tsc.utils")

local M = {}

local nvim_notify

if success then
  nvim_notify = pcall_result
end

local DEFAULT_CONFIG = {
  auto_open_qflist = true,
  auto_close_qflist = false,
  auto_focus_qflist = false,
  auto_start_watch_mode = false,
  use_trouble_qflist = false,
  bin_path = utils.find_tsc_bin(),
  enable_progress_notifications = true,
  flags = {
    noEmit = true,
    project = nil,
    watch = false,
  },
  hide_progress_notifications_from_history = true,
  spinner = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  pretty_errors = true,
}

local DEFAULT_NOTIFY_OPTIONS = {
  title = "TSC",
  hide_from_history = false,
}

local config = {}
local running_PIDs = {}

local function get_notify_options(...)
  local overrides = {}

  for _, opts in ipairs({ ... }) do
    for key, value in pairs(opts) do
      overrides[key] = value
    end
  end

  return vim.tbl_deep_extend("force", {}, DEFAULT_NOTIFY_OPTIONS, overrides)
end

local function format_notification_msg(msg, spinner_idx)
  if spinner_idx == 0 or spinner_idx == nil then
    return string.format(" %s ", msg)
  end

  return string.format(" %s %s ", config.spinner[spinner_idx], msg)
end

M.run = function()
  -- Closed over state
  local tsc = config.bin_path
  local errors = {}
  local files_with_errors = {}
  local notify_record
  local notify_called = false
  local spinner_idx = 1

  if not utils.is_executable(tsc) then
    vim.notify(
      format_notification_msg(
        "tsc was not available or found in your node_modules or $PATH. Please run install and try again."
      ),
      vim.log.levels.ERROR,
      get_notify_options()
    )

    return
  end

  config.flags.project = utils.find_nearest_tsconfig()

  if M.is_running(config.flags.project) then
    return
  end

  local function notify()
    if not M.is_running(config.flags.project) then
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

  local function notify_watch_mode()
    vim.notify("👀 Watching your project for changes, kick back and relax 🚀", nil, get_notify_options())
  end

  if config.enable_progress_notifications then
    if config.flags.watch then
      notify_watch_mode()
    else
      notify()
    end
  end

  local function on_stdout(_, output)
    local result = utils.parse_tsc_output(output, config)

    errors = result.errors
    files_with_errors = result.files

    utils.set_qflist(errors, {
      auto_open = config.auto_open_qflist,
      auto_close = config.auto_close_qflist,
      auto_focus = config.auto_focus_qflist,
      use_trouble = config.use_trouble_qflist,
    })

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

  local total_output = {}

  local function watch_on_stdout(_, output)
    for _, v in ipairs(output) do
      table.insert(total_output, v)
    end

    for _, value in pairs(output) do
      if string.find(value, "Watching for file changes") then
        on_stdout(_, total_output)
        total_output = {}
      end
    end
  end

  local on_exit = function(project)
    running_PIDs[project] = nil
  end

  local opts = {
    on_stdout = on_stdout,
    on_exit = function()
      on_exit(config.flags.project)
    end,
    stdout_buffered = true,
  }

  if config.flags.watch then
    opts.stdout_buffered = false
    opts.on_stdout = watch_on_stdout
  end

  running_PIDs[config.flags.project] = vim.fn.jobstart(tsc .. " " .. utils.parse_flags(config.flags), opts)
end

function M.is_running(project)
  return running_PIDs[project] ~= nil
end

M.stop = function()
  for _, pid in pairs(running_PIDs) do
    vim.fn.jobstop(pid)
  end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, DEFAULT_CONFIG, opts or {})

  vim.api.nvim_create_user_command("TSC", function()
    if M.is_running(config.flags.project) then
      vim.notify(
        format_notification_msg("Type-checking already in progress"),
        vim.log.levels.WARN,
        get_notify_options()
      )
      return
    end
    M.run()
  end, { desc = "Run `tsc` asynchronously and load the results into a qflist", force = true })

  vim.api.nvim_create_user_command("TSCStop", function()
    M.stop()
  end, { desc = "stop running `tsc`", force = true })

  vim.api.nvim_create_user_command("TSCOpen", function()
    utils.open_qflist(config.use_trouble_qflist, config.auto_focus_qflist)
  end, { desc = "Open the results in a qflist", force = true })

  vim.api.nvim_create_user_command("TSCClose", function()
    utils.close_qflist(config.use_trouble_qflist)
  end, { desc = "Close the results qflist", force = true })

  if config.flags.watch then
    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "*.{ts,tsx}",
      desc = "Run tsc.nvim in watch mode automatically when saving a TypeScript file",
      callback = function()
        vim.notify("Type-checking your project via watch mode, hang tight 🚀", nil, get_notify_options())
      end,
    })

    if config.auto_start_watch_mode then
      vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        pattern = "*.{ts,tsx}",
        desc = "Start tsc.nvim in watch mode automatically when opening a TypeScript file",
        callback = function()
          M.run()
        end,
      })
    end
  end
end

return M

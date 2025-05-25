local success, pcall_result = pcall(require, "notify")
local utils = require("tsc.utils")

local M = {}

local nvim_notify

if success then
  nvim_notify = pcall_result
end

--- @class Opts
--- @field auto_open_qflist? boolean - (false) When true the quick fix list will automatically open when errors are found
--- @field auto_close_qflist? boolean - (false) When true the quick fix list will automatically close when no errors are found
--- @field auto_focus_qflist? boolean - (false) When true the quick fix list will automatically focus when errors are found
--- @field auto_start_watch_mode? boolean - (false) When true the `tsc` process will be started in watch mode when a typescript buffer is opened
--- @field use_trouble_qflist? boolean - (false) When true the quick fix list will be opened in Trouble if it is installed
--- @field use_diagnostics? boolean - (false) When true the errors will be set as diagnostics
--- @field run_as_monorepo? boolean - (false) When true the `tsc` process will be started mode for each tsconfig in the current working directory
--- @field max_tsconfig_files? number - (20) Will not run `tsc` if number of found tsconfig files is greater.
--- @field bin_path? string - Path to the tsc binary if it is not in the projects node_modules or globally
--- @field enable_progress_notifications? boolean - (true) When false progress notifications will not be shown
--- @field enable_error_notifications? boolean - (true) When false error notifications will not be shown
--- @field hide_progress_notifications_from_history? boolean - (true) When true progress notifications will be hidden from history
--- @field spinner? string[] - ({"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"}) - The spinner characters to use
--- @field pretty_errors? boolean - (true) When true errors will be formatted with `pretty`
--- @field flags? { [string]: boolean }

local DEFAULT_CONFIG = {
  auto_open_qflist = true,
  auto_close_qflist = false,
  auto_focus_qflist = false,
  auto_start_watch_mode = false,
  use_trouble_qflist = false,
  use_diagnostics = false,
  bin_path = nil,
  enable_progress_notifications = true,
  enable_error_notifications = true,
  run_as_monorepo = false,
  max_tsconfig_files = 20,
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
  id = "tsc.nvim",
}

local config = {} ---@type Opts

--- Storage for each running tsc process
--- @type {[string]:{pid: number, errors: table }}
local running_processes = {}
local running_count = 0

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
  local tsc = config.bin_path or utils.find_tsc_bin()
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

  local configs_to_run = utils.find_tsconfigs(config.run_as_monorepo)

  if #configs_to_run > 0 and not config.run_as_monorepo then
    M.stop()
  end

  for i, k in pairs(configs_to_run) do
    if running_processes[k] ~= nil then
      configs_to_run[i] = nil
    end
  end

  if #configs_to_run > config.max_tsconfig_files then
    vim.notify_once("Too many tsconfigs found: " .. #configs_to_run, vim.log.levels.ERROR, get_notify_options())
    return
  end

  if not config.flags.watch and #configs_to_run == 0 then
    vim.notify(format_notification_msg("Type-checking already in progress"), vim.log.levels.WARN, get_notify_options())
    return
  end

  running_count = #configs_to_run

  local function notify()
    if running_count == 0 then
      return
    end

    notify_record = vim.notify(
      format_notification_msg(
        (
          config.flags.watch and "👀 Watching your project for changes"
          or "Type-checking your project" .. (running_count > 0 and "s" or "")
        ) .. ", kick back and relax 🚀",
        spinner_idx
      ),
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

  if config.enable_progress_notifications and not notify_called then
    notify()
  end

  local function create_output()
    running_count = running_count - 1
    if running_count > 0 then
      return
    end

    running_count = 0
    notify_called = false
    errors = {}

    for _, process in pairs(running_processes) do
      for _, error in ipairs(process.errors) do
        table.insert(errors, error)
      end
    end

    utils.set_qflist(errors, {
      auto_open = config.auto_open_qflist,
      auto_close = config.auto_close_qflist,
      auto_focus = config.auto_focus_qflist,
      use_trouble = config.use_trouble_qflist,
    })

    if config.use_diagnostics then
      local namespace_id = vim.api.nvim_create_namespace("tsc_diagnostics")
      vim.diagnostic.reset(namespace_id)

      for _, error in ipairs(errors) do
        local bufnr = vim.fn.bufnr(error.filename)
        if bufnr == -1 then
          vim.notify("Buffer not found for " .. error.filename, vim.log.levels.ERROR, get_notify_options())
          return
        end
        local diagnostic = {
          bufnr = bufnr,
          lnum = error.lnum - 1,
          col = error.col - 1,
          severity = vim.diagnostic.severity.ERROR,
          message = error.text,
          source = "tsc",
        }
        vim.diagnostic.set(namespace_id, bufnr, { diagnostic }, {})
      end
    end

    if #errors == 0 then
      if config.enable_progress_notifications then
        vim.notify(
          format_notification_msg("Type-checking complete. No errors found 🎉"),
          nil,
          get_notify_options((notify_record and { replace = notify_record.id }))
        )
      end
      return
    end

    if not config.enable_error_notifications then
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
      get_notify_options((notify_record and { overwrite = notify_record.id }))
    )
  end

  local function on_stdout(output, project)
    local result = utils.parse_tsc_output(output, config)

    running_processes[project].errors = result.errors

    for _, v in ipairs(result.files) do
      table.insert(files_with_errors, v)
    end
  end

  local total_output = {}

  local function watch_on_stdout(output, project)
    for _, v in ipairs(output) do
      table.insert(total_output, v)
    end

    for _, value in pairs(output) do
      if string.find(value, "Watching for file changes") then
        on_stdout(total_output, project)
        total_output = {}
        create_output()
      end
    end
  end

  local on_exit = function()
    if config.flags.watch then
      return
    end

    create_output()
    if running_count == 0 then
      running_processes = {}
    end
  end

  local opts = function(project)
    return {
      on_stdout = function(_, output)
        on_stdout(output, project)
      end,
      on_exit = function()
        on_exit()
      end,
      stdout_buffered = true,
    }
  end

  for _, project in ipairs(configs_to_run) do
    local project_opts = opts(project)

    if config.flags.watch then
      project_opts.stdout_buffered = false
      project_opts.on_stdout = function(_, output)
        watch_on_stdout(output, project)
      end
    end

    local flags = ""
    if type(config.flags) == "string" then
      flags = config.flags
    else
      flags = utils.parse_flags(vim.tbl_extend("force", config.flags, { project = project }))
    end
    vim.schedule(function()
      running_processes[project] = {
        pid = vim.fn.jobstart(tsc .. " " .. flags, project_opts),
        errors = {},
      }
    end)
  end
end

function M.is_running(project)
  return running_processes[project] ~= nil
end

M.stop = function()
  for _, process in pairs(running_processes) do
    vim.fn.jobstop(process.pid)
    running_processes = {}
  end
end

--- @param opts Opts | nil
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, DEFAULT_CONFIG, opts or {})

  vim.api.nvim_create_user_command("TSC", function()
    M.run()
  end, { desc = "Run `tsc` asynchronously and load the results into a qflist", force = true })

  vim.api.nvim_create_user_command("TSCStop", function()
    M.stop()
    vim.notify_once(format_notification_msg("TSC stopped"), nil, get_notify_options())
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
        if config.enable_progress_notifications then
          vim.notify("Type-checking your project via watch mode, hang tight 🚀", nil, get_notify_options())
        end
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

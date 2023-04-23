local M = {}

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
  if spinner_idx == nil then
    return string.format(" %s", msg)
  end

  return string.format(" %s %s", spinner[spinner_idx], msg)
end

M.run = function()
  -- Closed over state
  local cmd = "tsc --noEmit"
  local notify_opts = { title = "TSC" }
  local errors = {}
  local files_with_errors = {}
  local notify_record
  local spinner_idx

  if vim.fn.executable("tsc") == 0 then
    vim.notify(
      format_notification_msg("tsc was not available or found in your $PATH. Please run `npm install typescript -g`"),
      vim.log.levels.ERROR,
      notify_opts
    )
    return
  end

  if is_running then
    vim.notify(format_notification_msg("Type-checking already in progress"), vim.log.levels.WARN, notify_opts)
    return
  end

  is_running = true

  local function notify()
    if not is_running then
      return
    end

    if notify_record ~= nil then
      notify_opts = vim.tbl_extend("force", { replace = notify_record.id }, notify_opts)
    end

    notify_record = vim.notify(
      format_notification_msg("Type-checking your project, kick back and relax 🚀", spinner_idx),
      vim.log.levels.INFO,
      notify_opts
    )

    if spinner_idx == nil then
      spinner_idx = 1
    else
      spinner_idx = spinner_idx + 1
    end

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

    if notify_record ~= nil then
      notify_opts = vim.tbl_extend("force", notify_opts, { replace = notify_record.id })
    end

    if #errors == 0 then
      vim.notify(
        format_notification_msg("Type-checking complete. No errors found 🎉"),
        vim.log.levels.INFO,
        notify_opts
      )
      return
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

  vim.fn.jobstart(cmd, opts)
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

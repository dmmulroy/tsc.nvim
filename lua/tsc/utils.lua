local M = {}

M.is_executable = function(cmd)
  return cmd and vim.fn.executable(cmd) == 1 or false
end

M.get_tsc_cmd = function()
  vim.cmd("silent cd %:h")
  local node_modules_tsc_binary = vim.fn.findfile("node_modules/.bin/tsc", ".;")
  vim.cmd("silent cd-")
  if node_modules_tsc_binary ~= "" then
    return node_modules_tsc_binary
  end

  return "tsc"
end

return M

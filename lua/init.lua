local tsc = require("tsc")

local M = {}

M.setup = function()
  tsc.setup()
end

M.run = function()
  tsc.run()
end

M.is_running = function()
  return tsc.is_running()
end

return M

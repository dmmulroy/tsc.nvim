-- Module M for better error message handling
local M = {}

-- Regex pattern for capturing numbered parameters like {0}, {1}, etc.
local parameter_regex = "({%d})"

-- Extracts parameter placeholders from a given error template.
-- @param error_template string: The template string containing parameter placeholders.
-- @return table: A list of all parameter placeholders found in the template.
local function get_params(error_template)
  local params = {}
  for param in error_template:gmatch(parameter_regex) do
    table.insert(params, param)
  end
  return params
end

-- Extracts quoted strings from a given message.
-- @param message string: The message string containing quoted parts.
-- @return table: A list of all quoted strings found in the message.
local function get_matches(message)
  local matches = {}

  for match in string.gmatch(message, "'(.-)'") do
    table.insert(matches, match)
  end

  return matches
end

-- Constructs a better error message by replacing placeholders in the template with actual values.
-- @param error_msg string: The original error message.
-- @param error_template string: The error template with placeholders.
-- @param better_error_template string: The improved error message template.
-- @return string: The improved error message, or original if replacement isn't possible.
local function better_error_message(error_msg, error_template, better_error_template)
  local matches = get_matches(error_msg)
  local params = get_params(error_template)

  if #params ~= #matches then
    return error_msg
  end

  local better_error = better_error_template

  for i = 1, #params do
    better_error = better_error:gsub(params[i], matches[i])
  end

  return better_error
end

-- Retrieves a markdown file associated with a specific error number.
-- @param error_num string: The error number identifier.
-- @return file* | nil: The file pointer to the markdown file, if exists.
local function get_error_markdown_file(error_num)
  local filename = error_num .. ".md"
  local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h")
  return io.open(plugin_path .. "/better-messages/" .. filename, "r")
end

-- Parses a markdown file to extract 'original' and 'better' content.
-- @param markdown file*: The markdown file pointer.
-- @return table: A table with 'original' and 'better' keys containing extracted contents.
local function parse_md(markdown)
  local contents = markdown:read("*all")
  markdown:close()

  -- First, remove the leading and trailing '---'
  local trimmedMarkdown = contents:gsub("^%-%-%-%s*", ""):gsub("%s*%-%-%-$", "")

  -- Split the remaining content at the '---' separator
  local originalContent, betterContent = trimmedMarkdown:match("^(.-)%s*%-%-%-%s*(.-)$")

  -- Trim whitespace from both contents
  originalContent = originalContent:gsub('^original:%s*"(.-)"%s*$', "%1")
  betterContent = betterContent:gsub("^%s*(.-)%s*$", "%1")

  -- Return the table with the extracted contents
  return {
    original = originalContent,
    better = betterContent,
  }
end

-- Attempt to translate a given compiler message into a better one.
-- @param message string: The original compiler message to parse.
-- @return string: The improved or original error message.
M.translate = function(message)
  local error_num, original_message = message:match("^.*TS(%d+):%s(.*)")
  local improved_text_file = get_error_markdown_file(error_num)
  if improved_text_file == nil then
    return message
  end

  local parsed = parse_md(improved_text_file)

  local params = get_params(parsed["original"])

  if #params == 0 and parsed.body then
    return "TS" .. error_num .. ": " .. parsed.body
  end

  local better_error = better_error_message(original_message, parsed["original"], parsed["better"])

  return "TS" .. error_num .. ": " .. better_error
end

-- Returning the module M.
return M

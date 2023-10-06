local M = {}

--- Gets a pointer to the improved text file, if it exists. Not every error
--- requires additional description.
--- @param error_num string: the original compiler message to parse
--- @return file* | nil
local function get_improved_text_file(error_num)
  local filename = error_num .. ".md"
  local plugin_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h")
  return io.open(plugin_path .. "/better-messages/" .. filename, "r")
end

--- Removes link text from the string, keeping those with relevant text.
--- @param line string
--- @return string
local function parse_out_links(line)
  local link_re = "%[(.+)%]%((.+)%)"
  local link_start, link_end, match = line:find(link_re)
  if link_start == nil or link_end == nil then
    return line
  end

  if match == "Learn more" then
    return line:sub(0, link_start - 2)
  end

  if match == "This article" then
    local sentence_end = line:find("%.", link_end)
    if sentence_end == nil then
      return line:sub(0, link_start - 2) .. line:sub(link_end)
    end
    return line:sub(0, link_start - 2) .. line:sub(sentence_end + 1)
  end

  return line:sub(0, link_start - 1) .. match .. line:sub(link_end + 1)
end

--- @class MDFile
--- @field frontmatter table<string, string>
--- @field body string

--- Returns a markdown file object with frontmatter and content
--- @param md_file file*
--- @return MDFile
local function parse_md_simple(md_file)
  local md = { frontmatter = {}, body = "" }
  local in_frontmatter = false
  for l in md_file:lines("l") do
    if not in_frontmatter and l == "---" then
      in_frontmatter = true
      goto continue
    elseif in_frontmatter and l == "---" then
      in_frontmatter = false
      goto continue
    elseif in_frontmatter then
      local sep_idx = l:find(":")
      local key = l:sub(0, sep_idx - 1)
      local val = l:sub(sep_idx + 3, l:len() - 1)
      md.frontmatter[key] = val
    else
      md.body = md.body .. parse_out_links(l)
    end
    ::continue::
  end

  return md
end

--- Get any slots out of the improved text for matching.
--- @param md MDFile
local function get_improved_text_slots(md)
  local slots = {}
  --- @type integer | nil
  local i = 0
  while true do
    i = md.body:find("%{%d%}", i + 1)
    if i == nil then
      break
    end
    local val = md.body:sub(i, i + 2)
    table.insert(slots, val)
  end
  return slots
end

--- Match a slot with the text from the original message
--- @param slots table<integer, string>
--- @param original_message string
--- @param md_original_message string
--- @return table<string, string>
local function match_slots(slots, original_message, md_original_message)
  local matched_slots = {}
  for i = 1, #slots do
    local idx = md_original_message:find(slots[i])
    local match = original_message:match("%w+", idx)
    matched_slots[slots[i]] = match
  end
  return matched_slots
end

--- Finds and parses a preferred message md file, or returns the existing if no
--- preferred message is available.
--- @param message string: the original compiler message to parse
--- @return string
M.best_message = function(message)
  local error_num, original_message = message:match("^.*TS(%d+):%s(.*)")
  local improved_text_file = get_improved_text_file(error_num)
  if improved_text_file == nil then
    return message
  end

  local md = parse_md_simple(improved_text_file)

  local slots = get_improved_text_slots(md)
  if #slots == 0 then
    return "TS" .. error_num .. ": " .. md.body
  end

  local matched_slots = match_slots(slots, original_message, md.frontmatter["original"])

  local output_message = md.body
  for k, v in pairs(matched_slots) do
    output_message = output_message:gsub(k, v)
  end

  return "TS" .. error_num .. ": " .. output_message
end

return M

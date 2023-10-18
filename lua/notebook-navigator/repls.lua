local repls = {}

-- iron.nvim
repls.iron = function(start_line, end_line, repl_args)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, 0)
  require("iron.core").send(nil, lines)
end

local function is_whitespace(str)
  return str:match("^%s*$") ~= nil
end

-- Function to remove leading and ending whitespace strings
local function trim_whitespace_strings(lines)
  local start_idx, end_idx = 1, #lines

  -- Find the index of the first non-whitespace string
  while start_idx <= #lines and is_whitespace(lines[start_idx]) do
    start_idx = start_idx + 1
  end

  -- Find the index of the last non-whitespace string
  while end_idx >= 1 and is_whitespace(lines[end_idx]) do
    end_idx = end_idx - 1
  end

  -- Create a new table containing only the non-whitespace strings
  local trimmed_lines = {}
  for i = start_idx, end_idx do
    table.insert(trimmed_lines, lines[i])
  end

  return trimmed_lines
end

-- toggleterm
repls.toggleterm = function(start_line, end_line, repl_args)
  local id = 1
  if repl_args then
    id = repl_args.id or 1
  end
  local current_window = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, 0)

  if not lines or not next(lines) then
    return
  end

  local cmd = string.char(15)  -- ^O (shift in)

  for _, line in ipairs(trim_whitespace_strings(lines)) do
    local l = line
    if l == "" then
      cmd = cmd .. string.char(15) .. string.char(14)
    else
      cmd = cmd .. l .. string.char(10)  -- ^J (line feed)
    end
  end
  cmd = cmd .. string.char(4)  -- ^D (end of transmission)
  require("toggleterm").exec(cmd, id)

  -- Jump back with the cursor where we were at the beginning of the selection
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_set_current_win(current_window)

  vim.api.nvim_win_set_cursor(current_window, { cursor_line, cursor_col })
end

-- no repl
repls.no_repl = function(_) end

local get_repl = function(repl_provider)
  local repl_providers = { "iron", "toggleterm" }
  if repl_provider == "auto" then
    for _, r in ipairs(repl_providers) do
      if pcall(require, r) then
        return repls[r]
      end
      vim.notify "[Notebook Navigator] None of the supported REPL providers is available. Please install iron or toggleterm"
    end
  else
    if pcall(require, repl_provider) then
      return repls[repl_provider]
    else
      vim.notify("[Notebook Navigator] The " .. repl_provider .. " REPL provider is not available.")
    end
  end
  return repls["no_repl"]
end

return get_repl

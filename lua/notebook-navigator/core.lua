local commenter = require "notebook-navigator.commenters"
local get_repl = require "notebook-navigator.repls"
local ts_queries = require('nvim-treesitter.query')

local M = {}

M.miniai_spec = function(opts, cell_marker)
  local start_line = vim.fn.search("^" .. cell_marker, "bcnW")

  -- Just in case the notebook is malformed and doesnt  have a cell marker at the start.
  if start_line == 0 then
    start_line = 1
  else
    if opts == "i" then
      start_line = start_line + 1
    end
  end

  local end_line = vim.fn.search("^" .. cell_marker, "nW") - 1
  if end_line == -1 then
    end_line = vim.fn.line "$"
  end

  local last_col = math.max(vim.fn.getline(end_line):len(), 1)

  local from = { line = start_line, col = 1 }
  local to = { line = end_line, col = last_col }

  return { from = from, to = to }
end

M.map_to_range = function(m)
  local range = vim.treesitter.get_range(m.node, buf_id, m.metadata)

  -- map to 1-indexed lines and 0-indexed columns
  local from = { line = range[1] + 1, col = range[2] }
  local to = { line = range[4] + 1, col = range[5] }

  return { from = from, to = to }
end

M.get_toplevels = function()
  local buf_id = vim.api.nvim_get_current_buf()
  local matches = ts_queries.get_capture_matches_recursively(buf_id, '@toplevel', 'toplevels')
  return vim.tbl_map(M.map_to_range, matches)
end

-- Find the toplevel containing the cursor
M.find_toplevel = function()
  -- Get all matched ranges for the toplevels
  local ranges = M.get_toplevels()

  -- Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]  -- the cursor line is 1-indexed in Neovim

  local containing_range = nil
  local next_range = nil

  for _, range in ipairs(ranges) do
    if containing_range then
      -- We need to return the range after the one containing the cursor
      next_range = range
      break
    -- Check if cursor is within this range (only need to check lines)
    elseif cursor_line >= range.from.line and cursor_line <= range.to.line then
      containing_range = range
    end
  end

  return {containing_range = containing_range, next_range = next_range}
end

M.move_cell = function(dir, cell_marker)
  local search_res
  local result

  if dir == "d" then
    search_res = vim.fn.search("^" .. cell_marker, "W")
    if search_res == 0 then
      result = "last"
    end
  else
    search_res = vim.fn.search("^" .. cell_marker, "bW")
    if search_res == 0 then
      result = "first"
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end
  end

  return result
end

M.run_cell = function(cell_marker, repl_provider, repl_args)
  repl_args = repl_args or nil
  repl_provider = repl_provider or "auto"
  local cell_object = M.miniai_spec("i", cell_marker)

  -- protect ourselves against the case with no actual lines of code
  local n_lines = cell_object.to.line - cell_object.from.line + 1
  if n_lines < 1 then
    return nil
  end

  local repl = get_repl(repl_provider)
  repl(cell_object.from.line, cell_object.to.line, repl_args)
end

M.run_and_move = function(cell_marker, repl_provider, repl_args)
  M.run_cell(cell_marker, repl_provider, repl_args)
  local is_last_cell = M.move_cell("d", cell_marker) == "last"

  -- insert a new cell to replicate the behaviour of jupyter notebooks
  if is_last_cell then
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { cell_marker, "" })
    -- and move to it
    M.move_cell("d", cell_marker)
  end
end

M.run_toplevel = function(repl_provider, repl_args)
  repl_args = repl_args or nil
  repl_provider = repl_provider or "auto"
  local cell_object = M.find_toplevel()
  local containing_range = cell_object.containing_range
  local next_range = cell_object.next_range
  if not containing_range then
    return nil
  end

  -- protect ourselves against the case with no actual lines of code
  local n_lines = containing_range.to.line - containing_range.from.line + 1
  if n_lines < 1 then
    return nil
  end

  local repl = get_repl(repl_provider)
  repl(containing_range.from.line, containing_range.to.line, repl_args)
  if next_range then
    -- Move cursor to the beginning of the next range
    vim.api.nvim_win_set_cursor(0, { next_range.from.line, next_range.from.col })
  end
end

M.comment_cell = function(cell_marker)
  local cell_object = M.miniai_spec("i", cell_marker)

  -- protect against empty cells
  local n_lines = cell_object.to.line - cell_object.from.line + 1
  if n_lines < 1 then
    return nil
  end
  commenter(cell_object)
end

M.add_cell_before = function(cell_marker)
  local cell_object = M.miniai_spec("a", cell_marker)

  -- What to do on malformed notebooks? I.e. with no upper cell marker? are they malformed?
  -- What if we have a jupytext header? Code doesn't start at top of buffer.
  vim.api.nvim_buf_set_lines(
    0,
    cell_object.from.line - 1,
    cell_object.from.line - 1,
    false,
    { cell_marker, "" }
  )
  M.move_cell("u", cell_marker)
end

M.add_cell_after = function(cell_marker)
  local cell_object = M.miniai_spec("a", cell_marker)

  vim.api.nvim_buf_set_lines(0, cell_object.to.line, cell_object.to.line, false, { cell_marker, "" })
  M.move_cell("d", cell_marker)
end

return M

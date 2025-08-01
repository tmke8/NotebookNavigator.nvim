local commenter = require "notebook-navigator.commenters"
local get_repl = require "notebook-navigator.repls"
local gen_spec = require('mini.ai').gen_spec

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

-- Define specs for each type
M.class_spec = gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' })
M.function_spec = gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' })
M.block_spec = gen_spec.treesitter({ a = '@block.outer', i = '@block.inner' })
M.statement_spec = gen_spec.treesitter({ a = '@statement.outer', i = '@statement.inner' })

-- Generic function to find the largest range containing the cursor
M.find_largest_containing_range = function(ranges, cursor_line)
  local best_match = nil
  local best_size = -1
  
  for _, range in ipairs(ranges) do
    -- Check if cursor is within this range (only need to check lines)
    if cursor_line >= range.from.line and cursor_line <= range.to.line then
      -- Calculate the size (number of lines)
      local size = range.to.line - range.from.line + 1
      
      if size > best_size then
        best_size = size
        best_match = range
      end
    end
  end
  
  return best_match
end

-- Find the largest text object containing the cursor
M.find_toplevel = function(opts)
  -- Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  
  -- Try to find containing class first
  local class_ranges = M.class_spec(opts)
  local class_match = M.find_largest_containing_range(class_ranges, cursor_line)
  if class_match then
    return class_match
  end
  
  -- If no class contains cursor, try functions
  local function_ranges = M.function_spec(opts)
  local function_match = M.find_largest_containing_range(function_ranges, cursor_line)
  if function_match then
    return function_match
  end
  
  -- If no function contains cursor, try blocks
  local block_ranges = M.block_spec(opts)
  local block_match = M.find_largest_containing_range(block_ranges, cursor_line)
  if block_match then
    return block_match
  end
  
  -- If no block contains cursor, try statements
  local statement_ranges = M.statement_spec(opts)
  local statement_match = M.find_largest_containing_range(statement_ranges, cursor_line)
  if statement_match then
    return statement_match
  end
  
  -- Nothing found
  return nil
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
  local cell_object = M.find_toplevel("a")
  if not cell_object then
    return nil
  end

  -- protect ourselves against the case with no actual lines of code
  local n_lines = cell_object.to.line - cell_object.from.line + 1
  if n_lines < 1 then
    return nil
  end

  local repl = get_repl(repl_provider)
  repl(cell_object.from.line, cell_object.to.line, repl_args)
  -- Move cursor to the end of the text object
  vim.api.nvim_win_set_cursor(0, { cell_object.to.line, cell_object.to.col })
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

local commenter = require "notebook-navigator.commenters"
local get_repl = require "notebook-navigator.repls"
local ts = vim.treesitter
local ts_range = ts._range or require('nvim-treesitter-textobjects._range')

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
  -- local range = vim.treesitter.get_range(m.node, buf_id, m.metadata)
  local range = m

  -- map to 1-indexed lines and 0-indexed columns
  local from = { line = range[1] + 1, col = range[2] }
  local to = { line = range[4] + 1, col = range[5] }

  return { from = from, to = to }
end

---@param object table
---@param path string[]
---@param value table
local function insert_to_path(object, path, value)
  ---@type table<string, any|table<string, any>>
  local curr_obj = object

  for index = 1, (#path - 1) do
    if curr_obj[path[index]] == nil then
      curr_obj[path[index]] = {}
    end

    ---@type table<string, any|table<string, any>>
    curr_obj = curr_obj[path[index]]
  end

  ---@type table<string, any|table<string, any>>
  curr_obj[path[#path]] = value
end

---Memoize a function using hash_fn to hash the arguments.
---@generic F: function
---@param fn F
---@param hash_fn fun(...): any
---@return F
local function memoize(fn, hash_fn)
  local cache = setmetatable({}, { __mode = 'kv' }) ---@type table<any,any>

  return function(...)
    local key = hash_fn(...)
    if cache[key] == nil then
      local v = fn(...) ---@type any
      cache[key] = v ~= nil and v or vim.NIL
    end

    local v = cache[key]
    return v ~= vim.NIL and v or nil
  end
end

--- Prepare matches for given query_group and parsed tree
--- memoize by buffer tick and query group
---
---@param bufnr integer the buffer
---@param query_group string the query file to use
---@param root TSNode the root node
---@param root_lang string the root node lang, if known
---@return table[]
local get_query_matches = memoize(function(bufnr, query_group, root, root_lang)
  local query = ts.query.get(root_lang, query_group)
  if not query then
    return {}
  end

  local matches = {} ---@type table[]
  local start_row, _, end_row, _ = root:range()
  -- The end row is exclusive so we need to add 1 to it.
  for pattern, match, metadata in query:iter_matches(root, bufnr, start_row, end_row + 1) do
    if pattern then
      local prepared_match = {}

      -- Extract capture names from each match
      for id, nodes in pairs(match) do
        local query_name = query.captures[id] -- name of the capture in the query
        if query_name ~= nil then
          local path = vim.split(query_name, '%.')
          if metadata[id] and metadata[id].range then
            insert_to_path(prepared_match, path, ts_range.add_bytes(bufnr, metadata[id].range))
          else
            local srow, scol, sbyte, erow, ecol, ebyte = nodes[1]:range(true)
            if #nodes > 1 then
              local _, _, _, e_erow, e_ecol, e_ebyte = nodes[#nodes]:range(true)
              erow = e_erow
              ecol = e_ecol
              ebyte = e_ebyte
            end
            insert_to_path(prepared_match, path, { srow, scol, sbyte, erow, ecol, ebyte })
          end
        end
      end

      if metadata.range and metadata.range[7] then
        ---@cast metadata TSTextObjects.Metadata
        local query_name = metadata.range[7]
        local path = vim.split(query_name, '%.')
        insert_to_path(prepared_match, path, {
          metadata.range[1],
          metadata.range[2],
          metadata.range[3],
          metadata.range[4],
          metadata.range[5],
          metadata.range[6],
        })
      end

      matches[#matches + 1] = prepared_match
    end
  end
  return matches
end, function(bufnr, query_group, root)
  return string.format('%d-%s-%s', bufnr, root:id(), query_group)
end)

---@param tbl table<string, any|table<string, any>> the table to access
---@param path string the '.' separated path
---@return any|nil result the value at path or nil
local function get_at_path(tbl, path)
  if path == '' then
    return tbl
  end

  local segments = vim.split(path, '%.')
  local result = tbl

  for _, segment in ipairs(segments) do
    if type(result) == 'table' then
      ---@type any
      result = result[segment]
    end
  end

  return result
end

---@param bufnr integer
---@param query_string string
---@param query_group string
---@return Range6[]
local function get_capture_ranges_recursively(bufnr, query_string, query_group)
  if query_string:sub(1, 1) ~= '@' then
    error('Captures must start with "@"')
    return {}
  end
  query_string = query_string:sub(2)

  local parser = ts.get_parser(bufnr)
  if not parser then
    return {}
  end
  parser:parse(true)

  local ranges = {} ---@type Range6[]
  parser:for_each_tree(function(tree, lang_tree)
    local tree_lang = lang_tree:lang()

    local matches = get_query_matches(bufnr, query_group, tree:root(), tree_lang)
    for _, match in pairs(matches) do
      local found = get_at_path(match, query_string)
      if found then
        ---@cast found Range6
        table.insert(ranges, found)
      end
    end
  end)

  return ranges
end

M.get_toplevels = function()
  local buf_id = vim.api.nvim_get_current_buf()
  local matches = get_capture_ranges_recursively(buf_id, '@toplevel', 'toplevels')
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
  else
    -- If there is no next range, move to the end of the current range
    vim.api.nvim_win_set_cursor(0, { containing_range.to.line, containing_range.to.col })
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

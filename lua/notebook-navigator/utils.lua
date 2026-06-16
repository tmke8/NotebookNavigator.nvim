local utils = {}

---Get cell marker for a given buffer and cell markers table.
---The function checks the filetype of the buffer and returns the corresponding cell
---marker from the cell markers table. If the filetype is empty or if there's no cell
---marker defined for the filetype, it raises an error.
---@param bufnr integer
---@param cell_markers table<string, string> A table mapping filetypes to their corresponding cell markers.
---@return string The cell marker for the buffer's filetype.
utils.get_cell_marker = function(bufnr, cell_markers)
  local ft = vim.bo[bufnr].filetype

  if ft == nil or ft == "" then
    error "Empty filetype"
  elseif cell_markers[ft] == nil then
    error("There's no cell marker defined for filetype " .. ft)
  end

  return cell_markers[ft]
end

return utils

-- Start typing a comment inline, on the line below, or on the line above.
-- The comment marker is resolved the way built-in `gc` resolves it, so it follows
-- the filetype, the treesitter node under the cursor, and any injected language
-- such as a fenced code block inside markdown.

local M = {}

-- The same lookup `gc` performs: treesitter capture metadata first, then the
-- deepest injected language that has a commentstring, then the buffer option.
-- Neovim keeps this private in vim/_comment.lua, so it is mirrored here. The
-- vim.filetype.get_option call is what ts-comments.nvim hooks, which is how the
-- per-node overrides reach this code.
local function commentstring_at_cursor()
  local buf_cs = vim.bo.commentstring
  local ok, parser = pcall(vim.treesitter.get_parser, 0, "")
  if not ok or not parser then
    return buf_cs
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local caps = vim.treesitter.get_captures_at_pos(0, row, 0)
  for i = #caps, 1, -1 do
    local id, metadata = caps[i].id, caps[i].metadata
    local md_cs = metadata["bo.commentstring"] or metadata[id] and metadata[id]["bo.commentstring"]
    if md_cs then
      return md_cs
    end
  end

  local range = { row, 0, row, 1 }
  local found
  local function traverse(tree)
    if not tree:contains(range) then
      return
    end
    for _, ft in ipairs(vim.treesitter.language.get_filetypes(tree:lang())) do
      local cs = vim.filetype.get_option(ft, "commentstring")
      if cs ~= "" then
        found = cs
      end
    end
    for _, child in pairs(tree:children()) do
      traverse(child)
    end
  end
  traverse(parser)

  return found or buf_cs
end

-- `open` is the normal-mode key that starts insert mode: "o", "O" or "A".
local function insert_comment(open)
  local cs = commentstring_at_cursor()
  if type(cs) ~= "string" or not cs:find("%%s") then
    vim.api.nvim_echo({ { "Option 'commentstring' is empty.", "WarningMsg" } }, true, {})
    return
  end
  local left, right = cs:match("^(.-)%%s(.-)$")
  left, right = vim.trim(left), vim.trim(right)

  -- Separate the comment from code already on the line.
  local lead = ""
  if open == "A" then
    local line = vim.api.nvim_get_current_line()
    lead = (line == "" or line:match("%s$")) and "" or " "
  end

  -- Two spaces around the cursor when there is a closing marker, so the comment
  -- reads `<!-- text -->` once you type.
  local text = left .. " " .. (right ~= "" and " " .. right or "")
  -- <C-g>U keeps the whole insert in one undo block; a bare <Left> would split it.
  local back = right ~= "" and string.rep("<C-g>U<Left>", vim.fn.strchars(right) + 1) or ""

  -- Typing the comment rather than writing the buffer means the indent comes from
  -- the filetype indent plugin, exactly as if `o`, `O` or `A` had been pressed.
  local keys = vim.api.nvim_replace_termcodes(open .. lead .. text .. back, true, false, true)
  -- "n" so insert-mode plugins such as mini.pairs do not rewrite the markers,
  -- "i" so the keys run ahead of anything already waiting in the typeahead.
  vim.api.nvim_feedkeys(keys, "ni", false)
end

function M.below()
  insert_comment("o")
end

function M.above()
  insert_comment("O")
end

function M.eol()
  insert_comment("A")
end

return M

-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Run prettier even when no project-local prettier config is present.
vim.g.lazyvim_prettier_needs_config = false

-- Clipboard via OSC 52, everywhere.
-- LazyVim blanks `clipboard` under SSH (lua/lazyvim/config/options.lua), so a plain
-- `y`/`yy` only fills nvim's internal register and never leaves the session. This file
-- loads *after* LazyVim's defaults, so we re-enable it here and force the built-in OSC 52
-- provider unconditionally: the provider emits the escape itself, so it works outside
-- tmux (straight to the terminal) and inside it (tmux forwards OSC 52 when set-clipboard
-- is on). No pbcopy/xclip/wl-copy needed, so it's identical on macOS, local Linux, and
-- the headless VPS. Paste reads the last yank instead of querying the terminal (OSC 52
-- read is unreliable and can hang).
vim.opt.clipboard = "unnamedplus"
local osc52 = require("vim.ui.clipboard.osc52")
local function paste_last()
  return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end
vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = { ["+"] = paste_last, ["*"] = paste_last },
}

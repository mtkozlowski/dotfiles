-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Black-hole register: delete/paste without clobbering the unnamed (yank) register.
-- <leader>p over a visual selection pastes WITHOUT yanking what it replaced,
-- so you can paste the same text over several selections in a row.
-- <leader>D deletes to the black hole (operator-pending in normal mode, the
-- selection in visual) instead of into the yank register.
-- Capital D is deliberate: <leader>x is LazyVim's Trouble/quickfix group, and
-- <leader>d would become the debug group if the LazyVim DAP extra is enabled.
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste over selection (keep yank)" })
vim.keymap.set({ "n", "v" }, "<leader>D", [["_d]], { desc = "Delete to black hole (keep yank)" })

-- Cycle background dark → light → auto (auto follows the system appearance).
-- The pinned choice persists across restarts and survives the FocusGained system
-- re-sync; "auto" un-pins (see lua/config/colorscheme.lua). Overrides LazyVim's
-- default <leader>ub.
--
-- LazyVim maps <leader>ub to a Snacks "Dark Background" on/off toggle, which also
-- registers a which-key label ("Enable/Disable Dark Background"). Overriding the
-- keymap alone changes the action but not that label, so we re-register the
-- which-key entry after Snacks does (on_module preserves order; our config loads
-- after LazyVim's, so ours wins) to get a clean, accurate label.
vim.keymap.set("n", "<leader>ub", "<cmd>BackgroundCycle<cr>", { desc = "Cycle background: dark/light/auto" })
require("snacks").util.on_module("which-key", function()
  require("which-key").add({
    { "<leader>ub", desc = "Cycle background: dark/light/auto", icon = { icon = "󰔎", color = "yellow" } },
  })
end)

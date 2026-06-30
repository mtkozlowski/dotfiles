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

-- Split a bracketed construct across lines, or join it back onto one. It reads
-- the treesitter tree, so an object, a parameter list, an array, a list of
-- named imports and a set of JSX props are each understood as the shape they
-- are. A language needs its treesitter parser installed for this to have
-- anything to work on.
--
-- `gS` toggles. `<leader>cS` always splits and `<leader>cJ` always joins, which
-- are the ones to reach for when the current state is hard to see. `gs` belongs
-- to mini.surround and `<leader>m` to the markdown preview in
-- lua/plugins/md-render.lua, and `use_default_keymaps = false` leaves the
-- built-in `gJ` (join without inserting spaces) alone.
return {
  {
    "wansmer/treesj",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    keys = {
      { "gS", function() require("treesj").toggle() end, desc = "Split/Join Node" },
      { "<leader>cS", function() require("treesj").split() end, desc = "Split Node" },
      { "<leader>cJ", function() require("treesj").join() end, desc = "Join Node" },
    },
    opts = {
      use_default_keymaps = false,
      -- A join that would produce a line longer than this is refused. 0 lifts
      -- the limit.
      max_join_length = 240,
    },
  },
}

-- The colorschemes are installed here; the active one (and light/dark switching)
-- is driven by lua/config/colorscheme.lua. Toggle with `:ColorschemeToggle`.
return {
  {
    -- Light half of the gruvbox-material choice, matching Ghostty's light theme.
    "rose-pine/neovim",
    name = "rose-pine",
    lazy = false,
    priority = 1000,
  },
  {
    "sainnhe/gruvbox-material",
    lazy = false,
    priority = 1000,
    init = function()
      -- gruvbox-material options must be set before the colorscheme is applied.
      vim.g.gruvbox_material_background = "medium" -- soft | medium | hard
      vim.g.gruvbox_material_better_performance = 1
      vim.g.gruvbox_material_foreground = "material" -- material | original | mix
    end,
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    -- Ensure the other colorschemes are loaded too, so the controller can switch to them.
    dependencies = { "sainnhe/gruvbox-material", "rose-pine/neovim" },
    opts = {
      flavour = "auto",
      -- dark options: frappe, macchiato, mocha
      background = { light = "latte", dark = "macchiato" },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      -- All colorschemes are now available; wire up sync + toggle.
      require("config.colorscheme").setup()
    end,
  },
}

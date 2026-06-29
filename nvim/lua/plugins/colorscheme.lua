-- Both colorschemes are installed; the active one (and light/dark switching) is
-- driven by lua/config/colorscheme.lua. Toggle with `:ColorschemeToggle`.
return {
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
    -- Ensure gruvbox-material is loaded too, so the controller can switch to it.
    dependencies = { "sainnhe/gruvbox-material" },
    opts = {
      flavour = "auto",
      -- dark options: frappe, macchiato, mocha
      background = { light = "latte", dark = "macchiato" },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      -- Both colorschemes are now available; wire up sync + toggle.
      require("config.colorscheme").setup()
    end,
  },
}

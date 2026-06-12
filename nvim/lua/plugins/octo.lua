-- octo.nvim — review and comment on GitHub PRs/issues from inside nvim.
-- Launched from gh-dash via:  nvim -c "silent Octo pr edit {{.PrNumber}}"
return {
  {
    "pwntester/octo.nvim",
    cmd = "Octo", -- lazy-load on first :Octo (covers the `-c "Octo ..."` launch)
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      picker = "snacks", -- match LazyVim's default picker (no telescope/fzf-lua here)
    },
  },
}

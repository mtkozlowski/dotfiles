return {
  "delphinus/md-render.nvim",
  version = "*",
  ft = { "markdown" },
  keys = {
    {
      "<leader>mp",
      function()
        local cap = 140
        local margin = 4
        local width = math.min(vim.o.columns - margin, cap)
        require("md-render").preview.show({ max_width = width })
      end,
      desc = "Markdown preview (toggle)",
    },
    {
      "<leader>mt",
      function()
        require("md-render").preview.show_tab({ max_width = math.min(vim.o.columns - 4, 140) })
      end,
      desc = "Markdown preview in tab (toggle)",
    },
    {
      "<leader>mr",
      function()
        require("md-render").preview.toggle({ max_width = math.min(vim.o.columns - 4, 140) })
      end,
      desc = "Markdown render in place (toggle)",
    },
    {
      "<leader>ma",
      function()
        require("md-render").preview.auto_toggle({ max_width = math.min(vim.o.columns - 4, 140) })
      end,
      desc = "Markdown render auto-toggle (Insert-aware)",
    },
  },
}

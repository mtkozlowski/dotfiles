return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    lazy = false,
    opts = {
      flavour = "auto",
      background = { light = "latte", dark = "mocha" },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)

      -- macOS exposes the system appearance via `defaults`. On platforms
      -- without it (Linux), `vim.fn.system` with a list would throw E475
      -- because the binary isn't executable, so bail out and return nil.
      local function macos_is_dark()
        if vim.fn.executable("defaults") == 0 then
          return nil
        end
        local out = vim.fn.system({ "defaults", "read", "-g", "AppleInterfaceStyle" })
        return vim.v.shell_error == 0 and out:match("Dark") ~= nil
      end

      local function sync()
        local dark = macos_is_dark()
        if dark ~= nil then
          local want = dark and "dark" or "light"
          if vim.o.background ~= want then
            vim.o.background = want
          end
        end
        vim.cmd.colorscheme("catppuccin")
      end

      sync()

      vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
        group = vim.api.nvim_create_augroup("macos_theme_sync", { clear = true }),
        callback = sync,
      })
    end,
  },
}

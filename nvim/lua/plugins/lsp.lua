-- LSP overrides: how a diagnostic is drawn, and what <leader>ca opens.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      -- A diagnostic is drawn on its own line under the code, wrapped in full,
      -- and only for the line the cursor sits on. The sign column still marks
      -- every affected line, so the rest of the file's problems stay visible.
      -- Text below the cursor shifts down by a line while one is on screen.
      --
      -- `virtual_lines` is built into Neovim from 0.11 on. LazyVim hands this
      -- table to `vim.diagnostic.config` and guards its prefix-icons block on
      -- `virtual_text` being a table, so `false` is safe here.
      diagnostics = {
        virtual_text = false,
        virtual_lines = { current_line = true },
      },
      servers = {
        -- `servers["*"].keys` is where LazyVim 16 takes an LSP keymap.
        -- `opts_extend = { "servers.*.keys" }` appends this entry after
        -- LazyVim's own, and lazy.nvim's key resolver gives an lhs to the last
        -- entry that claims it.
        ["*"] = {
          keys = {
            {
              "<leader>ca",
              function()
                require("tiny-code-action").code_action({
                  -- Only actions that apply at the cursor reach the list, and
                  -- the previews depend on it.
                  --
                  -- TypeScript answers a code action request with every
                  -- refactor it knows, tagging the ones that do not fit the
                  -- cursor with a `notApplicableReason`, which vtsls forwards
                  -- as the LSP `disabled` field. At an ordinary line that is
                  -- most of the list, 14 of 16 in one measurement. Asking a
                  -- disabled refactor for its edits makes tsserver throw
                  -- ("Expected applicable refactor info"), and that RPC error
                  -- is what fills the preview pane.
                  --
                  -- Nothing usable is lost. Neovim's own menu labels these
                  -- "(disabled)" and declines to apply them. Quick fixes are
                  -- untouched: vtsls sets `disabled` on refactors only.
                  --
                  -- A `refactor.move` action passes the filter and carries a
                  -- command rather than an edit, so it applies on Enter and
                  -- has no diff to show. Adding
                  -- `and not vim.startswith(action.kind or "", "refactor.move")`
                  -- keeps those out too.
                  filter = function(action)
                    return action.disabled == nil
                  end,
                })
              end,
              desc = "Code Action",
              mode = { "n", "x" },
              has = "codeAction",
            },
          },
        },
      },
    },
  },
  {
    -- <leader>ca previews each code action as a diff of the edit it would make.
    "rachartier/tiny-code-action.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "LspAttach",
    opts = {
      -- The Snacks picker, which every other list in this config uses.
      picker = "snacks",
      -- delta colours the diff and has to be on PATH. `backend = "vim"` runs
      -- with no external binary.
      backend = "delta",
    },
  },
}

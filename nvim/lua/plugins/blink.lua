-- Completion also draws from ripgrep across the project, so a name defined in
-- a file that was never opened still completes. Such an entry is labelled
-- Ripgrep in the menu, and its documentation window carries the lines around
-- the match in the file it came from.
--
-- LazyVim's blink extra declares `sources.default` in `opts_extend`, so naming
-- "ripgrep" here appends to the default sources.
return {
  {
    "saghen/blink.cmp",
    dependencies = { "mikavilpas/blink-ripgrep.nvim" },
    opts = {
      sources = {
        default = { "ripgrep" },
        providers = {
          ripgrep = {
            module = "blink-ripgrep",
            name = "Ripgrep",
            -- Ranked below LSP and snippets, so a language server that knows
            -- the answer leads the menu.
            score_offset = -3,
            opts = {
              -- Three characters before the first search, which keeps typing
              -- from grepping the project on every keystroke.
              prefix_min_len = 3,
              -- The nearest `.git` is both the root it walks up to and the
              -- boundary of the search.
              project_root_marker = ".git",
              backend = {
                use = "ripgrep",
                -- Lines either side of the match in the documentation window.
                context_size = 5,
                ripgrep = {
                  max_filesize = "1M",
                },
              },
            },
          },
        },
      },
    },
  },
}

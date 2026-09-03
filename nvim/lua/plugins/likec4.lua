-- likec4.nvim — syntax highlighting and LSP for LikeC4 architecture-as-code files.
-- The plugin ships its own ftdetect/ftplugin/lsp files and calls vim.lsp.enable("likec4"),
-- so there is no setup() to call.
return {
  {
    "likec4/likec4.nvim",
    -- The standalone server, not the full `likec4` CLI the plugin's readme installs.
    build = "npm install -g @likec4/lsp",
    -- Not lazy-loaded: the filetype for *.c4 comes from this plugin's own ftdetect,
    -- so it has to be on the runtimepath before the buffer is read.
    lazy = false,
    init = function()
      -- The plugin only claims *.c4; LikeC4 also uses the *.likec4 extension.
      vim.filetype.add({ extension = { likec4 = "likec4" } })
    end,
    config = function()
      -- Point at the standalone binary. The plugin's lsp/likec4.lua asks for
      -- `likec4 lsp --stdio`, which needs the whole CLI on PATH.
      vim.lsp.config("likec4", { cmd = { "likec4-lsp", "--stdio" } })
    end,
  },
}

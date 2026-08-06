return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function truncate(max)
        return function(str)
          if #str > max then
            return str:sub(1, max - 1) .. "…"
          end
          return str
        end
      end

      -- 1) Cap the git branch length
      for i, comp in ipairs(opts.sections.lualine_b or {}) do
        if comp == "branch" or (type(comp) == "table" and comp[1] == "branch") then
          opts.sections.lualine_b[i] = { "branch", fmt = truncate(24) }
        end
      end

      -- 2) Tame the trouble "symbols" breadcrumb in lualine_c:
      --    cap its length and only show it when the window is wide enough.
      --    LazyVim appends it as the last lualine_c entry, only when enabled,
      --    so target that entry specifically instead of the whole section
      --    (otherwise this also hides the filename/pretty_path component).
      if vim.g.trouble_lualine and LazyVim.has("trouble.nvim") then
        local lualine_c = opts.sections.lualine_c or {}
        local trouble_comp = lualine_c[#lualine_c]
        if trouble_comp then
          trouble_comp.fmt = truncate(40)
          trouble_comp.cond = function()
            return vim.o.columns > 120
          end
        end
      end
    end,
  },
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = true,
      },
    },
  },
}

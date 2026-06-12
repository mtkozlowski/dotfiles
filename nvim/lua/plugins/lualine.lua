return {
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
    for _, comp in ipairs(opts.sections.lualine_c or {}) do
      if type(comp) == "table" then
        comp.fmt = truncate(40)
        comp.cond = function()
          return vim.o.columns > 120
        end
      end
    end
  end,
}

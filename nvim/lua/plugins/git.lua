-- The line under the cursor trails who last changed it, how long ago, and the
-- commit summary, as virtual text at the end of the line. It reads from git
-- history, so a tracked file is the requirement and an untracked one shows
-- nothing. `<leader>ghb` gives the full blame for one line on demand.
return {
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 300,
        virt_text_pos = "eol",
      },
    },
  },
}

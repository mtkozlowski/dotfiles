-- Central colorscheme controller.
--
-- Owns two concerns:
--   1. light/dark follows the macOS system appearance (both catppuccin and
--      gruvbox-material honor `vim.o.background`, so we only flip that)
--   2. which colorscheme is active is a persisted, runtime-toggleable choice
--
-- The chosen scheme is saved to stdpath("data")/colorscheme so it survives
-- restarts. Use `:ColorschemeToggle` to flip between the two.

local M = {}

local STATE_FILE = vim.fn.stdpath("data") .. "/colorscheme"
local SCHEMES = { "catppuccin", "gruvbox-material" }
local DEFAULT = SCHEMES[1]

local function read_choice()
  local f = io.open(STATE_FILE, "r")
  if not f then
    return DEFAULT
  end
  local name = vim.trim(f:read("*l") or "")
  f:close()
  return vim.tbl_contains(SCHEMES, name) and name or DEFAULT
end

local function write_choice(name)
  local f = io.open(STATE_FILE, "w")
  if f then
    f:write(name)
    f:close()
  end
end

-- macOS exposes the system appearance via `defaults`. On platforms without it
-- (Linux), `vim.fn.system` with a list would throw E475 because the binary
-- isn't executable, so bail out and return nil ("can't tell").
local function macos_is_dark()
  if vim.fn.executable("defaults") == 0 then
    return nil
  end
  local out = vim.fn.system({ "defaults", "read", "-g", "AppleInterfaceStyle" })
  return vim.v.shell_error == 0 and out:match("Dark") ~= nil
end

M.current = read_choice()

-- Apply system light/dark, then (re)apply the active colorscheme.
function M.sync()
  local dark = macos_is_dark()
  if dark ~= nil then
    local want = dark and "dark" or "light"
    if vim.o.background ~= want then
      vim.o.background = want
    end
  end
  -- catppuccin (flavour = "auto") and gruvbox-material both follow `background`.
  pcall(vim.cmd.colorscheme, M.current)
end

function M.set(name)
  if not vim.tbl_contains(SCHEMES, name) then
    vim.notify("Unknown colorscheme: " .. tostring(name), vim.log.levels.WARN)
    return
  end
  M.current = name
  write_choice(name)
  M.sync()
end

function M.toggle()
  local idx = 1
  for i, name in ipairs(SCHEMES) do
    if name == M.current then
      idx = i
      break
    end
  end
  local next_name = SCHEMES[(idx % #SCHEMES) + 1]
  M.set(next_name)
  vim.notify("Colorscheme: " .. next_name)
end

-- Called once both colorscheme plugins are loaded.
function M.setup()
  M.sync()

  vim.api.nvim_create_user_command("ColorschemeToggle", function()
    M.toggle()
  end, { desc = "Toggle between catppuccin and gruvbox-material" })

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = vim.api.nvim_create_augroup("system_theme_sync", { clear = true }),
    callback = M.sync,
  })
end

return M

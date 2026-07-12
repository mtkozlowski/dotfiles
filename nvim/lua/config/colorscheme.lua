-- Central colorscheme controller.
--
-- Owns two concerns:
--   1. light/dark: follows the macOS system appearance by default, but can be
--      pinned manually to dark/light (both catppuccin and gruvbox-material honor
--      `vim.o.background`, so we only flip that). `:BackgroundCycle` steps through
--      dark → light → auto; `:Background dark|light|auto` sets one directly.
--   2. which colorscheme is active is a persisted, runtime-toggleable choice.
--      Use `:ColorschemeToggle` to flip between the two.
--
-- Both choices are saved under stdpath("data") so they survive restarts.

local M = {}

local STATE_FILE = vim.fn.stdpath("data") .. "/colorscheme"
local BG_FILE = vim.fn.stdpath("data") .. "/background"
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

-- Background override: "auto" (follow the system), "dark", or "light".
-- When pinned to dark/light it wins over the system appearance, so a manual
-- choice survives the FocusGained re-sync instead of snapping back.
local function read_bg_override()
  local f = io.open(BG_FILE, "r")
  if not f then
    return "auto"
  end
  local v = vim.trim(f:read("*l") or "")
  f:close()
  return (v == "dark" or v == "light") and v or "auto"
end

local function write_bg_override(mode)
  local f = io.open(BG_FILE, "w")
  if f then
    f:write(mode)
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
M.bg_override = read_bg_override()

-- Apply light/dark, then (re)apply the active colorscheme.
function M.sync()
  local want
  if M.bg_override == "dark" or M.bg_override == "light" then
    want = M.bg_override -- manual pin wins over the system appearance
  else
    local dark = macos_is_dark()
    if dark ~= nil then
      want = dark and "dark" or "light"
    end
  end
  if want and vim.o.background ~= want then
    vim.o.background = want
  end
  -- catppuccin (flavour = "auto") and gruvbox-material both follow `background`.
  pcall(vim.cmd.colorscheme, M.current)
end

-- Pin the background to "dark"/"light", or "auto" to follow the system again.
function M.set_background(mode)
  if mode ~= "dark" and mode ~= "light" and mode ~= "auto" then
    vim.notify("Usage: :Background dark|light|auto", vim.log.levels.WARN)
    return
  end
  M.bg_override = mode
  write_bg_override(mode)
  M.sync()
end

-- Cycle the override: dark → light → auto → dark. "auto" un-pins and follows
-- the system appearance again (see M.sync).
function M.cycle_background()
  local next_mode = ({ dark = "light", light = "auto", auto = "dark" })[M.bg_override] or "dark"
  M.set_background(next_mode)
  if next_mode == "auto" then
    vim.notify("Background: auto — following system (" .. vim.o.background .. ")")
  else
    vim.notify("Background: " .. next_mode .. " (pinned)")
  end
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

  vim.api.nvim_create_user_command("BackgroundCycle", function()
    M.cycle_background()
  end, { desc = "Cycle background: dark → light → auto" })

  vim.api.nvim_create_user_command("Background", function(o)
    M.set_background(vim.trim(o.args))
  end, {
    nargs = 1,
    complete = function()
      return { "dark", "light", "auto" }
    end,
    desc = "Set background: dark | light | auto (follow system)",
  })

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = vim.api.nvim_create_augroup("system_theme_sync", { clear = true }),
    callback = M.sync,
  })
end

return M

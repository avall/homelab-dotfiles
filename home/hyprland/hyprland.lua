-- Hyprland entry point.
--
-- Deliberately tiny. Hyprland generates its own hyprland.lua the first time it
-- starts with nothing in ~/.config/hypr, and the generated file has no way to
-- reach ours — so instead of appending a require() to a generated, unversioned
-- file, this repo owns the entry point and the generated one never appears.
-- install.sh backs up a pre-existing one before symlinking this in.
--
-- require() resolves against the config directory: Hyprland prepends
-- "<configdir>/?.lua" to package.path, and tracks every required file so live
-- reload keeps working across all of them.
--
-- Order matters. hypr_extra is ours; the two after it are written by
-- nwg-displays and must come last so an explicit monitor layout overrides the
-- catch-all rule in hypr_extra.
require("hypr_extra")
require("monitors")
require("workspaces")

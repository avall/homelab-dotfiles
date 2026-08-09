-- Monitor layout, required from hyprland.lua.
--
-- MANAGED BY nwg-displays: it rewrites this whole file, comments included,
-- every time you press Apply, and writes it alongside the .conf variant.
-- Keep notes in hypr_extra.lua, which the GUI never touches.
--
-- The catch-all below is the starting point on a machine that has not run
-- nwg-displays yet: an empty output name matches every screen, each placed to
-- the right of the previous one at its preferred mode. That already drives
-- three monitors. Turn on "use monitor descriptions" in nwg-displays before
-- saving, so rules key on the display's EDID rather than the port.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

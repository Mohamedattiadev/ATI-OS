-- ============================================================
--  hyprglass — Lua form
--
--  The video author's setup keeps hyprglass settings in a separate
--  modules/plugins.lua required from hyprland.lua.  He also lost two
--  hours to having commented out that require line, so if you split
--  this out further: CHECK THE REQUIRE IS ACTUALLY UNCOMMENTED.
--
--  Prefer this over hyprglass.conf if your Hyprland config is Lua —
--  the .conf form is marked deprecated as of Hyprland 0.55 and the
--  plugin author expects to drop it within a release or two.
--
--  Not loaded by default; hyprglass is not installed yet.
--  See hyprglass.conf's header for the install + version check.
-- ============================================================

local hg = hl.plugin.hyprglass

-- ------------------------------------------------------------
--  Apple preset — restraint over spectacle
--
--  The plugin's defaults are already calibrated near Apple's look,
--  so these sit deliberately close to them.  Apple's material is
--  desaturated, low contrast, gentle refraction: it sits behind your
--  content and stays out of the way.
-- ------------------------------------------------------------
hg.preset = "apple"

hg.blur_strength = 1.0
hg.refraction_strength = 0.35   -- the setting that separates glass from blur
hg.chromatic_aberration = 0.3   -- author's own preset pushes this to 0.8
hg.lens_distortion = 0.25       -- his goes to 0.9, "almost maximum dome"
hg.fresnel_strength = 0.5
hg.specular_strength = 0.4
hg.edge_thickness = 0.18        -- where "middle = blur" becomes "edge = glass"
hg.glass_opacity = 0.85

hg.brightness = 1.0
hg.contrast = 0.95              -- Apple sits below 1.0; his glass preset is 1.7
hg.saturation = 0.9
hg.vibrancy = 0.12              -- his glass preset is 0.8

-- The adaptive half: what makes it hold up over any wallpaper.
hg.adaptive_dim = 0.35          -- pulls bright areas down, dark themes stay readable
hg.adaptive_boost = 0.25        -- lifts dark areas, light themes don't go muddy

-- 0xRRGGBBAA — the last two digits are alpha.
-- Once theme-apply gains a Hyprland target this becomes wallpaper-derived,
-- which is what the video author does with his own colours file.
hg.tint_color = 0x11111b40

-- ------------------------------------------------------------
--  Layer surfaces — OFF until the Quickshell bar exists.
--
--  THE TRAP: each hg.layer() call WHITELISTS that namespace.  A config
--  whose only call is an exclude leaves the whitelist empty, and an
--  empty whitelist glasses every layer on the system — exclusions are
--  evaluated first, then an empty filter returns true for everything.
--
--  So whitelist deliberately, and give every entry a threshold.
--
--  SECOND TRAP: the effect masks to visible content by alpha, and
--  shadows count as visible content.  The 0.001 default means a widget
--  with a drop shadow gets a glass rectangle around its shadow box.
--  Start at 0.05 and raise until it dies.  The author tried 0.3 then
--  0.7 on his Quickshell surfaces and ended up excluding them outright.
-- ------------------------------------------------------------
hg.layers_enabled = false
hg.mask_threshold = 0.05

-- When the bar lands, the shape is:
--   hg.layer("quickshell", { mask_threshold = 0.3 })
--   hg.layer("notifications", { mask_threshold = 0.05 })
-- and if artifacts persist:
--   hg.layer("quickshell", { exclude = true })

-- ------------------------------------------------------------
--  Per-window control
-- ------------------------------------------------------------
-- Glass over video playback is wasted GPU and looks wrong.
hl.windowrule({ match = { class = "mpv" }, tag = "+hyprglass_disabled" })
hl.windowrule({ match = { fullscreen = true }, tag = "+hyprglass_disabled" })

-- Light glass in the browser, punchy high-contrast glass on the terminal.
hl.windowrule({ match = { class = "firefox" }, tag = "hyprglass_theme_light" })
hl.windowrule({ match = { class = "brave-browser" }, tag = "hyprglass_theme_light" })
hl.windowrule({ match = { class = "kitty" }, tag = "hyprglass_preset_high_contrast" })

-- Live tuning loop — tag, look, adjust, no reload:
--   hl.dsp.window("+hyprglass_preset_subtle")

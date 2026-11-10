-- Personal additions (fork only)
local vars    = require("variables")
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

-- Per-monitor wallpapers via awww (restores last wallpaper on each monitor)
hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
end)

-- Wallpaper picker (applies to the focused monitor)
hl.bind(vars.kbWallpaper, hl.dsp.exec_cmd(scripts .. "/wallpaper-picker.sh"))

-- Personal additions (fork only)
local vars    = require("variables")
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
    -- Per-monitor wallpapers via awww (restores last wallpaper on each monitor)
    hl.exec_cmd("awww-daemon")

    -- Keep Awake on by default (no idle lock/screen-off/sleep).
    -- Toggle it off in the utilities popup when you want auto-sleep.
    -- Retries until the caelestia shell's IPC is up.
    hl.exec_cmd("sh -c 'for i in $(seq 60); do qs -c caelestia ipc call idleInhibitor enable 2>/dev/null && exit; sleep 1; done'")
end)

-- Wallpaper picker (applies to the focused monitor)
hl.bind(vars.kbWallpaper, hl.dsp.exec_cmd(scripts .. "/wallpaper-picker.sh"))

-- Lid: logind ignores it (no suspend); just turn the laptop screen off/on
hl.bind("switch:on:Lid Switch", hl.dsp.dpms({ action = "off", monitor = "eDP-1" }), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.dpms({ action = "on", monitor = "eDP-1" }), { locked = true })

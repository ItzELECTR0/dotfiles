---[===Monitor=Workspace=Order===]---
hl.workspace_rule({workspace = 1, monitor = "DP-1", default = true, persistent = true})
hl.workspace_rule({workspace = 2, monitor = "DP-1", persistent = true})
hl.workspace_rule({workspace = 3, monitor = "DP-1", persistent = true})
hl.workspace_rule({workspace = 4, monitor = "HDMI-A-1", persistent = true})
hl.workspace_rule({workspace = 5, monitor = "HDMI-A-1", persistent = true})
hl.workspace_rule({workspace = 6, monitor = "HDMI-A-1", default = true, persistent = true})

---[===Layer=Rules===]---
hl.layer_rule({match = {namespace = "^noctalia-backdrop.*$"}, ignore_alpha = 0.5, blur = true, blur_popups = true})
hl.layer_rule({match = {namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$"}, no_anim = true, ignore_alpha = 0.5, blur = true, blur_popups = true})
hl.layer_rule({match = {namespace = "^noctalia-window-switcher$"}, no_anim = true, blur = false})

---[===Shape=Rules===]---
--hl.plugin.dynamic_cursors.shape_rule({shape = "grab", mode = "tilt", tilt = {limit = 2000, window = 100}})

---[===Ignore=Maximize===]---
hl.window_rule({match = {class = ".*"}, suppress_event = "maximize"})

---[===Fix=XWayland=Dragging===]---
hl.window_rule({match = {class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false}, no_focus = true, suppress_event = "activatefocus"})

---[===Effects=Ignore=Fullscreen===]---
hl.window_rule({match = {fullscreen = true}, no_blur = true, no_dim = true})

---[===Gaming=Rules===]---
hl.window_rule({match = {class = "steam_app_.*"}, immediate = true, monitor = "DP-1", workspace = 2})
hl.window_rule({match = {class = "steam_proton"}, immediate = true, monitor = "DP-1",  workspace = 2})
hl.window_rule({match = {class = "gamescope"}, immediate = true, monitor = "DP-1", workspace = 2})
hl.window_rule({match = {class = "cs2"}, immediate = true, monitor = "DP-1", workspace = 2})

---[===Opaque=Apps===]---
hl.window_rule({match = {class = "[Hh]elium"}, opaque = true})

---[===Main=Monitor=Apps===]---
hl.window_rule({match = {class = "librewolf"}, opaque = true, no_initial_focus = true, monitor = "DP-1", workspace = 1})
hl.window_rule({match = {class = "librewolf", title = ".*Private Browsing.*"}, monitor = "DP-1", workspace = 2})
hl.window_rule({match = {class = "zen|zen-twilight"}, opaque = true, no_initial_focus = true, monitor = "DP-1", workspace = 1})
hl.window_rule({match = {class = "zen|zen-twilight", title = ".*Private Browsing.*"}, monitor = "DP-1", workspace = 2})
-- Minecraft: modern (GLFW class "Minecraft* 26.2" / "Minecraft 1.21.4"), legacy LWJGL2 and launcher-wrapper classes
hl.window_rule({match = {class = "^([Mm]inecraft\\*?(\\s.*)?|com\\.mojang\\.[Mm]inecraft.*|com-moulberry-pandora-LaunchWrapper|net-minecraft-client-main-Main|net\\.minecraft\\.client\\.main\\.Main|org-(prism|multimc|poly)launcher-EntryPoint)$"}, immediate = true, monitor = "DP-1", no_initial_focus = true, fullscreen = true, workspace = "2 silent"})
-- Fallback: XWayland windows that map before WM_CLASS is set, matched on the version title instead
hl.window_rule({match = {title = "^[Mm]inecraft\\*?\\s\\d[\\w.+-]*$"}, immediate = true, monitor = "DP-1", no_initial_focus = true, workspace = "2 silent"})
hl.window_rule({match = {class = "[Pp]andora[Ll]auncher", title = "Minecraft Game Output"}, monitor = "DP-1", no_initial_focus = true, workspace = "2 silent"})
hl.window_rule({match = {class = "Unity"}, monitor = "DP-1", no_initial_focus = true, workspace = 3})
hl.window_rule({match = {class = "steam", title = "Steam Big Picture Mode"}, monitor = "DP-1", fullscreen = true, workspace = 2})
hl.window_rule({match = {initial_class = "wondershare filmora.exe", class = "wondershare filmora.exe", title = "Wondershare Filmora"}, tile = true, opacity = 1.0, no_blur = true, no_initial_focus = true, monitor = "DP-1", workspace = 2})

---[===Vertical=Monitor=Apps===]---
hl.window_rule({match = {class = "[Ss]team|[Hh]eroic|modrinth-app"}, monitor = "HDMI-A-1", workspace = "5 silent", no_initial_focus = true, suppress_event = "activatefocus"})
hl.window_rule({match = {class = "[Dd]iscord-[Cc]anary|[Dd]iscord-[Pp][Tt][Bb]|[Dd]iscord"}, monitor = "HDMI-A-1", workspace = "6 silent", no_initial_focus = true, suppress_event = "activatefocus"})
hl.window_rule({match = {class = "[Dd]iscord-[Cc]anary|[Dd]iscord-[Pp][Tt][Bb]|[Dd]iscord", fullscreen = true}, opaque = true})
hl.window_rule({match = {class = "[Ff]eishin"}, monitor = "HDMI-A-1", workspace = "6 silent", no_initial_focus = true})

---[===Floating=Windows===]---
hl.window_rule({match = {class = "librewolf", float = true}, size = "1640 980"})
hl.window_rule({match = {class = "librewolf", title = "Extension:.*"}, float = true})
hl.window_rule({match = {class = "zen|zen-twilight", float = true}, size = "1640 980"})
hl.window_rule({match = {class = "zen|zen-twilight", title = "Extension:.*"}, float = true})
hl.window_rule({match = {class = "twintaillauncher"}, float = true, size = "1460 800"})
hl.window_rule({match = {title = "Twintail Launcher"}, float = true, size = "1460 800"})
hl.window_rule({match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1080, 920 }})
hl.window_rule({match = {class = "com.system76.CosmicMonitor"}, float = true, size = "1050 1020"})
hl.window_rule({match = {class = "localsend"}, float = true, size = "1000 660"})
hl.window_rule({match = {class = "motrix-next"}, float = true, size = "960 830"})
hl.window_rule({match = {class = "[Ww]aydroid|^waydroid\\.com\\..*$"}, size = "1920 1080", float = true, center = true})
hl.window_rule({match = {class = "com.vysp3r.ProtonPlus|net.davidotek.pupgui2"}, float = true})
hl.window_rule({match = {class = "io.ente.auth"}, size = "770 1100", float = true, center = true})
hl.window_rule({match = {class = "io.frama.tractor.carburetor"}, size = "600 700", float = true})
hl.window_rule({match = {class = "kitty-floating"}, size = "975 640", float = true, center = true})
hl.window_rule({match = {class = "blueman-manager|io.github.kaii_lb.Overskride", title = "Bluetooth Devices|overskride"}, size = "850 465", float = true, center = true})
hl.window_rule({match = {class = "org.pulseaudio.pavucontrol", title = "Volume Control"}, size = "600 800", float = true, center = true})
hl.window_rule({match = {class = "Bitwarden"}, size = "900 850", float = true, center = true})
hl.window_rule({match = {class = "steam", title = "negative:[Ss]team"}, float = true})
hl.window_rule({match = {class = "org.qbittorrent.qBittorrent", title = "negative:^qBittorrent Enhanced Edition v[\\d.]+$"}, float = true})
hl.window_rule({match = {class = "org.gnome.FileRoller"}, float = true})
hl.window_rule({match = {class = "org.gnome.DiskUtility"}, float = true})
hl.window_rule({match = {class = "solaar"}, size = "1000 1000", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", workspace = 1}, size = "1370 870", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", workspace = 2}, size = "1370 870", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", workspace = 3}, size = "1370 870", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", workspace = 4}, size = "1050 870", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", workspace = 5}, size = "1050 870", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", workspace = 6}, size = "1050 870", float = true, center = true})
hl.window_rule({match = {class = "[Tt]hunar", title = "File Operation Progress"}, size = "600 110", float = true})
hl.window_rule({match = {class = "virt-manager", title = "Virtual Machine Manager"}, size = "850 900", float = true, center = true})
hl.window_rule({match = {class = "nemo"}, size = "1370 870", float = true, center = true})
hl.window_rule({match = {class = "unityhub|unityhub-bin"}, size = "1320 800", float = true, center = true})
hl.window_rule({match = {class = "mpv|vlc"}, size = "1420 840", float = true})
hl.window_rule({match = {class = "[Ll]umafly", title = "[Ll]umafly"}, float = true, center = true})
hl.window_rule({match = {class = "emote"}, float = true, center = false})
hl.window_rule({match = {class = "xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland"}, size = "1100 800", float = true})
hl.window_rule({match = {title = "Visual Studio Installer"}, float = true, center = true})
hl.window_rule({match = {title = "Picture-in-Picture"}, float = true})

---[===Border=Colors===]---
hl.window_rule({match = {title = ".*Hyprland.*", class = "negative:firefox|librewolf|zen|zen-twilight|chromium|helium"}, border_color = "rgb(FFFF00)"})
hl.window_rule({match = {class = "librewolf", title = ".*Private Browsing.*"}, border_color = "rgb(a020f0)"})
hl.window_rule({match = {class = "zen|zen-twilight", title = ".*Private Browsing.*"}, border_color = "rgb(a020f0)"})
hl.window_rule({match = {class = "[Ss]team|[Hh]eroic"}, border_color = "rgba(33ccffee)"})
hl.window_rule({match = {title = "[Ss]team"}, border_color = "rgba(33ccffee)"})
hl.window_rule({match = {class = "modrinth-app"}, border_color = "rgba(1bd96aff)"})
hl.window_rule({match = {class = "[Dd]iscord-[Cc]anary|[Dd]iscord"}, border_color = "rgba(faa61aff)"})
hl.window_rule({match = {class = "codium-insiders"}, border_color = "rgba(22a455ff)"})
hl.window_rule({match = {class = "[Uu]nity|[Uu]nity[Hh]ub"}, border_color = "rgba(ffffffbf)"})

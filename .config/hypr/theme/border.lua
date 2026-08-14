hl.config({
    general = {
        locale = "en_GB",
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border = { colors = { "rgba(ff8c21ff)", "rgba(ff9500ff)", "rgba(ff7700ff)", "rgba(ff5500ff)"}, angle = 90},
            inactive_border = "rgba(6c4d3faa)"
        },
        resize_on_border = true,
        extend_border_grab_area = 15,
        hover_icon_on_border = true,
        allow_tearing = false,
        layout = "dwindle"
    },

    decoration = {
        rounding = 10,
        rounding_power = 2,
        active_opacity = 1,
        inactive_opacity = 0.9,
        dim_around = 0.05,
        dim_inactive = 1,
        dim_special = 0.05,
        dim_strength = 0.05,
        inactive_opacity = 0.85,
        rounding_power = 5.0,

        blur = {
            enabled = true,
            new_optimizations = true,
            popups = true,
            special = true,
            size = 8,
            passes = 4,
            vibrancy = 0.1696,
            vibrancy_darkness = 0.0121
        },

        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)"
        }
    }
})
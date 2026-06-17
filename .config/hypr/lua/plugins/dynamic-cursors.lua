hl.config({
    plugin = {
        dynamic_cursors = {
            enabled = true,
            mode = "stretch",
            threshold = 2,
            tilt = {
                limit = 5000,
                activation = "negative_quadratic",
                window = 250,
                full = 75
            },
            stretch = {
                limit = 10000,
                activation = "linear",
                window = 250
            },
            shake = {
                enabled = false
            },
            hyprcursor = {
                nearest = 1,
                enabled = true,
                resolution = -1,
                fallback = "clientside"
            }
        }
    }
})
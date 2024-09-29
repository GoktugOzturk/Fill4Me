data:extend{
	--Custom hotkeys
    {
        type = "custom-input",
        name = "fill4me-keybind-reload",
        key_sequence = "CONTROL + R",
        consuming = "game-only",
    },
    {
        type = "custom-input",
        name = "fill4me-keybind-enable",
        key_sequence = "CONTROL + SHIFT + R",
        consuming = "none",
    },
    {
        type = "shortcut",
        name = "fill4me-shortcut-toggle",
        order = "z[toggles]-b[fill4me]",
        action = "lua",
        toggleable = true,
        localised_name = {"fill4me.gui.enable_button"},
        associated_control_input = "fill4me-keybind-enable",
        icons = {
            {
                icon = "__Fill4Me__/images/fill4me-32.png",
                icon_size = 32,
                scale = 1,
            },
        },
        small_icons = {
            {
                icon = "__Fill4Me__/images/fill4me-24.png",
                icon_size = 24,
                scale = 1,
            },
        },
    }
}
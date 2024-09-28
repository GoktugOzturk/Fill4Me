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
        order = "fill4me",
        action = "lua",
        toggleable = true,
        localised_name = {"fill4me.gui.enable_button"},
        icon = "__Fill4Me__/images/fill4me-64.png",
        small_icon = "__Fill4Me__/images/fill4me-64.png",
        --icons = {
        --    {
        --        icon = "__Fill4Me__/images/fill4me-32.png",
        --        size = 32,
        --        scale = 2,
        --    },
        --},
        --small_icons = {
        --    {
        --        icon = "__Fill4Me__/images/fill4me-24.png",
        --        size = 24,
        --        scale = 1,
        --    },
        --},
    }
}
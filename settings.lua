data:extend({
	--
	-- global settings
	--
	{
		type = "int-setting",
		name = "fill4me-maximum-fuel-value",
		-- name is used to determine localization
		setting_type = "runtime-global",
		default_value = 0
	},
	{
		type = "int-setting",
		name = "fill4me-maximum-ammo-value",
		-- name is used to determine localization
		setting_type = "runtime-global",
		default_value = 0
	},
	--
	-- per player settings
	--
	{
		type = "bool-setting",
		name = "fill4me-ignore-ammo-radius",
		-- name is used to determine localization
		setting_type = "runtime-per-user",
		default_value = false
	},
	{
		type = "string-setting",
		name = "fill4me-ammo-load-limit",
		setting_type = "runtime-per-user",
		default_value = "both",
		allowed_values = {"percent", "count", "both"},
		order = "ammo-load-1",
	},
	{
		type = "double-setting",
		name = "fill4me-ammo-load-percent",
		setting_type = "runtime-per-user",
		default_value = 25.0,
		minimum_value = 0.1,
		maximum_value = 100.0,
		order = "ammo-load-2",
	},
	{
		type = "int-setting",
		name = "fill4me-ammo-load-count",
		setting_type = "runtime-per-user",
		default_value = 10,
		minimum_value = 1,
		maximum_value = 200,
		order = "ammo-load-3",
	},
	--
	-- blacklist settings
	--
	{
		name = "fill4me-blacklist-fuel",
		type = "string-setting",
		allow_blank = true,
		setting_type = "runtime-per-user",
		default_value = "",
		order = "fill4me-2",
	},
	--[[
	{
		type = "string-setting",
		name = "fill4me-blacklist-ammo",
		setting_type = "runtime-per-user",
		default_value = " ",
		order = "fill4me-3",
	},
	]]--
})

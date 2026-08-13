---@class EndlessChestEffectParams
---@field char Character
---@field effect Effect

---@class EndlessChestExamineParams
---@field user Character
---@field pos TripointBubMs

---@class PortableInfiniteSpaceMod
---@field ensure_scroll fun()
---@field exit_vault fun(who: Character)
---@field on_character_effect_added fun(params: EndlessChestEffectParams)

---@type PortableInfiniteSpaceMod
local mod = game.mod_runtime[game.current_mod]

game.add_hook("on_game_started", function() return mod.ensure_scroll() end)
game.add_hook("on_game_load", function() return mod.ensure_scroll() end)
---@param params EndlessChestEffectParams
game.add_hook("on_character_effect_added", function(params) return mod.on_character_effect_added(params) end)
---@param params EndlessChestExamineParams
game.examine_functions["EXIT_ENDLESS_CHEST"] = function(params) return mod.exit_vault(params.user) end

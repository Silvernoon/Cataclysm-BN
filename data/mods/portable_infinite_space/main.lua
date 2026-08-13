---@class EndlessChestEffectParams
---@field char Character
---@field effect Effect

---@class PortableInfiniteSpaceStorage
---@field inside boolean?
---@field return_abs TripointAbsMs?
---@field vault_version integer?

---@class PortableInfiniteSpaceMod
---@field is_in_vault fun(who: Character): boolean
---@field initialize_vault fun(who: Character)
---@field ensure_exit_sigil fun(who: Character)
---@field enter_vault fun(who: Character)
---@field exit_vault fun(who: Character)
---@field ensure_scroll fun()
---@field on_character_effect_added fun(params: EndlessChestEffectParams)

---@type PortableInfiniteSpaceMod
local mod = game.mod_runtime[game.current_mod]
---@type PortableInfiniteSpaceStorage
local storage = game.mod_storage[game.current_mod]

local CAST_EFFECT_ID = EffectTypeId.new("endless_chest_cast_v2")
local LEGACY_CAST_EFFECT_ID = EffectTypeId.new("endless_chest_cast")
local SCROLL_ID = ItypeId.new("endless_chest_scroll")
local SPELL_ID = SpellTypeId.new("endless_chest_spell")
local FURN_NULL = FurnId.new("f_null"):int_id()
local FURN_ENDLESS_CHEST = FurnId.new("f_endless_chest"):int_id()
local FURN_RETURN_SIGIL = FurnId.new("f_endless_chest_return"):int_id()
local TER_FLOOR = TerId.new("t_rock_floor"):int_id()
local TER_WALL = TerId.new("t_rock"):int_id()
local VAULT_OMT = coords.tripoint_abs_omt(1000001, 1000001, -10)
local VAULT_VERSION = 1

---@param who Character
---@return boolean
mod.is_in_vault = function(who)
  local here = gapi.get_map()
  for _, point in ipairs(here:points_in_radius(who:get_pos_ms(), 8, 0)) do
    if here:get_furn_at(point) == FURN_ENDLESS_CHEST then return true end
  end
  return false
end

---@param who Character
mod.initialize_vault = function(who)
  if storage.vault_version == VAULT_VERSION then return end

  local here = gapi.get_map()
  local center = who:get_pos_ms()
  for _, point in ipairs(here:points_in_radius(center, 5, 0)) do
    local at_boundary = math.abs(point.x - center.x) == 5 or math.abs(point.y - center.y) == 5
    here:set_ter_at(point, at_boundary and TER_WALL or TER_FLOOR)
    here:set_furn_at(point, FURN_NULL)
  end

  here:set_furn_at(center + coords.tripoint_rel_ms(1, 0, 0), FURN_ENDLESS_CHEST)
  here:set_furn_at(center + coords.tripoint_rel_ms(1, 1, 0), FURN_RETURN_SIGIL)
  storage.vault_version = VAULT_VERSION
end

---@param who Character
mod.ensure_exit_sigil = function(who)
  local here = gapi.get_map()
  for _, point in ipairs(here:points_in_radius(who:get_pos_ms(), 8, 0)) do
    if here:get_furn_at(point) == FURN_ENDLESS_CHEST then
      here:set_furn_at(point + coords.tripoint_rel_ms(0, 1, 0), FURN_RETURN_SIGIL)
      return
    end
  end
end

---@param who Character
mod.enter_vault = function(who)
  storage.return_abs = who:abs_pos()
  gapi.place_player_overmap_at(VAULT_OMT)
  mod.initialize_vault(who)
  storage.inside = true
  gapi.add_msg(MsgType.good, locale.gettext("Space folds around you, revealing the endless chest."))
end

---@param who Character
mod.exit_vault = function(who)
  local return_abs = storage.return_abs
  if return_abs == nil then
    gapi.add_msg(MsgType.warning, locale.gettext("The endless chest has no saved return location."))
    return
  end

  gapi.place_player_overmap_at(return_abs:to_omt())
  gapi.place_player_local_at(gapi.get_map():abs_to_bub(return_abs))
  storage.inside = false
  storage.return_abs = nil
  gapi.add_msg(MsgType.good, locale.gettext("The endless chest returns you to the exact place you left."))
end

mod.ensure_scroll = function()
  local who = gapi.get_avatar()
  who:remove_effect(CAST_EFFECT_ID)
  who:remove_effect(LEGACY_CAST_EFFECT_ID)
  storage.inside = mod.is_in_vault(who)
  if storage.inside then mod.ensure_exit_sigil(who) end
  if who:get_magic():knows_spell(SPELL_ID) then return end
  if who:has_item_with_id(SCROLL_ID, false) then return end

  who:create_item(SCROLL_ID, 1)
  gapi.add_msg(
    MsgType.good,
    locale.gettext("A violet scroll settles into your possession, covered in impossible geometry.")
  )
end

---@param params EndlessChestEffectParams
mod.on_character_effect_added = function(params)
  if params.effect:get_id() ~= CAST_EFFECT_ID then return end
  params.effect:set_duration(TimeDuration.from_turns(0), false)
  if storage.inside or mod.is_in_vault(params.char) then
    mod.exit_vault(params.char)
  else
    mod.enter_vault(params.char)
  end
end

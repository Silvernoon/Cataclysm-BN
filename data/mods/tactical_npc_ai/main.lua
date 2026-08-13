---@class TacticalNpcAiTurnParams
---@field npc Npc

---@class TacticalNpcAiSpawnParams
---@field npc Npc

---@class TacticalNpcAiWarningParams
---@field npc Npc
---@field warning_type string
---@field speech string
---@field results table<string, any>

---@class TacticalNpcAiConfig
---@field regroup_distance integer Grant a movement bonus when farther than this distance from the player.
---@field regroup_move_bonus integer Movement points granted per turn while safely regrouping.

---@class TacticalNpcAiRuntime
---@field config TacticalNpcAiConfig
---@field on_npc_do_turn fun(params: TacticalNpcAiTurnParams)?
---@field on_npc_spawn fun(params: TacticalNpcAiSpawnParams)?
---@field on_npc_warning fun(params: TacticalNpcAiWarningParams)?
---@field maid_npc_ai fun(npc: Npc): boolean?

---@type TacticalNpcAiRuntime
local mod = game.mod_runtime[game.current_mod]

mod.config = {
  regroup_distance = 8,
  regroup_move_bonus = 25,
}

local MAID_MARKER = MutationBranchId.new("TACTICAL_NPC_AI_MAID")

local FEAR_EFFECT = EffectTypeId.new("npc_run_away")
local GRAVITY_WELL = SpellTypeId.new("gravity_well")
local GRAVITY_WELL_MIN_HOSTILES = 4

local RETREAT_LINES = {
  locale.gettext("主人，请带我离开这里！"),
  locale.gettext("我需要支援！"),
}

---@class MaidShield
---@field effects EffectTypeId[]
---@field spells SpellTypeId[]
local SHIELD_SPELLS = {
  {
    effects = { EffectTypeId.new("ward_lightning"), EffectTypeId.new("lightning_ward") },
    spells = { SpellTypeId.new("electric_ward"), SpellTypeId.new("arcana_magic_lightning_ward") },
  },
  {
    effects = { EffectTypeId.new("ward_acid"), EffectTypeId.new("acid_ward") },
    spells = { SpellTypeId.new("acid_ward"), SpellTypeId.new("arcana_blessing_ward_acid") },
  },
  {
    effects = { EffectTypeId.new("ward_cold"), EffectTypeId.new("cold_ward") },
    spells = { SpellTypeId.new("ice_ward"), SpellTypeId.new("arcana_magic_cold_ward") },
  },
  {
    effects = { EffectTypeId.new("ward_fire"), EffectTypeId.new("heat_ward") },
    spells = { SpellTypeId.new("fire_ward"), SpellTypeId.new("arcana_magic_heat_ward") },
  },
  {
    effects = { EffectTypeId.new("ward_anomaly") },
    spells = { SpellTypeId.new("anomaly_ward") },
  },
  {
    effects = { EffectTypeId.new("arcana_effect_phase_shield") },
    spells = { SpellTypeId.new("arcana_magic_phase_shield") },
  },
  {
    effects = { EffectTypeId.new("arcana_effect_shadowy_shield") },
    spells = { SpellTypeId.new("arcana_magic_serpentine_shield") },
  },
  {
    effects = { EffectTypeId.new("poison_ward") },
    spells = { SpellTypeId.new("arcana_magic_poison_armor") },
  },
  {
    effects = { EffectTypeId.new("cleric_warding") },
    spells = { SpellTypeId.new("arcana_magic_ward_against_evil") },
  },
}
local STEP_OFFSETS = {
  { x = -1, y = -1 },
  { x = 0, y = -1 },
  { x = 1, y = -1 },
  { x = -1, y = 0 },
  { x = 1, y = 0 },
  { x = -1, y = 1 },
  { x = 0, y = 1 },
  { x = 1, y = 1 },
}

-- Fear prioritizes staying within two tiles of the player; native combat resumes inside that range.

---@param first TripointBubMs
---@param second TripointBubMs
---@return integer
local function tile_distance(first, second)
  return math.max(math.abs(first.x - second.x), math.abs(first.y - second.y), math.abs(first.z - second.z))
end

---@param first TripointBubMs
---@param second TripointBubMs
---@return integer
local function path_distance(first, second)
  return math.abs(first.x - second.x) + math.abs(first.y - second.y) + math.abs(first.z - second.z)
end

---@param npc Npc
---@param target Creature?
local function regroup_with_player(npc, target)
  if target ~= nil then
    return
  end

  local player = gapi.get_avatar()
  local regroup_distance = math.max(mod.config.regroup_distance, npc:follow_distance() + 2)
  if tile_distance(npc:get_pos_ms(), player:get_pos_ms()) > regroup_distance then
    npc:mod_moves(mod.config.regroup_move_bonus)
  end
end

---@param npc Npc
---@param target TripointBubMs
---@return TripointBubMs?
local function find_step_toward(npc, target)
  local origin = npc:get_pos_ms()
  local best_step = nil
  local best_distance = path_distance(origin, target) + 1

  for _, offset in ipairs(STEP_OFFSETS) do
    local candidate = TripointBubMs.new(origin.x + offset.x, origin.y + offset.y, origin.z)
    local distance = path_distance(candidate, target)
    local occupant = gapi.get_creature_at(candidate, true)
    if distance < best_distance and occupant == nil and npc:can_move_to(candidate, true) then
      best_step = candidate
      best_distance = distance
    end
  end

  return best_step
end

---@param npc Npc
---@param shield MaidShield
---@return boolean
local function has_shield(npc, shield)
  for _, effect_id in ipairs(shield.effects) do
    if effect_id:is_valid() and npc:has_effect(effect_id) then
      return true
    end
  end
  return false
end

---@param level integer
---@return integer
local function gravity_well_aoe_radius(level)
  return math.min(3 + math.floor(level * 0.5 + 0.5), 11)
end

---@param npc Npc
---@param center TripointBubMs
---@param radius integer
---@return boolean
local function gravity_well_target_is_safe(npc, center, radius)
  local hostile_count = 0
  for _, creature in ipairs(gapi.get_all_creatures()) do
    local creature_pos = creature:get_pos_ms()
    if creature_pos.z == center.z and tile_distance(creature_pos, center) <= radius then
      local attitude = npc:attitude_to(creature)
      if attitude == Attitude.Friendly then
        return false
      end
      if attitude == Attitude.Hostile then
        hostile_count = hostile_count + 1
      end
    end
  end
  return hostile_count >= GRAVITY_WELL_MIN_HOSTILES
end

---@param npc Npc
---@param target Creature
---@return boolean
local function cast_gravity_well(npc, target)
  if not GRAVITY_WELL:is_valid() or npc:attitude_to(target) ~= Attitude.Hostile then
    return false
  end

  local magic = npc:get_magic()
  if not magic:knows_spell(GRAVITY_WELL) then
    return false
  end

  local spell = magic:get_spell(GRAVITY_WELL)
  if not magic:has_enough_energy(npc, spell) then
    return false
  end

  local target_pos = target:get_pos_ms()
  local npc_pos = npc:get_pos_ms()
  local level = spell:get_level()
  if tile_distance(npc_pos, target_pos) > math.min(9 + level, 26) then
    return false
  end

  if not gravity_well_target_is_safe(npc, target_pos, gravity_well_aoe_radius(level)) then
    return false
  end

  spell:cast(npc, target_pos)
  return true
end

---@param npc Npc
---@return boolean
local function cast_missing_shield(npc)
  local magic = npc:get_magic()
  for _, shield in ipairs(SHIELD_SPELLS) do
    if not has_shield(npc, shield) then
      for _, spell_id in ipairs(shield.spells) do
        if spell_id:is_valid() and magic:knows_spell(spell_id) then
          local spell = magic:get_spell(spell_id)
          if magic:has_enough_energy(npc, spell) then
            spell:cast(npc, npc:get_pos_ms())
            return true
          end
        end
      end
    end
  end
  return false
end

---@param npc Npc
local function set_loyal_follower_attitude(npc)
  npc:set_attitude(NpcAttitude.NPCATT_FOLLOW)
  local opinion = NpcOpinion.new()
  opinion.trust = 10
  opinion.fear = 0
  opinion.value = 10
  opinion.anger = 0
  opinion.owed = 0
  npc.op_of_u = opinion
end

---@param params TacticalNpcAiSpawnParams
mod.on_npc_spawn = function(params)
  local npc = params.npc
  if not npc:has_trait(MAID_MARKER) then
    return
  end

  npc.male = false
  npc.name = ch_names.generate(false)
  set_loyal_follower_attitude(npc)
  npc:set_first_topic("TALK_TACTICAL_NPC_AI_MAID_GREETING")
end

---@param params TacticalNpcAiWarningParams
mod.on_npc_warning = function(params)
  if params.warning_type ~= "run_away" or not params.npc:has_trait(MAID_MARKER) then
    return
  end

  params.results.speech = RETREAT_LINES[gapi.rng(1, #RETREAT_LINES)]
end

---@param npc Npc
---@return boolean
mod.maid_npc_ai = function(npc)
  if not npc:has_trait(MAID_MARKER) then
    return false
  end
  local target = npc:current_target()
  if target ~= nil and not target:is_dead() then
    if cast_gravity_well(npc, target) or cast_missing_shield(npc) then
      return true
    end
  end

  if not npc:has_effect(FEAR_EFFECT) then
    return false
  end

  npc:remove_effect(FEAR_EFFECT)
  local player_pos = gapi.get_avatar():get_pos_ms()
  if tile_distance(npc:get_pos_ms(), player_pos) <= 2 then
    return false
  end

  local step = find_step_toward(npc, player_pos)
  if step ~= nil then
    npc:move_to(step, true)
  end
  return true
end

---@param params TacticalNpcAiTurnParams
mod.on_npc_do_turn = function(params)
  local npc = params.npc
  if not npc:is_player_ally() or not npc:is_walking_with() or npc:is_dead() then
    return
  end

  local target = npc:current_target()
  if target ~= nil and target:is_dead() then
    target = nil
  end

  regroup_with_player(npc, target)
end

gdebug.log_info("Tactical NPC AI: ready")

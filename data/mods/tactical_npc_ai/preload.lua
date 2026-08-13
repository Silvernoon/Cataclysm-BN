---@class TacticalNpcAiTurnParams
---@field npc Npc

---@class TacticalNpcAiSpawnParams
---@field npc Npc

---@class TacticalNpcAiWarningParams
---@field npc Npc
---@field warning_type string
---@field speech string
---@field results table<string, any>

---@class TacticalNpcAiRuntime
---@field on_npc_do_turn fun(params: TacticalNpcAiTurnParams)?
---@field on_npc_spawn fun(params: TacticalNpcAiSpawnParams)?
---@field on_npc_warning fun(params: TacticalNpcAiWarningParams)?
---@field maid_npc_ai fun(npc: Npc): boolean?

---@type TacticalNpcAiRuntime
local mod = game.mod_runtime[game.current_mod]

---@param params TacticalNpcAiTurnParams
local function forward_npc_turn(params)
  if mod.on_npc_do_turn then
    return mod.on_npc_do_turn(params)
  end
end

---@param params TacticalNpcAiSpawnParams
local function forward_npc_spawn(params)
  if mod.on_npc_spawn then
    return mod.on_npc_spawn(params)
  end
end

---@param params TacticalNpcAiWarningParams
local function forward_npc_warning(params)
  if mod.on_npc_warning then
    return mod.on_npc_warning(params)
  end
end

---@param npc Npc
---@return boolean
local function forward_maid_npc_ai(npc)
  if mod.maid_npc_ai then
    return mod.maid_npc_ai(npc) or false
  end
  return false
end

game.npc_ai_functions["tactical_npc_ai_maid"] = forward_maid_npc_ai

game.add_hook("on_npc_do_turn", forward_npc_turn)
game.add_hook("on_npc_spawn", forward_npc_spawn)
game.add_hook("on_npc_warning", forward_npc_warning)

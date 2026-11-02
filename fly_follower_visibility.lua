-- RBY 3D NPC: hide only Ranch follower actors during the complete HM Fly
-- cinematic. Ranch's follower service owns their spawning, updates and draws;
-- we wrap each exposed follower's `shouldRender` predicate, leaving all other
-- Ranch overworld actors, trainer sprites and gameplay entirely untouched.
-- No rebuild of RanchImporterGen1 or its WAD-derived pack is required.
local M={version=1}
local suppress=false
local wrapped=setmetatable({}, {__mode='k'})
local lastApi=nil

local function followerService(mod)
  if not(mod and type(mod.find)=='function') then return nil end
  -- The real Ranch Gen1 export (not a DX alias).
  for _,id in ipairs({'POKEMON_RANCH_GEN1','COBBLEMON_MAIN'}) do
    local ok,handle=pcall(mod.find,id)
    if ok and type(handle)=='table' and type(handle.exports)=='table' then
      local service=handle.exports.cobblemon_follower
      if type(service)=='table' and type(service.getFollower)=='function' then
        return service
      end
    end
  end
  return nil
end

local function restore()
  for actor,previous in pairs(wrapped) do
    if type(actor)=='table' and rawget(actor,'shouldRender')==previous.wrapper then
      -- Usually the original method lives on Actor.__index, not the instance.
      rawset(actor,'shouldRender',previous.own)
    end
    wrapped[actor]=nil
  end
end

function M.sync(mod,active)
  suppress=active==true
  if not suppress then restore();return end
  local service=followerService(mod)
  if not service then return end
  lastApi=service
  for slot=1,6 do
    local ok,actor=pcall(service.getFollower,slot)
    if ok and type(actor)=='table' and not wrapped[actor] then
      local own=rawget(actor,'shouldRender')
      local original=actor.shouldRender
      -- Follow Ranch's own predicate when the flight ends. While flying,
      -- skipping drawActor also prevents ground shadow and toon outlines.
      local wrapper=function(self,...)
        if suppress then return false end
        if type(original)=='function' then return original(self,...) end
        return true
      end
      wrapped[actor]={own=own,wrapper=wrapper}
      rawset(actor,'shouldRender',wrapper)
    end
  end
end
function M.active() return suppress end
function M.restore() suppress=false;restore() end
return M

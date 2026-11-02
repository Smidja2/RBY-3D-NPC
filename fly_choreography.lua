-- Shared RBY 3D NPC Fly animation. This is the ONE visual source of truth
-- for Terrarium / Dramaless / Dramatic / Potato / Battle Art.
-- Ported from the user-approved Terrarium v6 animation. No renderer hooks here.
-- World Fly destination/warp stays with Gen1Recomp.
local Fly={version=7}
local pi=math.pi
local function clamp(v) return math.max(0,math.min(1,v)) end
local function ease(v) v=clamp(v); return v*v*(3-2*v) end

function Fly.landingTimes(cfg)
  cfg=cfg or {}
  return math.max(0.1,cfg.cinematic_landing_duration or 0.90),
         math.max(0.1,cfg.terrarium_dismount_duration or 0.46),
         math.max(0.1,cfg.terrarium_flyaway_duration or 0.45)
end
function Fly.landingDuration(cfg)
  local a,b,c=Fly.landingTimes(cfg)
  return a+b+c
end
-- Return common (world x,y,z offset, yaw, visible, rider independent x,y,z,
-- stage, jump progress, pitch, roll). All offsets are in world coordinates.
function Fly.transform(mode, elapsed, cfg, flyMount)
  cfg=cfg or {};flyMount=flyMount or {}
  local t=math.max(0,elapsed or 0)
  if mode=="departure" then
    -- Exactly the Terrarium v6 takeoff arc and cadence.
    local takeoff=cfg.takeoff or 0.50
    local departing=math.max(cfg.departure_duration or 0.55,0.001)
    local depDist=cfg.departure_distance or 64
    local depHeight=cfg.departure_height or 28
    local offscreen=math.max(cfg.offscreen or 0,0)
    local returning=math.max(cfg.return_duration or 0.55,0.001)
    local retDist=cfg.return_distance or depDist
    local retHeight=cfg.return_height or 45
    if t<takeoff then return 0,0,0,pi/2,true,nil,nil,nil,"mounted",0,0,0 end
    t=t-takeoff
    if t<departing then
      local p=clamp(t/departing)
      return depDist*p,depHeight*p,0,pi/2,true,nil,nil,nil,"mounted",0,0,0
    end
    t=t-departing
    if t<offscreen then
      return depDist,depHeight,0,pi/2,true,nil,nil,nil,"mounted",0,0,0
    end
    t=t-offscreen
    if t<returning then
      local p=clamp(t/returning)
      return retDist-(retDist*2*p),
             depHeight+(retHeight-depHeight)*p,
             0,-pi/2,true,nil,nil,nil,"mounted",0,0,0
    end
    return 0,0,0,0,false
  end
  if mode=="landing" then
    -- New forward approach, jump OFF, bird flies away (never reverse takeoff).
    local approach,dismount,flyaway=Fly.landingTimes(cfg)
    local entryDistance=math.max(18,cfg.entry_distance or 57)
    local entryHeight=cfg.entry_height or 30
    local parkX=-(cfg.terrarium_parking_distance or 9)
    local hoverY=cfg.pickup_height or 5
    if t<approach then
      local p=ease(t/approach)
      return -entryDistance+(entryDistance+parkX)*p,
        entryHeight+(hoverY-entryHeight)*p,0,pi/2,true,
        nil,nil,nil,"landing",0,0,0
    end
    t=t-approach
    if t<dismount then
      local p=clamp(t/dismount)
      local floating=flyMount.flying_offset or {}
      local rider=flyMount.rider_offset or {}
      local startX=parkX+(floating.x or 0)+(rider.z or 0)
      local startY=hoverY+(floating.y or 0)+(rider.y or 0)
      return parkX,hoverY,0,pi/2,true,
        startX*(1-ease(p)),
        startY*(1-ease(p))+(cfg.red_jump_lift or 6)*0.45*math.sin(pi*p),
        0,"land_jump",p,0,0
    end
    t=t-dismount
    if t<flyaway then
      local p=ease(t/flyaway)
      return parkX+(cfg.climb_distance or 70)*p,
        hoverY+(cfg.climb_height or 40)*p,
        0,pi/2,true,0,0,0,"idle",1,0,0
    end
  end
  return 0,0,0,0,false
end

function Fly.nativeFlyActive(state)
  if type(state)~="table" then return false end
  local candidates={}
  local ok,Game=pcall(require,"src.core.Game")
  if ok and type(Game)=="table" and type(Game.overworld)=="table" then
    candidates[#candidates+1]=Game.overworld
  end
  candidates[#candidates+1]=state
  if type(state.overworld)=="table" then candidates[#candidates+1]=state.overworld end
  for _,world in ipairs(candidates) do
    local anim=world.flyAnim
    if type(anim)=="table" and anim.active~=false and anim.enabled~=false then
      local phase=anim.phase or anim.status or anim.stage
      if phase~="idle" and phase~="done" and phase~="none"
        and phase~="finished" and phase~="cancelled"
        and phase~="complete" then return true,anim,world end
    end
  end
  return false,nil,nil
end

function Fly.step(state,now,cfg,mount)
  if not state or state.mode=="normal" then return nil end
  local start=state.mode=="landing" and state.landingAt or state.startedAt
  local elapsed=math.max(0,now-(start or now))
  local x,y,z,yaw,visible,rx,ry,rz,phase,jump,pitch,bank =
    Fly.transform(state.mode,elapsed,cfg,mount)
  if not visible then return nil end
  local pose=(math.floor(elapsed/0.05)%2)==0 and "idle" or "walk"
  return {x=x,y=y,z=z,yaw=yaw,rx=rx,ry=ry,rz=rz,
          phase=phase,jump=jump,pitch=pitch,bank=bank,pose=pose}
end

-- Renderers provide Mat4 only. This produces identical world-space mount/rider
-- transforms and uses the destination player's real facing after dismount.
function Fly.models(Mat4, state, definition, step)
  local landing=state.mode=="landing"
  local px=(landing and state.targetPx or state.startPx) or 0
  local py=(landing and state.targetPy or state.startPy) or 0
  local ground=(landing and state.targetGround or state.startGround) or 0
  local floating=definition.flying_offset or {}
  local rider=definition.rider_offset or {}
  local mount=Mat4.mul(Mat4.translate(px+8+step.x+(floating.x or 0),
       ground+step.y+(floating.y or 0),py+8+step.z+(floating.z or 0)),
       Mat4.rotateY(step.yaw or 0))
  local riderMat
  if step.rx ~= nil then
    local facingYaw=step.yaw or 0
    if step.phase=="idle" then
      local face=state.targetFacing
      facingYaw=(face=="right" and pi/2)
        or (face=="left" and -pi/2)
        or (face=="up" and pi)
        or (face=="down" and 0) or facingYaw
    end
    riderMat=Mat4.mul(Mat4.translate(px+8+step.rx,
          ground+(step.ry or 0),py+8+(step.rz or 0)),
          Mat4.rotateY(facingYaw))
  else
    riderMat=Mat4.mul(mount,Mat4.translate(
      rider.x or 0,rider.y or 0,rider.z or 0))
  end
  return mount,riderMat,{x=px+8+step.x+(floating.x or 0),
      y=ground+step.y+(floating.y or 0),
      z=py+8+step.z+(floating.z or 0),
      yaw=step.yaw or 0,pitch=step.pitch or 0,
      roll=step.bank or 0,phase=step.phase}
end
return Fly

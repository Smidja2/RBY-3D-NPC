-- RBY 3D NPC / Terrarium 1.32.0-beta.
-- Character-only bridge: intercept the EXPORTED scene, billboard and Voxel3D
-- surfaces (just as the Potato adapter does). Lua debug upvalue mutation was
-- unreliable in the shipped first pass and is no longer used.
-- No world pipeline, tile mesh, movement or Terrarium source is replaced.
local Adapter = {}
Adapter.info = {
  adapterVersion = "0.7.0",
  targetMod = { id="TERRARIUM", name="Terrarium", validatedVersion="1.32.0-beta" }
}

local function modules(mod)
  local target=mod.find("TERRARIUM")
  if not (target and target.exports and target.exports.lib) then return nil end
  local V=target.exports.lib
  if type(V.require)~="function" then return nil end
  local function get(name)
    local ok,x=pcall(V.require,name)
    return ok and type(x)=="table" and x or nil
  end
  local scene=get("VoxelScene")
  local voxel=get("Voxel3D")
  local cards=get("SpriteBillboards")
  local m4=get("Mat4")
  local chunks=get("ChunkMesher")
  local shadows=get("ShadowMap")
  if not (chunks and type(chunks.figures)=="function"
      and shadows and type(shadows.draw)=="function") then return nil end
  if not (scene and type(scene.render)=="function"
      and voxel and type(voxel.draw)=="function" and type(voxel.newMesh)=="function"
      and cards and type(cards.mesh)=="function" and m4
      and type(m4.translate)=="function" and type(m4.rotateY)=="function") then
    return nil
  end
  return scene,voxel,cards,m4,chunks,shadows
end

function Adapter.detect(mod)
  return modules(mod)~=nil
end

function Adapter.initialize(mod, loadLocalModule, Registry, Runtime)
  local Scene, Voxel3D, Cards, Mat4, ChunkMesher, ShadowMap = modules(mod)
  if not Scene then
    mod.log:warn("Terrarium 3D NPC: exported character surfaces unavailable")
    return false
  end
  if Scene.__rby3dNpcTerrariumBridge then return true end
  if not (Runtime and type(Runtime.loadAsset)=="function"
      and type(Runtime.getSpritePose)=="function"
      and type(Runtime.textureDataFor)=="function"
      and Registry and type(Registry.lookup)=="function") then return false end

  local originalRender=Scene.render
  local originalCardMesh=Cards.mesh
  local originalVoxelDraw=Voxel3D.draw
  local originalShadowDraw=ShadowMap.draw
  local originalBeginGhost=Voxel3D.beginGhost
  local originalEndGhost=Voxel3D.endGhost
  local originalBeginOverlay=Voxel3D.beginOverlay
  local originalEndOverlay=Voxel3D.endOverlay
  local originalEndScene=Voxel3D.endScene
  local ToonOutline=loadLocalModule("toon_outline.lua")
  local FlySpriteGuard=loadLocalModule("fly_sprite_guard.lua")
  local activeFlyWorldState=nil
  local flyState={
    mode="normal", startedAt=0, landingAt=0, startMap=nil,
    startPx=0, startPy=0, startGround=0,
    targetPx=0, targetPy=0, targetGround=0,
    playerSprite=nil, colors=nil, lastArrival=nil,
    presented=false, arrivalMap=nil, session=0, lastActiveFlyAnim=nil
  }
  local cardsByMesh=setmetatable({}, {__mode="k"})
  local gpuCache=setmetatable({}, {__mode="k"})
  local prevPosition=setmetatable({}, {__mode="k"})
  local context=nil
  local reportedSuccess=false
  local reportedFailure=false
  local reportedSeated=false
  local lastError=nil

  local function option(key,fallback)
    if mod.options and type(mod.options.get)=="function" then
      local ok,v=pcall(mod.options.get,mod.options,key)
      if ok and v~=nil then return v end
    end
    return fallback
  end

  -- Fly detection is shared with the other renderers. Do not treat a
  -- retained birdSprite or flyArrive from a normal warp as a fresh HM action.

  -- Field effects in some engine versions call love.graphics.draw directly
  -- instead of SpriteRenderer.draw. Only the actual Fly bird Image is eligible
  -- for filtering; ordinary map/NPC/pokemon draws are never compared here.
  local function isNativeBirdImage(drawable)
    if not drawable or flyState.mode=="normal" or not flyState.presented then return false end
    local gameOK,Game=pcall(require,"src.core.Game")
    local world=(gameOK and type(Game)=="table" and Game.overworld) or activeFlyWorldState
    if type(world)~="table" then return false end
    local function match(value)
      if value==drawable then return true end
      if type(value)=="table" then
        if value.image==drawable or value.img==drawable then return true end
        if type(value.def)=="table" and value.def.image==drawable then return true end
      end
      return false
    end
    for _,name in ipairs({"birdSprite","flyBirdSprite","birdImg","flyBirdImg","flyBirdImage","birdImage"}) do
      if match(world[name]) then return true end
    end
    if type(world.flyAnim)=="table" then
      for _,name in ipairs({"birdSprite","flyBirdSprite","birdImg","flyBirdImg","flyBirdImage","birdImage"}) do
        if match(world.flyAnim[name]) then return true end
      end
    end
    return false
  end

  local function clearFlight()
    flyState.mode="normal"
    flyState.presented=false
    flyState.arrivalMap=nil
    flyState.startMap=nil
  end

  -- The ordinary sprite pass may run *after* the voxel canvas has ended, or
  -- while a destination transition temporarily has no voxel canvas. Suppress
  -- the actual native bird actor, not arbitrary billboard sprites, as soon as
  -- we have successfully submitted the 3D Red + Pidgeot composite once.
  local srOK,SpriteRenderer=pcall(require,"src.render.SpriteRenderer")
  local gameOK,Game=pcall(require,"src.core.Game")
  if srOK and gameOK and type(SpriteRenderer)=="table" and
      type(SpriteRenderer.draw)=="function" and type(Game)=="table" then
    local previousSpriteDraw=SpriteRenderer.draw
    SpriteRenderer.draw=function(self,...)
      local world=Game.overworld
      if flyState.mode~="normal" and flyState.presented and type(world)=="table"
        and world.birdSprite~=nil and self==world.birdSprite then
        return
      end
      return previousSpriteDraw(self,...)
    end
  end

  local function flyNowSeconds()
    if love.timer and love.timer.getTime then
      local ok,t=pcall(love.timer.getTime)
      if ok and type(t)=="number" then return t end
    end
    return 0
  end

  local function flyAnimationConfig()
    return Registry.fly_animation or {}
  end

  local FLY_POSE_STEP=0.05

  if type(originalBeginOverlay)=="function" and type(originalEndOverlay)=="function" then
    local savedFxDraw,fxDrawWrapper,flyFxActive=nil,nil,false
    local function restoreFlyOverlay()
      if savedFxDraw and love and love.graphics and love.graphics.draw==fxDrawWrapper then
        love.graphics.draw=savedFxDraw
      end
      savedFxDraw,fxDrawWrapper=nil,nil
      if flyFxActive and FlySpriteGuard and FlySpriteGuard.endFx then
        FlySpriteGuard.endFx()
      end
      flyFxActive=false
    end
    Voxel3D.beginOverlay=function(...)
      restoreFlyOverlay()
      local result=originalBeginOverlay(...)
      if result and flyState.mode~="normal" and flyState.presented then
        flyFxActive=true
        if FlySpriteGuard and FlySpriteGuard.beginFx then FlySpriteGuard.beginFx(activeFlyWorldState) end
        if love and love.graphics and type(love.graphics.draw)=="function" then
          savedFxDraw=love.graphics.draw
          local original=savedFxDraw
          fxDrawWrapper=function(drawable,...)
            if isNativeBirdImage(drawable) or
                (FlySpriteGuard and FlySpriteGuard.hideImage(drawable)) then return end
            return original(drawable,...)
          end
          love.graphics.draw=fxDrawWrapper
        end
      end
      return result
    end
    Voxel3D.endOverlay=function(...)
      local ok,a,b,c=pcall(originalEndOverlay,...)
      restoreFlyOverlay()
      if not ok then error(a,0) end
      return a,b,c
    end
  end

  local function gpuFor(pkg)
    local gpu=gpuCache[pkg]
    if gpu then return gpu end
    local mesh=Voxel3D.newMesh(pkg.vertices,pkg.indices)
    local mirrored=Voxel3D.newMesh(pkg.mirroredVertices,pkg.mirroredIndices)
    if not (mesh and mirrored) then return nil end
    gpu={mesh=mesh,mirroredMesh=mirrored,textures={}}
    gpuCache[pkg]=gpu
    if ToonOutline and type(ToonOutline.prepare)=="function" then
      pcall(ToonOutline.prepare,pkg,gpu,Voxel3D)
    end
    return gpu
  end

  local function prepared(replacement,p)
    local definition=replacement and replacement.asset
    if not definition then return nil end
    local pkg=Runtime.loadAsset(definition)
    if not pkg then return nil end
    local gpu=gpuFor(pkg)
    if not gpu then return nil end
    if type(Runtime.animateAsset)=="function" then
      pcall(Runtime.animateAsset,definition,pkg,gpu)
    end
    local pixels,key=Runtime.textureDataFor(pkg,p.sprite,p.colors)
    if not pixels then return nil end
    key=key or "raw"
    local texture=gpu.textures[key]
    if not texture then
      texture=love.graphics.newImage(pixels)
      if texture and texture.setFilter then
        local filter=pkg.rumbleTexture and "nearest" or "linear"
        texture:setFilter(filter,filter)
      end
      gpu.textures[key]=texture
    end
    if not texture then return nil end
    return gpu,texture
  end

  local function isWater(map,e)
    if map and type(map.isWaterCell)=="function" and e
        and type(e.cellX)=="number" and type(e.cellY)=="number" then
      local ok,water=pcall(map.isWaterCell,map,e.cellX,e.cellY)
      if ok then return water==true end
    end
    return false
  end

  local function replacementFor(p)
    if not (p and p.sprite and p.sprite.def) then return nil end
    local id,frame,mirror=Runtime.getSpritePose(p.sprite,p.facing,p.phase,p.flip)
    if id==nil then return nil end
    local e=p.entityRef
    local replacement=Registry.lookup(id,frame,mirror,p.facing,{
      isPlayer=p.isPlayer, entityRef=e,entityKey=e,
      objectId=e and (e.id or e.objectId or (e.def and e.def.name)),
      mapId=p.map and (p.map.id or p.map.name or p.map.key),
      cellX=e and e.cellX,cellY=e and e.cellY,
      isMoving=p.isMoving,isLedgeJump=e and
        ((e.hopStep and e.hopStep~=0) or e.ledgeJump or e.jumping) or false,
      jumpProgress=e and (e.progress or e.stepProgress),
      jumpFrames=e and (e.stepFramesCur or e.stepFrames),
      onWaterCell=p.onWaterCell,
      surfing=e and e.surfing or false,
      cycling=e and (e.cycling or e.onBike) or false,
      fishing=e and (e.fishing or e.isFishing) or false,
      spriteDef=p.sprite.def,spriteImage=p.sprite.def.image,
    })
    return replacement
  end

  local function matrix(p,replacement)
    local facing=replacement.facing or p.facing
    local yaw=(facing=="right" and math.pi/2)
          or (facing=="left" and -math.pi/2)
          or (facing=="up" and math.pi) or 0
    local factor=tonumber(option(p.isPlayer and "player_model_scale" or "npc_model_scale","1")) or 1
    factor=math.max(0.2,math.min(3,factor))
    local y=(p.gh or 0)+(p.lift or 0)
    -- Swimmers are already served by pre-submerged GLBs selected by Registry.
    local model=Mat4.mul(Mat4.translate(p.px+8,y,p.py+8),Mat4.rotateY(yaw))
    if factor~=1 then model=Mat4.mul(model,Mat4.scale(factor,factor,factor)) end
    return model
  end

  -- Arrival is a NEW forward-moving action, not the takeoff played in
  -- reverse. Keep the same +X / +90-degree heading used by departure:
  -- the bird enters from the west, approaches, Red jumps forward onto the
  -- destination tile, and the bird flies ahead once Red is on the ground.
  -- All positions are visual offsets only; Gen1Recomp owns the actual warp.
  -- Every renderer calls the same user-approved v6 choreography.
  local FlyChoreography=loadLocalModule("fly_choreography.lua")
        local FlyMounts=loadLocalModule("fly_mount_provider.lua")
        if FlyMounts and type(FlyMounts.installSelectionHook)=="function" then
            FlyMounts.installSelectionHook(mod)
        end
        local FlyFollowers=loadLocalModule("fly_follower_visibility.lua")
  local function flyStep()
    return FlyChoreography.step(flyState,flyNowSeconds(),
      flyAnimationConfig(),Registry.fly_mount)
  end

  local function flyReplacementData()
    local step=flyStep()
    if not step then return nil end
    local definition=Registry.lookupFly and Registry.lookupFly(
      step.pose,step.phase,(step.jump or 0)*1.875) or nil
    if not (definition and definition.parts) then return nil end
    local mountModel,riderModel,actorCoords=FlyChoreography.models(
      Mat4,flyState,definition,step)
    local draws={}
    for _,part in ipairs(definition.parts) do
      local gpu,texture=prepared({asset=part.asset},
        {sprite=flyState.playerSprite,colors=flyState.colors})
      if not (gpu and texture) then return nil end
      draws[#draws+1]={
        mesh=(part.mirror and gpu.mirroredMesh or gpu.mesh),
        texture=texture,model=part.role=="rider" and riderModel or mountModel,role=part.role
      }
    end
    draws.mountWorld=actorCoords or actor
            return draws
  end

  local function drawFlyVisible()
    if Registry.standaloneFlyOwnsFly then return false end
    local draws=flyReplacementData()
    if type(draws)~="table" or #draws==0 then return false end
    local gfx=love and love.graphics
    local oldCull="none"
    if gfx and type(gfx.getMeshCullMode)=="function" then
      local ok,mode=pcall(gfx.getMeshCullMode)
      if ok and type(mode)=="string" then oldCull=mode end
    end
    local ok,err=pcall(function()
      if gfx and type(gfx.setMeshCullMode)=="function" then gfx.setMeshCullMode("none") end
      for _,draw in ipairs(draws) do
        local external = draw.role=="mount" and FlyMounts and
          FlyMounts.draw(originalVoxelDraw,draws.mountWorld,flyNowSeconds())
        if not external then
          if ToonOutline and type(ToonOutline.draw)=="function" then
            ToonOutline.draw(originalVoxelDraw,draw.mesh,draw.texture,draw.model,0,draw.model)
          else
            originalVoxelDraw(draw.mesh,draw.texture,draw.model,0,draw.model)
          end
        end
      end
    end)
    if gfx and type(gfx.setMeshCullMode)=="function" then pcall(gfx.setMeshCullMode,oldCull) end
    if not ok then lastError="Fly visible pass: "..tostring(err); return false end
    flyState.presented=true
    return true
  end

  local function drawFlyShadow()
    local draws=flyReplacementData()
    if type(draws)~="table" or #draws==0 then return false end
    local ok,err=pcall(function()
      for _,draw in ipairs(draws) do
        local usedExternal = draw.role=="mount" and FlyMounts and
                        FlyMounts.shadow(originalShadowDraw)
                    if not usedExternal then originalShadowDraw(draw.mesh,draw.texture,draw.model) end
      end
    end)
    if not ok then lastError="Fly shadow pass: "..tostring(err); return false end
    return true
  end

  local function paint(p)
    local ok,r=pcall(replacementFor,p)
    if not ok then lastError="Registry.lookup: "..tostring(r);return false end
    if not r then return false end
    local base=matrix(p,r)
    local submissions={}
    if r.type=="composite" and r.parts then
      local floating=r.floating_offset or {}
      local rider=r.rider_offset or {}
      local mount=Mat4.mul(base,Mat4.translate(floating.x or 0,floating.y or 0,floating.z or 0))
      local riderModel=Mat4.mul(base,Mat4.translate(
        (floating.x or 0)+(rider.x or 0),
        (floating.y or 0)+(rider.y or 0),
        (floating.z or 0)+(rider.z or 0)))
      for _,part in ipairs(r.parts) do
        local loaded,gpu,texture=pcall(prepared,{asset=part.asset},p)
        if not loaded or not (gpu and texture) then
          lastError=loaded and "missing composite part" or tostring(gpu)
          return false
        end
        submissions[#submissions+1]={
          mesh=part.mirror and gpu.mirroredMesh or gpu.mesh,
          texture=texture,mat=part.role=="rider" and riderModel or mount
        }
      end
    elseif r.asset then
      local loaded,gpu,texture=pcall(prepared,r,p)
      if not loaded then lastError="asset loading: "..tostring(gpu);return false end
      if not (gpu and texture) then lastError="model or texture missing";return false end
      submissions[1]={mesh=r.mirror and gpu.mirroredMesh or gpu.mesh,
                      texture=texture,mat=base}
    else
      return false
    end
    if #submissions==0 then return false end
    local success,err=pcall(function()
      for _,part in ipairs(submissions) do
        if ToonOutline and type(ToonOutline.draw)=="function" then
          ToonOutline.draw(originalVoxelDraw,part.mesh,part.texture,part.mat,0,part.mat)
        else
          originalVoxelDraw(part.mesh,part.texture,part.mat,0,part.mat)
        end
      end
    end)
    if not success then lastError="GLB draw: "..tostring(err);return false end
    return true
  end

  -- Terrarium's sofa occupant is NOT a character/entity. Structures cuts it
  -- out of the furniture tiles and ChunkMesher.figures supplies its own
  -- camera-facing mesh. The normal SpriteBillboards hooks never see it.
  -- Reuse the existing Registry.lookupPokecenterSeatedFigure(Sit) instead.
  local function figureData(info)
    if not (info and info.figure and info.replacement
        and info.replacement.asset) then return nil end
    local p={sprite=nil,colors=info.colors}
    local gpu,texture=prepared(info.replacement,p)
    if not (gpu and texture) then return nil end
    local f=info.figure
    -- An authored figure's wx is the left edge of its pixel-art silhouette,
    -- while a GLB's origin is central. Match the already proven Dramatic /
    -- Dramaless figure adapter's +8px half-width seat anchor.
    local x=(f.wx or 0)+8+(info.ox or 0)
    -- The room's 3D couch seat is at height 8 (Terrarium RoomKit.couch /
    -- voxel_heights.lua: pc_couch standH=8), but ChunkMesher.figures may
    -- report y=0 for the old 2D cutout's floor-level feet.  The Sit GLB
    -- must rest on the furniture, never on that old cutout's floor plane.
    -- Keep any greater authored lift, and apply this BEFORE model scaling
    -- so NPC size settings do not change the seat elevation.
    local y=math.max(f.y or 0,8)
    local z=(f.wz or 0)+(info.oy or 0)
    local model=Mat4.mul(Mat4.translate(x,y,z),
                         Mat4.rotateY(info.replacement.yaw or 0))
    local factor=tonumber(option("npc_model_scale","1")) or 1
    factor=math.max(0.2,math.min(3,factor))
    if factor~=1 then
      model=Mat4.mul(model,Mat4.scale(factor,factor,factor))
    end
    return gpu,texture,model
  end

  -- The same GLB replaces the flat figure in both the light's shadow map
  -- and the visible camera pass. A failure leaves Terrarium's original
  -- figure intact rather than making someone on the sofa disappear.
  ShadowMap.draw=function(mesh,texture,model,...)
    local ctx=context
    if ctx and ctx.flyActive and not ctx.flyShadowDrawn then
      ctx.flyShadowDrawn=drawFlyShadow() == true
    end
    local info=ctx and ctx.specialFigures[mesh]
    if info then
      local ok,gpu,tex,mat=pcall(figureData,info)
      if ok and gpu and tex and mat then
        return originalShadowDraw(gpu.mesh,tex,mat,...)
      end
    end
    return originalShadowDraw(mesh,texture,model,...)
  end

  local function paintFigure(info)
    local ready,gpu,texture,model=pcall(figureData,info)
    if not ready then
      lastError="seated figure asset: "..tostring(gpu)
      return false
    end
    if not (gpu and texture and model) then
      lastError="seated figure model or texture missing"
      return false
    end
    local ok,err=pcall(function()
      if ToonOutline and type(ToonOutline.draw)=="function" then
        ToonOutline.draw(originalVoxelDraw,gpu.mesh,texture,model,0,model)
      else
        originalVoxelDraw(gpu.mesh,texture,model,0,model)
      end
    end)
    if not ok then
      lastError="seated figure GLB draw: "..tostring(err)
      return false
    end
    return true
  end

  -- Associate cached character billboard meshes with their sprite sheets.
  -- Terrarium calls Cards.mesh(def, frame, waterline) for actual characters;
  -- its shadow pass instead uses Cards.shadowQuad.
  Cards.mesh=function(def,frame,...)
    local mesh=originalCardMesh(def,frame,...)
    if mesh then cardsByMesh[mesh]={def=def,frame=frame} end
    return mesh
  end

  -- The scene draws the poses in the same order as the engine calls pose():
  -- neighbour ghosts first, then current-map entities. The observed pose
  -- callback is invoked by TERRARIUM, never an extra call by this mod.
  local function wrapPose(e,map,dx,dz,isPlayer,restorers,seen)
    if type(e)~="table" or type(e.pose)~="function" or seen[e] then return end
    seen[e]=true
    local original=e.pose
    local own=rawget(e,"pose")
    local function capture(self,...)
      local sprite,vx,vy,facing,phase,flip=original(self,...)
      local ctx=context
      if ctx and sprite and sprite.def then
        local px=(vx or self.px or 0)+(dx or 0)
        local py=(self.py or vy or 0)+(dz or 0)
        local ground=0
        if type(Scene.groundAt)=="function" and self.cellX~=nil and self.cellY~=nil then
          local ok,v=pcall(Scene.groundAt,map,self.cellX,self.cellY)
          if ok and v then ground=v end
        end
        local old=prevPosition[self]
        local moving=old and (math.abs(px-old[1])+math.abs(py-old[2])>0.001) or false
        prevPosition[self]={px,py}
        local p={sprite=sprite,px=px,py=py,gh=ground,
          facing=facing,phase=phase,flip=flip,
          lift=(self.py or vy or 0)-(vy or self.py or 0),
          colors=ctx.colors(map),isPlayer=isPlayer,entityRef=self,map=map,
          isMoving=moving or (self.moving==true),onWaterCell=isWater(map,self)}
        ctx.poses[#ctx.poses+1]=p
        if isPlayer then ctx.player=p end
      end
      return sprite,vx,vy,facing,phase,flip
    end
    local ok=pcall(function() e.pose=capture end)
    if ok then
      restorers[#restorers+1]=function() e.pose=own end
    end
  end

  -- Voxel3D.draw is dynamically looked up by Terrarium's local drawEntity.
  -- This is the actual sprite-suppression point: only when a GLB draw
  -- succeeds do we skip the original billboard submission.
  Voxel3D.draw=function(mesh,texture,model,pull,sunModel,...)
    local ctx=context
    if ctx and ctx.inGhost and ctx.player and not sunModel then
      -- The occlusion silhouette belongs to the player's sprite. When a
      -- GLB is available, suppress the 2D silhouette, not the world depth.
      local tag=ctx.shadowMeshTag
      if tag and tag==mesh then
        local ok,r=pcall(replacementFor,ctx.player)
        if ok and r then
          if r.asset then
            local ready,gpu,tex=pcall(prepared,r,ctx.player)
            if ready and gpu and tex then return end
          elseif r.type=="composite" and type(r.parts)=="table" then
            local allReady=#r.parts>0
            for _,part in ipairs(r.parts) do
              local ready,gpu,tex=pcall(prepared,{asset=part.asset},ctx.player)
              if not (ready and gpu and tex) then allReady=false;break end
            end
            if allReady then return end
          end
        end
      end
    end
    -- Authored indoor figure: bypass the billboard/entity draw index.
    -- Terrarium renders this after normal NPCs, from another mesh source.
    if ctx and sunModel and ctx.specialFigures[mesh] then
      if paintFigure(ctx.specialFigures[mesh]) then
        ctx.seatedReplaced=ctx.seatedReplaced+1
        return
      end
    end
    local info=ctx and sunModel and cardsByMesh[mesh]
    if info then
      local nextIndex=(ctx.drawIndex or 0)+1
      ctx.drawIndex=nextIndex
      -- If a sprite was skipped (e.g. a missing billboard), resynchronize
      -- by def without pairing one model with an unrelated NPC.
      local p=ctx.poses[nextIndex]
      if not (p and p.sprite and p.sprite.def==info.def) then
        for i=nextIndex+1,#ctx.poses do
          local candidate=ctx.poses[i]
          if candidate and candidate.sprite and candidate.sprite.def==info.def then
            p=candidate;ctx.drawIndex=i;break
          end
        end
      end
      if p and p.sprite and p.sprite.def==info.def then
        if p.isPlayer and ctx.flyActive then
          if not ctx.flyVisibleDrawn then
            ctx.flyVisibleDrawn=drawFlyVisible() == true
            if ctx.flyVisibleDrawn and FlySpriteGuard then FlySpriteGuard.mark(activeFlyWorldState) end
          end
          if ctx.flyVisibleDrawn then return end
        end
        ctx.seen=ctx.seen+1
        local max=tonumber(option("npc_draw_distance","12"))
        local visible=true
        if max and max>0 and ctx.player and not p.isPlayer then
          local dx=p.px-ctx.player.px
          local dz=p.py-ctx.player.py
          visible=(dx*dx+dz*dz <= (max*16)^2)
        end
        if visible and paint(p) then
          ctx.replaced=ctx.replaced+1
          return
        end
      else
        ctx.unmatched=ctx.unmatched+1
      end
    end
    return originalVoxelDraw(mesh,texture,model,pull,sunModel,...)
  end

  if type(originalEndScene)=="function" then
    Voxel3D.endScene=function(...)
      local ctx=context
      if ctx and ctx.flyActive and not ctx.flyVisibleDrawn then
        ctx.flyVisibleDrawn=drawFlyVisible() == true
        if ctx.flyVisibleDrawn and FlySpriteGuard then FlySpriteGuard.mark(activeFlyWorldState) end
      end
      return originalEndScene(...)
    end
  end

  -- mark the player's original silhouette quad for suppression while
  -- preserving unrelated drop-shadows and 3D scene geometry.
  local originalShadowQuad=Cards.shadowQuad
  if type(originalShadowQuad)=="function" then
    Cards.shadowQuad=function(def,frame,...)
      local mesh=originalShadowQuad(def,frame,...)
      if context and context.inGhost and mesh then context.shadowMeshTag=mesh end
      return mesh
    end
  end
  if type(originalBeginGhost)=="function" and type(originalEndGhost)=="function" then
    Voxel3D.beginGhost=function(...)
      if context then context.inGhost=true;context.shadowMeshTag=nil end
      return originalBeginGhost(...)
    end
    Voxel3D.endGhost=function(...)
      local r=originalEndGhost(...)
      if context then context.inGhost=false;context.shadowMeshTag=nil end
      return r
    end
  end

  Scene.render=function(state,w,h,vw,vh,paletteFor,...)
    local now=flyNowSeconds()
    local player=state and state.player or nil
    activeFlyWorldState=state
    if FlySpriteGuard and type(FlySpriteGuard.begin)=="function" then
      FlySpriteGuard.begin(state)
    end
    -- Broad FlySpriteGuard.isNativeFly() is intentionally NOT used as the
    -- trigger: its cached birdSprite shortcut mislabels ordinary map warps.
    local flyNativeActive,activeAnim,flyEngineWorld =
      FlyChoreography.nativeFlyActive(state)
    local nativeFlyArrival=(type(flyEngineWorld)=="table" and
      type(flyEngineWorld.flyArrive)=="table") and flyEngineWorld.flyArrive or nil
    -- A flyArrive seen without this adapter observing a departure is NEVER a
    -- Fly activation. The game may reuse arrival FX after warpTo(...).
    local newNativeFlyArrival=nativeFlyArrival~=nil
      and nativeFlyArrival~=flyState.lastArrival
    -- Always retire old arrival records so stale ones cannot re-arm Fly.
    if flyState.mode=="normal" and nativeFlyArrival then
      flyState.lastArrival=nativeFlyArrival
    end
    local playerPx=player and player.px or 0
    local playerPy=player and player.py or 0
    local playerGround=0
    if player and state and state.map and type(Scene.groundAt)=="function" and player.cellX~=nil and player.cellY~=nil then
      local okGround,v=pcall(Scene.groundAt,state.map,player.cellX,player.cellY)
      if okGround and v then playerGround=v end
    end
    local function paletteColors(map)
      if type(paletteFor)=="function" then
        local ok,value=pcall(paletteFor,map)
        if ok then return value end
      end
      return nil
    end
    -- Cancelled or stale native transitions must not strand the player in a
    -- Fly cinematic. Never infer a new flight from a map or position change.
    if flyState.mode=="departure" and not flyNativeActive
        and state and state.map==flyState.startMap
        and (now-(flyState.startedAt or now))>7.0 then
      clearFlight()
    end
    -- Latch the animation identity: a still-active native table after
    -- our landing must not re-trigger Fly over and over.
    if not flyNativeActive then flyState.lastActiveFlyAnim=nil end
    if flyState.mode=="normal" and flyNativeActive and player
       and activeAnim~=flyState.lastActiveFlyAnim then
      flyState.lastActiveFlyAnim=activeAnim
      flyState.mode="departure"
      if FlyMounts then FlyMounts.begin(mod,state,activeAnim) end
      flyState.session=flyState.session+1
      flyState.presented=false
      flyState.startedAt=now
      flyState.startMap=state.map
      flyState.startPx=playerPx
      flyState.startPy=playerPy
      flyState.startGround=playerGround
      flyState.playerSprite=player.sprite
      flyState.colors=paletteColors(state.map)
      if mod.log then mod.log:info("NPC Terrarium Fly: native Fly action started; 3D cinematic armed") end
    end
    -- Landing is allowed ONLY for the same explicitly armed Fly session.
    -- A normal door/stair/cave warp has no such session and cannot trigger it.
    if flyState.mode=="departure" and player then
      local mapChanged=state.map~=flyState.startMap
      local dx=playerPx-flyState.startPx
      local dz=playerPy-flyState.startPy
      local movedFar=(dx*dx+dz*dz)>(16*16)
      if newNativeFlyArrival or mapChanged or (not flyNativeActive and movedFar) then
        flyState.mode="landing"
        flyState.arrivalMap=state.map
        if nativeFlyArrival then flyState.lastArrival=nativeFlyArrival end
        flyState.landingAt=now
        flyState.targetPx=playerPx
        flyState.targetPy=playerPy
        flyState.targetGround=playerGround
        flyState.targetFacing=player.facing
        flyState.playerSprite=player.sprite or flyState.playerSprite
        flyState.colors=paletteColors(state.map) or flyState.colors
      end
    end
    if flyState.mode=="landing" then
      local cfg=flyAnimationConfig()
      local completeTime=FlyChoreography.landingDuration(cfg)
      if state and flyState.arrivalMap and state.map~=flyState.arrivalMap then
        clearFlight() -- another ordinary warp immediately after landing
      elseif (now-flyState.landingAt)>=completeTime then
        clearFlight()
      end
    end
    if FlyFollowers then FlyFollowers.sync(mod,flyState.mode~="normal") end
    local previous=context
    local ctx={poses={},player=nil,drawIndex=0,seen=0,replaced=0,
      unmatched=0,inGhost=false,shadowMeshTag=nil,
      specialFigures={},seatedReplaced=0,state=state,
      flyActive=(flyState.mode~="normal"),flyVisibleDrawn=false,flyShadowDrawn=false}
    function ctx.colors(map)
      if type(paletteFor)=="function" then
        local ok,value=pcall(paletteFor,map)
        if ok then return value end
      end
      return nil
    end
    context=ctx
    local function captureSeatedFigure(map,ox,oy)
      if not (map and type(map.id)=="string"
          and type(Registry.lookupPokecenterSeatedFigure)=="function") then return end
      local id=map.id:lower():gsub("[^%w]","")
      if not (id:find("pokecenter",1,true)
          or id=="indigoplateaulobby" or id=="celadonhotel") then return end
      -- The 1-person rule prevents removing other authored figures in
      -- a custom map which happens to reuse Pokémon Center tiles.
      local list=ChunkMesher.figures(map)
      if not (list and #list==1 and list[1].mesh) then return end
      local ok,special=pcall(Registry.lookupPokecenterSeatedFigure,map.id)
      if not (ok and special and special.asset) then return end
      local colors=ctx.colors(map)
      local f=list[1]
      ctx.specialFigures[f.mesh]={
        figure=f,replacement=special,colors=colors,
        ox=ox or 0,oy=oy or 0
      }
    end
    -- Figures are separate from state.entities and MUST be tagged before
    -- VoxelScene's shadow pass, not while handling a character pose().
    if state then
      captureSeatedFigure(state.map,0,0)
      for _,nb in ipairs(state.neighbors or {}) do
        captureSeatedFigure(nb.map,nb.ox,nb.oy)
      end
    end
    local restorers={}
    local seen=setmetatable({},{__mode="k"})
    if state then
      for _,g in ipairs(state.ghosts or {}) do
        wrapPose(g.npc,g.map or state.map,g.ox or 0,g.oy or 0,false,restorers,seen)
      end
      for _,e in ipairs(state.entities or {}) do
        wrapPose(e,state.map,0,0,e==state.player,restorers,seen)
      end
    end
    local ok,a,b,c=pcall(originalRender,state,w,h,vw,vh,paletteFor,...)
    for i=#restorers,1,-1 do pcall(restorers[i]) end
    context=previous
    if not ok then error(a,0) end
    -- An absent terrain mesh gives a nil canvas (Terrarium intentionally
    -- falls back to the engine's 2D renderer during first-frame loading).
    if a~=nil and ctx.seatedReplaced>0 and not reportedSeated then
      reportedSeated=true
      mod.log:info("Terrarium RBY NPC: Pokemon Center seated figure replaced with animated GLB")
    end
    if a~=nil and ctx.seen>0 then
      if ctx.replaced>0 and not reportedSuccess then
        reportedSuccess=true
        mod.log:info("Terrarium RBY NPC GLB active: %d/%d characters replaced (first visible frame)",ctx.replaced,ctx.seen)
      elseif ctx.replaced==0 and not reportedFailure then
        reportedFailure=true
        mod.log:warn("Terrarium RBY NPC: %d character billboards seen, zero GLB replacements. Last issue: %s",ctx.seen,tostring(lastError or "unmapped sprite/identity"))
      end
    end
    return a,b,c
  end

  Scene.__rby3dNpcTerrariumBridge=true
  mod.log:info("Terrarium RBY NPC v0.7 bridge installed: characters + seated figures + strict HM Fly gating + native bird actor suppression")
  return true
end

return Adapter

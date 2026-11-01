-- Porygonal Fly is a sprite-to-GLB visual replacement, not a renderer mod.
-- Native HM Fly is rendered through the engine's field-FX pipeline.
-- Only suppress its sprite after a complete Pidgeot+Red GLB submission.
local ok, SR=pcall(require,"src.render.SpriteRenderer")
local guard={version=308, state=nil, drawn=false, fxDepth=0, suppressed=0}
local prior=ok and type(SR)=="table" and SR._npcPidgeotBirdGuard or nil
if prior and prior.version==308 then return prior end
if prior then prior.drawn=false;prior.state=nil;prior.fxDepth=0 end
-- Check real transient HM Fly actions across known Gen1Recomp state layouts.
-- Do not use the Fly HM inventory, or ordinary sprite IDs, as detection.
local function transientFly(value)
    if value == nil or value == false then return false end
    if type(value) == "table" then
        if value.active == false or value.enabled == false then return false end
        local phase = value.phase or value.status or value.stage
        if phase == "done" or phase == "idle" or phase == "none"
            or phase == "finished" or phase == "cancelled" then return false end
        -- Some engine builds don't store a phase in the animation table.
        return true
    end
    return value == true or type(value) == "number" and value > 0
end
local function exactFlyAction(value)
    if type(value)=="string" then
        local normalized=value:lower():gsub("[%s_%-]", "")
        return normalized == "fly" or normalized == "hmfly" or normalized == "usefly"
    end
    if type(value)=="table" then
        local action=value.action or value.kind or value.name or value.type or value.id
        return exactFlyAction(action) and value.active ~= false and value.phase ~= "done"
    end
    return false
end
local function roots(state)
    if type(state)~="table" then return {} end
    local result={state}
    local function append(v)
        if type(v)=="table" then
            for _,known in ipairs(result) do if known==v then return end end
            result[#result+1]=v
        end
    end
    append(state.overworld)
    if type(state.game)=="table" then append(state.game.overworld) end
    if type(state.world)=="table" then append(state.world.overworld);append(state.world) end
    return result
end
function guard.isNativeFly(state)
    for _,world in ipairs(roots(state)) do
        for _,key in ipairs({"flyAnim","flyFade","flyArrive","hmFlyAnim",
            "flyTransition","flySequence","flyEffect","fieldFly",
            "flyDeparture","flyLanding","flyCutscene","flyPending"}) do
            if transientFly(world[key]) then return true end
        end
        -- The engine constructs a dedicated birdSprite for the HM Fly
        -- field effect, separate from decorative map NPCs. This survives
        -- engine versions that omit the flyAnim phase from the scene context.
        local bird=world.birdSprite or world.flyBirdSprite
        if bird~=nil and bird~=false and type(bird)=="table"
            and bird.active~=false and bird.visible~=false
            and (world.player~=nil or world.map~=nil) then return true end
        -- Some engine builds nest transient HM effects in state.fx.
        for _,group in ipairs({"fx","fieldFx","effects","fieldEffects"}) do
            local effects=world[group]
            if type(effects)=="table" and transientFly(effects.fly) then return true end
        end
        if exactFlyAction(world.fieldMove) or exactFlyAction(world.hmMove)
            or exactFlyAction(world.currentAction) then return true end
        if exactFlyAction(world.action) and world.actionActive ~= false then return true end
    end
    return false
end
local function flyWorld(state)
    for _,world in ipairs(roots(state)) do
        if guard.isNativeFly(world) then return world end
    end
    return nil
end
local function flying()
    return guard.isNativeFly(guard.state)
end
function guard.begin(world)
    guard.state=world;guard.drawn=false;guard.fxDepth=0
end
function guard.mark(world)
    if world and world==guard.state then guard.drawn=true end
end
function guard.status()
    return {fly=guard.isNativeFly(guard.state),drawn=guard.drawn,
        suppressed=guard.suppressed,fieldFxDepth=guard.fxDepth}
end
function guard.beginFx(world)
    guard.fxDepth=guard.fxDepth+1
end
function guard.endFx()
    guard.fxDepth=math.max(0,guard.fxDepth-1)
end
local function candidateImage(drawable)
    local world=flyWorld(guard.state)
    if not world or not drawable then return false end
    local fly=world.flyAnim
    local fields={"birdImg","flyBirdImg","flyBirdImage","birdImage","flyBirdSprite","birdSprite"}
    local function found(obj)
        if obj==drawable then return true end
        if type(obj)=="table" and (obj.image==drawable or obj.img==drawable or (obj.def and obj.def.image==drawable)) then return true end
        return false
    end
    for _,name in ipairs(fields) do
        if found(world[name]) then return true end
        if type(fly)=="table" and found(fly[name]) then return true end
    end
    return false
end
function guard.hideImage(drawable)
    if not (guard.drawn and flying()) then return false end
    -- Only the native Fly image may be hidden.  The engine's fxBird()
    -- owns overworld.birdSprite and draws that exact SpriteRenderer.
    if candidateImage(drawable) then
        guard.suppressed=guard.suppressed+1
        return true
    end
    return false
end
-- This covers the native sprite renderer if Fly uses a SpriteRenderer actor.
-- Restrict the fallback to the field-FX draw scope, never all overworld NPCs.
if ok and type(SR)=="table" and type(SR.draw)=="function" then
    local underlying=SR.draw
    SR.draw=function(self,...)
        if guard.drawn and flying() then
            local world=flyWorld(guard.state)
            local fly=world and world.flyAnim
            local bird=world and (world.birdSprite or world.flyBirdSprite)
            if bird and (self==bird or (type(bird)=="table" and self.image==bird)) then
                guard.suppressed=guard.suppressed+1
                return
            end
            if type(fly)=="table" and (self==fly.birdSprite or self==fly.flyBirdSprite) then
                guard.suppressed=guard.suppressed+1
                return
            end
        end
        return underlying(self,...)
    end
    SR._npcPidgeotBirdGuard=guard
end
return guard

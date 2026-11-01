-- v50: stand-alone, player-only run input and movement.  No voxel renderer is replaced.
-- v49 only hooked movement.speed; first/third-person FreeMove skips that hook.
-- Support normal grid steps AND the optional renderer's own continuous movement.
local Run = {}
local shiftDown = { lshift=false, rshift=false }
local tracked, gameRef = nil, nil
local freeMoving, freePlayer = false, nil
local freeTable, freeWrap = nil, nil
local attachedName = nil
local Game
local okGame, foundGame = pcall(require, "src.core.Game")
if okGame then Game=foundGame end

local function physicalShift()
    local kb = love and love.keyboard
    if not (kb and type(kb.isDown)=="function") then return nil end
    local a,l=pcall(kb.isDown,"lshift")
    local b,r=pcall(kb.isDown,"rshift")
    if not a and not b then return nil end
    return (a and l==true) or (b and r==true)
end

local function shiftHeld()
    -- Key events are the authoritative backup when love.keyboard isn't visible.
    -- Polling also handles Shift already held when the mod was hot-reloaded.
    local down=physicalShift()
    return shiftDown.lshift or shiftDown.rshift or down==true
end

local function busy(g)
    g = g or gameRef or Game
    local ow = g and g.overworld
    if not ow then return false end
    if ow.transitioning or ow.engaging or ow.teleportOut then return true end
    if ow.runner and type(ow.runner.isRunning)=="function" then
        local ok,is=pcall(ow.runner.isRunning,ow.runner)
        if ok and is then return true end
    end
    return type(ow.scriptMoves)=="table" and #ow.scriptMoves>0
end

local function restore()
    local old=tracked
    tracked=nil
    if old and old.player and old.player.stepFramesCur == old.runFrames then
        -- Do not overwrite a newer value owned by a bike or another mod.
        old.player.stepFramesCur=tonumber(old.player.stepFrames) or old.normalFrames or 16
    end
end

function Run.isFreeMoving()
    return freeMoving and freePlayer~=nil
end

function Run.isRunning(ctx)
    if type(ctx)~="table" or not ctx.isPlayer or not shiftHeld() or busy()
        or ctx.surfing or ctx.cycling or ctx.fishing or ctx.isLedgeJump then
        return false
    end
    local moving = ctx.isMoving or freeMoving
    if not moving then return false end
    local player= (tracked and tracked.player) or freePlayer
    if ctx.isMoving and tracked and tracked.running and player==tracked.player then
        return true
    end
    return freeMoving and freePlayer~=nil
end

-- DRAMALESS_SHAPE / DRAMATIC_SHAPE / BATTLE_ART_VOXEL_FORK first and third
-- person modes use FreeMove.tick instead of Player.tryMove.  The renderer's
-- FreeMove.WALK and .BIKE constants are temporarily scaled for its own tick.
-- No pipeline/camera/GLB renderer, world data or player position is patched.
local MODS={"DRAMALESS_SHAPE","DRAMATIC_SHAPE","BATTLE_ART_VOXEL_FORK"}
local function attachFreeMove(mod)
    if type(mod.find)~="function" then return false end
    for _,name in ipairs(MODS) do
        local ok, handle=pcall(mod.find,name)
        local lib=ok and handle and handle.exports and handle.exports.lib
        if type(lib)=="table" and type(lib.require)=="function" then
            local okay,fm=pcall(lib.require,"FreeMove")
            if okay and type(fm)=="table" and type(fm.tick)=="function"
                and type(fm.WALK)=="number" and type(fm.BIKE)=="number" then
                if freeTable==fm and fm.tick==freeWrap then return true end
                -- Allow hot reload without wrappers multiplying one another.
                if fm.npcShiftV50Wrap and fm.tick==fm.npcShiftV50Wrap
                    and type(fm.npcShiftV50Inner)=="function" then
                    fm.tick=fm.npcShiftV50Inner
                end
                local inner=fm.tick
                local wrap=function(state,...)
                    local player=state and state.player
                    local pX,pY=player and player.px,player and player.py
                    local game=gameRef or Game
                    local save=game and game.save
                    local onBike=save and save.onBike
                    local oldWalk,oldBike=fm.WALK,fm.BIKE
                    local canRun=player~=nil and shiftHeld() and not busy(game)
                        and not onBike and not player.surfing and not player.fishing
                    if canRun then
                        fm.WALK=math.max(oldWalk,math.min(oldWalk*2,4))
                        -- Keep the bike untouched: free roam only uses WALK on foot.
                    end
                    -- Restore constants even if this third-party tick raises.
                    local success,a,b,c,d=pcall(inner,state,...)
                    fm.WALK,fm.BIKE=oldWalk,oldBike
                    freePlayer=player
                    freeMoving=(success and canRun and player~=nil
                        and (player.px~=pX or player.py~=pY)) or false
                    if not success then error(a,0) end
                    return a,b,c,d
                end
                fm.tick=wrap
                fm.npcShiftV50Wrap, fm.npcShiftV50Inner=wrap,inner
                freeTable,freeWrap=fm,wrap
                attachedName=name
                if mod.log and mod.log.info then
                    mod.log:info("Shift RUN integrated with %s FreeMove (1ST/3RD)",name)
                end
                return true
            end
        end
    end
    return false
end

function Run.install(mod)
    if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then
        return false,"mod hook API unavailable"
    end
    mod.hooks:wrap("input.key",function(next,game,ev)
        gameRef=game or gameRef
        if type(ev)=="table" and (ev.key=="lshift" or ev.key=="rshift") then
            if ev.phase=="pressed" then shiftDown[ev.key]=true
            elseif ev.phase=="released" then shiftDown[ev.key]=false end
        end
        return next(game,ev)  -- do not consume normal game input
    end)
    mod.hooks:wrap("movement.speed",function(next,frames,ctx)
        local normal=tonumber(next(frames,ctx)) or tonumber(frames) or 16
        if type(ctx)~="table" or not ctx.player or ctx.onBike or ctx.surfing
            or ctx.player.fishing or not shiftHeld() or busy() then
            if tracked and ctx and ctx.player and tracked.player~=ctx.player then restore() end
            return normal
        end
        local faster=math.max(1,math.min(normal,math.floor(normal/2+0.5)))
        tracked={player=ctx.player,normalFrames=normal,runFrames=faster,running=true}
        return faster
    end)
    mod.hooks:wrap("input.step",function(next,game,dt)
        gameRef=game or gameRef
        -- A cutscene must NEVER inherit 8-frame scripted player steps.
        if tracked and (not tracked.player or not tracked.player.moving
            or busy(game)) then restore() end
        -- Dramaless exports can appear after the NPC mod's initialization.
        if not (freeTable and freeTable.tick==freeWrap) then
            attachFreeMove(mod)
        end
        return next(game,dt)
    end)
    if mod.events and type(mod.events.on)=="function" then
        mod.events:on("mods.loaded",function() attachFreeMove(mod) end)
        mod.events:on("game.ready",function() attachFreeMove(mod) end)
        mod.events:on("script.started",function() restore();freeMoving=false end)
        mod.events:on("map.exited",function() restore();freeMoving=false end)
    end
    -- Immediate attach when renderer already loaded.
    attachFreeMove(mod)
    return true
end
return Run

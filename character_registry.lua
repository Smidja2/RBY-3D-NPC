local Tuning,
      Version,
      Decisions,
      AnimationCatalog,
      SeatedNPCs = ...


local Registry = {}

if type(Version) ~= "table"
    or type(Version.group) ~= "function" then

    error(
        "character_registry.lua expected Version module"
    )
end
----------------------------------------------------------------
-- Persistent user tuning
--
-- Tuning is injected by main.lua after loading character_tuning.lua
-- through the mod-local loader. Registry therefore stays independent
-- from filesystem/package.path details.
----------------------------------------------------------------

if type(Tuning) ~= "table" then
    error(
        "character_registry.lua expected attributes_tuning table"
    )
end


----------------------------------------------------------------
-- Active game/version profile
--
-- Red + Blue share the current base assets. Yellow adds only its
-- own assets/overrides, using the suffix `_Y`.
--
-- Keep symbolic sprite IDs as Registry keys: numeric sprite values
-- differ between Red/Blue and Yellow after SPRITE_SEEL.
----------------------------------------------------------------

local VERSION_GROUP =
    Version.group()


local IS_RED_BLUE =
    VERSION_GROUP
        == Version.RED_BLUE


local IS_YELLOW =
    VERSION_GROUP
        == Version.YELLOW


assert(
    IS_RED_BLUE
        or IS_YELLOW,
    "Unsupported Registry version group: "
        .. tostring(VERSION_GROUP)
)


Registry.version = {
    group =
        VERSION_GROUP,

    asset_group =
        IS_YELLOW
        and "Y"
        or "RB"
}
----------------------------------------------------------------
-- Global Porygonal asset convention
----------------------------------------------------------------

local ASSET_ROOT =
    "assets/"

local CHARACTER_PALETTE =
    ASSET_ROOT
    .. "grayscale_palette.png"


----------------------------------------------------------------
-- Active player character
--
-- Surf temporarily replaces the player's VISUAL sprite with SEEL.
-- Recomp does not expose the original RED/YELLOW sprite ID through
-- that visual pose, so Surf must resolve the rider from a stable
-- Porygonal-side player configuration instead.
--
-- Change "red" later if/when another playable character is selected.
----------------------------------------------------------------

Registry.player = {
    base = "red"
}

Registry.getStyle = function() return "n64", "low" end
Registry.Decisions = Decisions or { byObject={}, byMapCell={}, bySprite={} }

-- Lock each NPC to its first resolved map-object assignment for as long as
-- that entity exists on the map. Never reclassify a walking NPC based on
-- whatever tile it currently happens to occupy. Weak keys also ensure old
-- map instances are released when the game unloads a map.
Registry._npcIdentityLocks = setmetatable({}, {__mode="k"})


local function slugify(value)
    local v=tostring(value or ""):lower():gsub("[^%w]+","")
    return v
end

-- Calm idle v0.4.8: Idle_03 is stretching, NEVER the default Idle.
-- Normal authored Idle/Breathing clips play as-is at original speed.
-- NPC stretching is a rare separate action, ~120-240 continuous idle seconds.
-- NPC optional gestures are occasional rather than cycling nonstop.
-- Red: after 20 seconds without gameplay input, play one miscellaneous
-- non-Walk/non-Run action; respect the same rare stretching rule.
-- No GLB keyframes, timing, morph weights, or skeleton data are edited.
local RED_ACTION_WAIT = 20.0
local RED_IDLE_VARIANT_INTERVAL = 12.0
local NPC_IDLE_VARIANT_INTERVAL = 18.0
local WALK_BRIDGE_SECONDS = 0.16

local function keyHash(s)
    local h=17
    for i=1,#s do h=(h*33+s:byte(i))%2147483629 end
    return h
end

local function animationTime()
    if love and love.timer and love.timer.getTime then
        local ok,v=pcall(love.timer.getTime)
        if ok and type(v)=="number" then return v end
    end
    return os.clock()
end

Registry.AnimationCatalog=AnimationCatalog or {}
Registry.SeatedSitClips={
    ["beauty"]=true,
    ["blue_sis"]=true,
    ["boy"]=true,
    ["fisherman"]=true,
    ["gambler"]=true,
    ["gentleman"]=true,
    ["lass"]=true,
    ["middle_age_woman_new"]=true,
    ["old_guy2"]=true,
    ["old_woman"]=true,
    ["red_mom"]=true,
    ["scientist_m"]=true,
    ["youngster"]=true,
 }
Registry._lookupContext=nil
local idleState={}

local function clipDuration(clip)
    return math.max(0.01,tonumber(clip and clip.duration) or 1)
end
local function stretching(name)
    local v=tostring(name or ""):lower()
    return v=="idle_03" or v:sub(1,8)=="idle_03_" or v:sub(1,8)=="idle_03."
end
local function normalIdle(name)
    local v=tostring(name or ""):lower()
    if stretching(v) then return false end
    return v:match("^idle")~=nil
        or v:find("breath",1,true)~=nil
        or v:match("^stand")~=nil
end
local poolCache={}
local function splitIdle(base,entry)
    local prev=poolCache[base]
    if prev then return prev.normal,prev.extra,prev.stretch end
    local normal,extra,stretch={},{},{}
    for _,clip in ipairs(entry.idle or {}) do
        if stretching(clip.name) then
            stretch[#stretch+1]=clip
        elseif normalIdle(clip.name) then
            normal[#normal+1]=clip
        else
            extra[#extra+1]=clip
        end
    end
    -- v21: A dedicated user-authored Breathing clip is the NPC's default
    -- standing loop when present. Other Idle poses remain available as rare
    -- extra actions; no GLB keyframes or existing clips are edited.
    -- Keep Red's input-dependent idle/action system entirely unchanged.
    if base ~= "red" then
        local authored={}
        for _,clip in ipairs(normal) do
            if tostring(clip.name or ""):lower()=="breathing" then
                authored[#authored+1]=clip
            end
        end
        if #authored>0 then
            for _,clip in ipairs(normal) do
                if tostring(clip.name or ""):lower()~="breathing" then
                    extra[#extra+1]=clip
                end
            end
            normal=authored
        end
    end
    poolCache[base]={normal=normal,extra=extra,stretch=stretch}
    return normal,extra,stretch
end
local function nextRandom(st,n,slot)
    if n<=1 then st[slot]=1;return 1 end
    st.seed=(st.seed*1103515245+12345)%2147483629
    local v=math.floor(st.seed/2147483629*n)+1
    if v==st[slot] then v=v%n+1 end
    st[slot]=v
    return v
end
local function randomWait(st,low,high)
    st.seed=(st.seed*1103515245+12345)%2147483629
    return low+(high-low)*(st.seed/2147483629)
end
local function entityFor(base,ctx)
    if type(ctx)=="table" then
        if ctx.isPlayer then return "player:"..base end
        if ctx.seatedId then return base..":seat:"..ctx.seatedId end
        return base..":"..tostring(ctx.objectId or ctx.entityKey or ctx.entityRef
            or ((ctx.mapId or "")..":"..tostring(ctx.cellX or "")..":"..tostring(ctx.cellY or "")))
    end
    return base
end
-- Independent visual Walk clip clock. Retiming does NOT modify NPC paths,
-- game step intervals, collision, or player speed. Preserve phase when a
-- user changes the option mid-walk; preserve the existing short walk bridge.
local function motionClipTime(state,now,reset,speed)
    if reset or state.motionSampleAt==nil then
        state.motionElapsed=0
        state.motionSampleAt=now
        state.motionPlaybackSpeed=speed
        return 0
    end
    local delta=math.max(0,now-state.motionSampleAt)
    state.motionElapsed=(state.motionElapsed or 0)
        +delta*(state.motionPlaybackSpeed or speed)
    state.motionSampleAt=now
    state.motionPlaybackSpeed=speed
    return state.motionElapsed
end

local function walkPlaybackRate()
    local speed=1
    if type(Registry.walkAnimationSpeed)=="function" then
        local ok,v=pcall(Registry.walkAnimationSpeed)
        if ok and type(v)=="number" and v>=1.00 and v<=3.00 then
            speed=v
        end
    end
    return speed
end

local function animationSelection(base,pose)
    local entry=Registry.AnimationCatalog[base]
    if not entry then return nil end
    local now=animationTime()
    local ctx=Registry._lookupContext
    local playerRed=(base=="red" and type(ctx)=="table" and ctx.isPlayer==true)
    local special=(base=="red_surf" or base=="red_cycling" or base=="red_fishing"
        or base=="biker_cycling" or base:match("^biker_cycling_v29_") or base=="ghost")
    local cycling=(base=="red_cycling" or base=="biker_cycling" or base:match("^biker_cycling_v29_"))
    if special and not cycling then pose="idle" end
    local entity=entityFor(base,ctx)
    local state=idleState[entity]
    if not state then
        state={seed=keyHash(entity),mode=nil,start=now,motionStart=now,
            lastMotionAt=-math.huge,motionClip=nil,lastInputAt=now,
            idleIndex=1,idleLast=1,actionLast=0,variantAt=now}
        state.nextStretchAt=now+randomWait(state,120,240)
        state.nextGestureAt=now+randomWait(state,70,125)
        idleState[entity]=state
    end

    local buttonDown=false
    if playerRed and type(Registry.isGameplayButtonDown)=="function" then
        local ok,pressed=pcall(Registry.isGameplayButtonDown)
        buttonDown=(ok and pressed==true)
        if buttonDown then
            state.lastInputAt=now
            if state.mode=="action" then
                state.mode="idle";state.start=now
                state.idleIndex=1;state.variantAt=now;state.action=nil
            end
        end
    end

    -- v44: Chair occupants play their actual per-model GLB Sit track.
    -- This branch runs before the V6 Walk/Run and random idle logic, so
    -- fixed-chair actors cannot stand, turn randomly or walk in place.
    -- The decorative Pokemon Center seat remains an independent case.
    if pose=="spe1" or pose=="sit" then
        local hasSit=(base=="middle_age_woman_new" or base=="little_girl_new")
        if not hasSit and type(Registry.SeatedSitClips)=="table" then
            hasSit=Registry.SeatedSitClips[base]==true
        end
        if hasSit then
            if state.mode~="sit" then state.mode="sit";state.start=now end
            return "Sit",math.max(0,now-state.start),entity
        end
        return nil -- no bogus Sit clip call on models without one
    end
    local locomotion=(pose=="walk" or pose=="run")
    if locomotion and (not special or cycling) then
        if playerRed then state.lastInputAt=now end
        local pool=entry[pose]
        if not pool or #pool==0 then
            pool=(pose=="run" and entry.walk) or entry.run or entry.walk
        end
        if pool and #pool>0 then
            local clip=pool[1]
            local sameMotion=(state.mode==pose and state.motionClip==clip.name)
            local withinGap=(now-state.lastMotionAt)<WALK_BRIDGE_SECONDS
            local continuing=sameMotion or (withinGap and state.motionClip==clip.name)
            if not continuing then state.motionStart=now end
            -- Run clips keep their original playback rate. This toggle only
            -- retimes the Walk clip, not the actor's actual movement speed.
            local speed=(pose=="walk") and walkPlaybackRate() or 1.0
            local clipTime=motionClipTime(state,now,not continuing,speed)
            state.mode=pose;state.motionClip=clip.name;state.lastMotionAt=now
            return clip.name,clipTime,entity
        end
    end
    if not special and state.motionClip
      and (state.mode=="walk" or state.mode=="run")
      and now-state.lastMotionAt<WALK_BRIDGE_SECONDS then
        if playerRed then state.lastInputAt=now end
        local speed=(state.mode=="walk") and walkPlaybackRate() or 1.0
        return state.motionClip,motionClipTime(state,now,false,speed),entity
    end

    local pool=entry.idle
    if not pool or #pool==0 then return nil end
    if special and not cycling then
        if state.mode~="special" then state.mode="special";state.start=now end
        return pool[1].name,math.max(0,now-state.start),entity
    end

    local normal,extra,stretch=splitIdle(base,entry)
    local idlePool=(#normal>0 and normal) or extra
    if #idlePool==0 then
        -- Defensive fallback for models whose only non-locomotion clip is stretching.
        -- Keep its authored starting pose, not an endless stretch loop.
        if #stretch>0 then return stretch[1].name,0,entity end
        return nil
    end

    if not playerRed then
        if state.mode=="npc_action" then
            local act=state.action
            if act and now-state.start<clipDuration(act) then
                return act.name,math.max(0,now-state.start),entity
            end
            if act and stretching(act.name) then
                state.nextStretchAt=now+randomWait(state,120,240)
            else
                state.nextGestureAt=now+randomWait(state,70,125)
            end
            state.mode="npc_idle";state.start=now
            state.idleIndex=1;state.variantAt=now;state.action=nil
        end
        if state.mode~="npc_idle" then
            state.mode="npc_idle";state.start=now
            state.idleIndex=1;state.variantAt=now
            state.nextStretchAt=now+randomWait(state,120,240)
            state.nextGestureAt=now+randomWait(state,70,125)
        end
        local clip=idlePool[state.idleIndex] or idlePool[1]
        local elapsed=now-state.start
        if elapsed>=clipDuration(clip) then
            -- Only begin miscellaneous actions at a normal Idle loop boundary.
            local action=nil
            if #stretch>0 and #normal>0 and now>=state.nextStretchAt then
                action=stretch[nextRandom(state,#stretch,"actionLast")]
            elseif #extra>0 and #normal>0 and now>=state.nextGestureAt then
                action=extra[nextRandom(state,#extra,"actionLast")]
            end
            if action then
                state.mode="npc_action";state.action=action;state.start=now
                return action.name,0,entity
            end
            state.start=state.start+math.floor(elapsed/clipDuration(clip))*clipDuration(clip)
            if #idlePool>1 and now-state.variantAt>=NPC_IDLE_VARIANT_INTERVAL then
                state.idleIndex=nextRandom(state,#idlePool,"idleLast")
                state.start=now;state.variantAt=now
                clip=idlePool[state.idleIndex]
            end
        end
        return clip.name,math.max(0,now-state.start),entity
    end

    -- Red waits 20 seconds with NO input before each optional action.
    if state.mode=="action" then
        local act=state.action
        if act and now-state.start<clipDuration(act) and not buttonDown then
            return act.name,math.max(0,now-state.start),entity
        end
        if act and stretching(act.name) then
            state.nextStretchAt=now+randomWait(state,120,240)
        end
        state.lastInputAt=now
        state.mode="idle";state.start=now;state.idleIndex=1
        state.variantAt=now;state.action=nil
    end
    if state.mode~="idle" then
        state.mode="idle";state.start=now
        state.idleIndex=1;state.variantAt=now
    end
    local clip=idlePool[state.idleIndex] or idlePool[1]
    local elapsed=now-state.start
    if elapsed>=clipDuration(clip) then
        if not buttonDown and now-state.lastInputAt>=RED_ACTION_WAIT then
            local act=nil
            if #stretch>0 and now>=state.nextStretchAt then
                -- Stretching only after a longer 2-4 minute wait.
                if #extra==0 or nextRandom(state,3,"stretchChance")==1 then
                    act=stretch[nextRandom(state,#stretch,"stretchLast")]
                else
                    state.nextStretchAt=now+randomWait(state,120,240)
                end
            end
            if not act and #extra>0 then
                act=extra[nextRandom(state,#extra,"actionLast")]
            end
            if act then
                state.action=act;state.mode="action";state.start=now
                return act.name,0,entity
            end
        end
        state.start=state.start+math.floor(elapsed/clipDuration(clip))*clipDuration(clip)
        if #idlePool>1 and now-state.variantAt>=RED_IDLE_VARIANT_INTERVAL then
            state.idleIndex=nextRandom(state,#idlePool,"idleLast")
            state.start=now;state.variantAt=now
            clip=idlePool[state.idleIndex]
        end
    end
    return clip.name,math.max(0,now-state.start),entity
end

----------------------------------------------------------------
-- Procedural idle life
--
-- Artistic values should live in character_tuning.lua.
-- Defaults are kept here only as a safe fallback so older tuning
-- files remain compatible.
----------------------------------------------------------------

Registry.idle_animation =
    Tuning.idle_animation
    or {
        enabled = true,

        speed = 1.15,

        scale_y = 0.012,

        scale_xz = 0.003
    }


----------------------------------------------------------------
-- Player-specific authored states
--
-- Bicycle assets are resolved automatically when Recomp switches
-- the player's visual sprite to a bike/bicycle sprite:
--
--   assets/<player>_bike_idle.lua
--   assets/<player>_bike_walk.lua
----------------------------------------------------------------


----------------------------------------------------------------
-- Fly mount
--
-- Generic mounted-player pose convention:
--   assets/<player>_mount_walk.lua
--
-- Fly alternates between:
--   assets/bird_idle.lua
--   assets/bird_walk.lua
--   assets/<player>_mount_idle.lua
--   assets/<player>_mount_walk.lua
--
-- flying_offset:
--   positions the flying creature relative to the animation anchor.
--
-- rider_offset:
--   is added on top of flying_offset for the mounted character.
----------------------------------------------------------------

Registry.fly_mount = {

    -- The earlier "bird" and "red_mount" assets were not shipped in this
    -- package. Reuse a real 3D Flying Pokémon from the current model pack.
    base = "pokemon_pidgeot",

    ------------------------------------------------------------
    -- Geometry comes from Bird's own persistent mount tuning.
    -- The renderer still receives the semantic Fly field name
    -- `flying_offset`, but the source value belongs to Bird.
    ------------------------------------------------------------

    flying_offset =
        Tuning.mounts.bird.mount_offset,

    rider_offset =
        Tuning.mounts.bird.rider_offset
}


----------------------------------------------------------------
-- Fly world-space trajectory
--
-- Values come from character_tuning.lua.
-- All distances are expressed in world units.
--
-- takeoff:
--   time spent mounted at the player's position before departure.
--
-- offscreen:
--   duration between departure and return pass.
--   The composite stays visible at the end of the departure path and
--   keeps alternating idle/walk during this phase.
----------------------------------------------------------------

Registry.fly_animation =
    Tuning.fly.animation


----------------------------------------------------------------
-- Gen1Recomp sprite ID -> Porygonal basename
--
-- Naming convention:
--
-- WALKER:
--   assets/<base>_idle.lua
--   assets/<base>_walk.lua
--
-- OPTIONAL SPECIAL ASSET:
--   assets/<base>_spe1.lua
--
-- STATIC:
--   assets/<base>_idle.lua
--
-- Shared texture:
--   assets/grayscale_palette.png
----------------------------------------------------------------

Registry.characters = {

    ----------------------------------------------------------------
    -- Main characters
    ----------------------------------------------------------------

    SPRITE_RED = {
        base = "red"
    },

    SPRITE_BLUE = {
        base = "blue"
    },

    SPRITE_OAK = {
        base = "oak"
    },


    ----------------------------------------------------------------
    -- Overworld characters / NPCs
    ----------------------------------------------------------------

    SPRITE_YOUNGSTER = {
        base = "youngster"
    },

    SPRITE_MONSTER = {
        base = "monster"
    },

    SPRITE_COOLTRAINER_F = {
        base = "cooltrainer_f"
    },

    SPRITE_COOLTRAINER_M = {
        base = "cooltrainer_m",

        ------------------------------------------------------------
        -- Optional authored-figure replacement.
        --
        -- Dramatic Shape identifies the seated Pokémon Center person
        -- as an authored FIGURE cut from the tileset, not as the normal
        -- Cooltrainer billboard. The logical map entity remains useful
        -- as the stable identity anchor for Porygonal.
        ------------------------------------------------------------

        spe1 = {

            --------------------------------------------------------
            -- Pokémon Center seated authored FIGURE orientation.
            --
            -- The renderer now identifies that FIGURE directly on
            -- Pokémon Center maps. No logical NPC/entity-name match
            -- is involved here.
            --------------------------------------------------------

            yaw =
                math.rad(90)
        }
    },

    SPRITE_LITTLE_GIRL = {
        base = "little_girl"
    },

    SPRITE_BIRD = {
        base = "bird"
    },

    SPRITE_MIDDLE_AGED_MAN = {
        base = "middle_aged_man"
    },

    SPRITE_GAMBLER = {
        base = "gambler"
    },

    SPRITE_SUPER_NERD = {
        base = "super_nerd"
    },

    SPRITE_GIRL = {
        base = "girl"
    },

    SPRITE_HIKER = {
        base = "hiker"
    },

    SPRITE_BEAUTY = {
        base = "beauty"
    },

    SPRITE_GENTLEMAN = {
        base = "gentleman"
    },

    SPRITE_DAISY = {
        base = "daisy"
    },

    SPRITE_BIKER = {
        base = "biker"
    },

    SPRITE_SAILOR = {
        base = "sailor"
    },

    SPRITE_COOK = {
        base = "chef"
    },

    SPRITE_BIKE_SHOP_CLERK = {
        base = "bike_shop_clerk"
    },

    SPRITE_MR_FUJI = {
        base = "mr_fuji"
    },

    SPRITE_GIOVANNI = {
        base = "giovanni"
    },

    SPRITE_ROCKET = {
        base = "rocket"
    },

    SPRITE_CHANNELER = {
        base = "channeler"
    },

    SPRITE_WAITER = {
        base = "waiter"
    },

    SPRITE_SILPH_WORKER_F = {
        base = "silph_worker_f"
    },

    SPRITE_MIDDLE_AGED_WOMAN = {
        base = "middle_aged_woman"
    },

    SPRITE_BRUNETTE_GIRL = {
        base = "brunette_girl"
    },

    SPRITE_LANCE = {
        base = "lance"
    },


    ----------------------------------------------------------------
    -- Scientist
    --
    -- Two ROM IDs share the same visual asset.
    ----------------------------------------------------------------

    SPRITE_UNUSED_SCIENTIST = {
        base = "scientist"
    },

    SPRITE_SCIENTIST = {
        base = "scientist"
    },


    ----------------------------------------------------------------
    -- More overworld NPCs
    ----------------------------------------------------------------

    SPRITE_ROCKER = {
        base = "rocker"
    },

    SPRITE_SWIMMER = {
        base = "swimmer"
    },

    SPRITE_SAFARI_ZONE_WORKER = {
        base = "safari_zone_worker"
    },

    SPRITE_GYM_GUIDE = {
        base = "gym_guide"
    },

    SPRITE_GRAMPS = {
        base = "gramps"
    },

    SPRITE_CLERK = {
        base = "clerk"
    },

    SPRITE_FISHING_GURU = {
        base = "fishing_guru"
    },

    SPRITE_GRANNY = {
        base = "granny"
    },

    SPRITE_NURSE = {
        -- Same symbolic ID in all Gen 1 versions, but Yellow uses
        -- distinct authored artwork/model assets.
        base = IS_YELLOW and "nurse_Y" or "nurse"
    },

    SPRITE_LINK_RECEPTIONIST = {
        base = "link_receptionist"
    },

    SPRITE_SILPH_PRESIDENT = {
        base = "silph_president"
    },

    SPRITE_SILPH_WORKER_M = {
        base = "silph_worker_m"
    },

    SPRITE_WARDEN = {
        base = "warden"
    },

    SPRITE_CAPTAIN = {
        base = "captain"
    },

    SPRITE_FISHER = {
        base = "fisher"
    },

    SPRITE_KOGA = {
        base = "koga"
    },


    ----------------------------------------------------------------
    -- Guards
    ----------------------------------------------------------------

    SPRITE_GUARD = {
        base = "guard"
    },

    SPRITE_UNUSED_GUARD = {
        base = "guard"
    },


    ----------------------------------------------------------------
    -- Remaining overworld characters
    ----------------------------------------------------------------

    SPRITE_MOM = {
        base = "mom"
    },

    SPRITE_BALDING_GUY = {
        base = "balding_guy"
    },

    SPRITE_LITTLE_BOY = {
        base = "youngster"
    },


    ----------------------------------------------------------------
    -- Gameboy Kid
    ----------------------------------------------------------------

    SPRITE_UNUSED_GAMEBOY_KID = {
        base = "gameboy_kid"
    },

    SPRITE_GAMEBOY_KID = {
        base = "gameboy_kid"
    },


    ----------------------------------------------------------------
    -- Special characters / creatures
    ----------------------------------------------------------------

    SPRITE_FAIRY = {
        base = "fairy"
    },

    SPRITE_AGATHA = {
        base = "agatha"
    },

    SPRITE_BRUNO = {
        base = "bruno"
    },

    SPRITE_LORELEI = {
        base = "lorelei"
    },

    SPRITE_SEEL = {
        base = "seel",

        ------------------------------------------------------------
        -- Optional Surf mount configuration.
        --
        -- The normal overworld creature still uses:
        --   seel_idle.lua
        --   seel_walk.lua
        --
        -- These offsets are only applied when THIS visual sprite is
        -- being used by the PLAYER as a Surf mount.
        --
        -- floating_offset:
        --   Moves the creature relative to the water/world anchor.
        --   Useful later for Pokémon that need to sit deeper in water.
        --
        -- rider_offset:
        --   Added ON TOP of floating_offset for the rider.
        --   It is expressed in mount-local coordinates and therefore
        --   follows the mount/player facing.
        ------------------------------------------------------------

        surf_mount = {

            --------------------------------------------------------
            -- Geometry belongs to Seel itself.
            -- `floating_offset` remains the renderer-facing Surf
            -- semantic name, but its source is Seel.mount_offset.
            --------------------------------------------------------

            floating_offset =
                Tuning.mounts.seel.mount_offset,

            rider_offset =
                Tuning.mounts.seel.rider_offset
        }
    },


    ----------------------------------------------------------------
    -- STATIC OVERWORLD OBJECTS
    --
    -- These use only:
    --
    -- assets/<base>_idle.lua
    --
    -- They do not use walk, facing rotation or mirror.
    ----------------------------------------------------------------

    SPRITE_POKE_BALL = {
        base = "poke_ball",
        type = "static",
        idle_animation = false
    },

    SPRITE_FOSSIL = {
        base = "fossil",
        type = "static",
        idle_animation = false
    },

    SPRITE_BOULDER = {
        base = "boulder",
        type = "static",
        idle_animation = false
    },

    SPRITE_PAPER = {
        base = "paper",
        type = "static",
        idle_animation = false
    },

    SPRITE_POKEDEX = {
        base = "pokedex",
        type = "static",
        idle_animation = false
    },

    SPRITE_CLIPBOARD = {
        base = "clipboard",
        type = "static",
        idle_animation = false
    },

    SPRITE_SNORLAX = {
        base = "snorlax",
        type = "static"
    },


    ----------------------------------------------------------------
    -- Old Amber
    --
    -- Both IDs use the same asset.
    ----------------------------------------------------------------

    SPRITE_UNUSED_OLD_AMBER = {
        base = "old_amber",
        type = "static",
        idle_animation = false
    },

    SPRITE_OLD_AMBER = {
        base = "old_amber",
        type = "static",
        idle_animation = false
    },


    ----------------------------------------------------------------
    -- Gambler asleep
    --
    -- Three IDs use the same visual asset.
    ----------------------------------------------------------------

    SPRITE_UNUSED_GAMBLER_ASLEEP_1 = {
        base = "gambler_asleep",
        type = "static"
    },

    SPRITE_UNUSED_GAMBLER_ASLEEP_2 = {
        base = "gambler_asleep",
        type = "static"
    },

    SPRITE_GAMBLER_ASLEEP = {
        base = "gambler_asleep",
        type = "static"
    }

}


----------------------------------------------------------------
-- Pokémon Yellow-only overworld sprites
--
-- Yellow inserts ten animated overworld sprite IDs after SEEL.
-- Asset naming convention:
--
--   assets/<name>_Y_idle.lua
--   assets/<name>_Y_walk.lua
--
-- Numeric IDs below are Yellow overworld IDs for documentation only.
-- Runtime matching stays SYMBOLIC so Red/Blue's shifted numeric IDs
-- never collide with Yellow.
----------------------------------------------------------------

if IS_YELLOW then

    Registry.characters.SPRITE_PIKACHU = {
        -- Yellow: $3D / 61
        base = "pikachu_Y"
    }

    Registry.characters.SPRITE_OFFICER_JENNY = {
        -- Yellow: $3E / 62
        base = "officer_jenny_Y"
    }

    Registry.characters.SPRITE_SANDSHREW = {
        -- Yellow: $3F / 63
        base = "sandshrew_Y"
    }

    Registry.characters.SPRITE_ODDISH = {
        -- Yellow: $40 / 64
        base = "oddish_Y"
    }

    Registry.characters.SPRITE_BULBASAUR = {
        -- Yellow: $41 / 65
        base = "bulbasaur_Y"
    }

    Registry.characters.SPRITE_JIGGLYPUFF = {
        -- Yellow: $42 / 66
        base = "jigglypuff_Y"
    }

    Registry.characters.SPRITE_CLEFAIRY = {
        -- Yellow: $43 / 67
        base = "clefairy_Y"
    }

    Registry.characters.SPRITE_CHANSEY = {
        -- Yellow: $44 / 68
        base = "chansey_Y"
    }

    Registry.characters.SPRITE_JESSIE = {
        -- Yellow: $45 / 69
        base = "jessie_Y"
    }

    Registry.characters.SPRITE_JAMES = {
        -- Yellow: $46 / 70
        base = "james_Y"
    }
end


----------------------------------------------------------------
-- Build asset definition automatically
--
-- Example:
--
-- base = "girl"
-- pose = "walk"
--
-- ->
--
-- assets/girl_walk.lua
----------------------------------------------------------------

-- Game-renderer-native mesh assets exported from the supplied GLBs.
-- Styles are independent selections; changed options take effect immediately.
-- The Poké Ball is a fixed prop: never request an animation or procedural idle.
-- v27: lookup table allocated once (not rebuilt for every NPC per frame).
local authoredPokemonClips={
        ["pokemon_meowth"]=true,
        ["pokemon_doduo"]=true,
        ["pokemon_machoke"]=true,
        ["pokemon_wigglytuff"]=true,
        ["pokemon_oddish"]=true,
        ["pokemon_sandshrew"]=true,
        ["pokemon_psyduck"]=true,
        ["pokemon_fearow"]=true,
 }
-- v30.1 compact: identical variant geometry/animations share their parent files.
local SHARED_VARIANT_GEOMETRY = {
    ["biker_cycling_v29_b"]="biker_cycling",
    ["biker_cycling_v29_c"]="biker_cycling",
    ["biker_v29_b"]="biker",
    ["biker_v29_c"]="biker",
    ["birdkeeper_v29_b"]="birdkeeper",
    ["birdkeeper_v29_c"]="birdkeeper",
    ["burglar_v29_b"]="burglar",
    ["burglar_v29_c"]="burglar",
    ["cook_new_v29_b"]="cook_new",
    ["cook_new_v29_c"]="cook_new",
    ["engineer_v30_b"]="engineer",
    ["fisherman_v29_b"]="fisherman",
    ["fisherman_v29_c"]="fisherman",
    ["gambler_v30_b"]="gambler",
    ["gambler_v30_c"]="gambler",
    ["gameboy_v29_b"]="gameboy",
    ["gameboy_v29_c"]="gameboy",
    ["gentleman_v29_b"]="gentleman",
    ["gentleman_v29_c"]="gentleman",
    ["karate_minion_v29_b"]="karate_minion",
    ["karate_minion_v29_c"]="karate_minion",
    ["lass_v29_b"]="lass",
    ["lass_v29_c"]="lass",
    ["male_guard_v29_b"]="male_guard",
    ["male_guard_v29_c"]="male_guard",
    ["rocket_grunt_f_v29_b"]="rocket_grunt_f",
    ["rocket_grunt_f_v29_c"]="rocket_grunt_f",
    ["naked_sailor_v29_b"]="naked_sailor",
    ["naked_sailor_v29_c"]="naked_sailor",
    ["rocket_grunt_m_v29_b"]="rocket_grunt_m",
    ["rocket_grunt_m_v29_c"]="rocket_grunt_m",
    ["scientist_m_v29_b"]="scientist_m",
    ["scientist_m_v29_c"]="scientist_m",
    ["shaman_v29_b"]="shaman",
    ["shaman_v29_c"]="shaman",
    ["swimmer_f_v29_b"]="swimmer_f",
    ["swimmer_f_v29_c"]="swimmer_f",
    ["swimmer_m_v29_b"]="swimmer_m",
    ["swimmer_m_v29_c"]="swimmer_m",
    ["youngster_v29_b"]="youngster",
    ["youngster_v29_c"]="youngster",
    ["youngster_v30_c"]="youngster",
}

local function buildAsset(base,pose)
    local viewerJpegPokemon = {
        ["pokemon_wigglytuff"]=true,
        ["pokemon_slowbro"]=true,
        ["pokemon_sandshrew"]=true,
        ["pokemon_psyduck"]=true,
        ["pokemon_omanyte"]=true,
        ["pokemon_oddish"]=true,
        ["pokemon_meowth"]=true,
        ["pokemon_machoke"]=true,
        ["pokemon_lapras"]=true,
        ["pokemon_jigglypuff"]=true,
        ["pokemon_fearow"]=true,
        ["pokemon_doduo"]=true,
        ["pokemon_cubone"]=true,
        ["pokemon_articuno"]=true,
        ["pokemon_bulbasaur"]=true,
        ["pokemon_chansey"]=true,
        ["pokemon_charmander"]=true,
        ["pokemon_clefairy"]=true,
        ["pokemon_eevee"]=true,
        ["pokemon_electrode"]=true,
        ["pokemon_kangaskhan"]=true,
        ["pokemon_machop"]=true,
        ["pokemon_mewtwo"]=true,
        ["pokemon_moltres"]=true,
        ["pokemon_nidoran_f"]=true,
        ["pokemon_nidoran_m"]=true,
        ["pokemon_nidorino"]=true,
        ["pokemon_pidgeot"]=true,
        ["pokemon_pidgey"]=true,
        ["pokemon_pikachu"]=true,
        ["pokemon_poliwrath"]=true,
        ["pokemon_seel"]=true,
        ["pokemon_slowpoke"]=true,
        ["pokemon_snorlax"]=true,
        ["pokemon_squirtle"]=true,
        ["pokemon_voltorb"]=true,
        ["pokemon_zapdos"]=true,
    }
    local shade,poly=Registry.getStyle()
    if shade~="toon" and shade~="toon_outline" and shade~="smooth_lit" and shade~="low_poly" then shade="n64" end
    if poly~="smooth" then poly="low" end
    if base=="poke_ball" or base=="pokeball" then
        return {
            mesh="assets/render/pokeball_rest.bin",
            texture="assets/textures/pokeball.png",
            paletteMode="direct",shading=shade,poly=poly
            -- Intentionally no animation = always draw original rest vertices.
        }
    end
    -- Pokémon definitions use the same renderer as humans; their mesh and
    -- texture paths are looked up by name, while per-object placements
    -- remain editable in npc_decisions.lua.
    if base:sub(1,8)=="pokemon_" then
        local asset={
            mesh="assets/render/"..base.."_rest.bin",
            texture="assets/textures/"..base..".png",
            paletteMode="direct",shading=shade,poly=poly
        }
        -- RUMBLE variant: Rumble rest geometry cannot be driven by the unrelated
        -- original GLB skeleton/vertex tracks. Use the renderer's non-destructive,
        -- absolute-rest procedural breathing for all decorative Pokemon instead.
        -- Red, human NPCs, the custom Pidgeot HM Fly and all their clips are untouched.
        asset.animation={pokemonBreathing=true,time=animationTime(),entity=base}
        return asset
    end
    -- Recolor variants reuse the exact original vertex/index and animation data.
    -- Only the texture and per-entity animation identity differ.
    local geometryBase = SHARED_VARIANT_GEOMETRY[base] or base
    local clip,time,entity=animationSelection(base,pose)
    local asset={
        mesh="assets/render/"..geometryBase.."_rest.bin",
        -- v30.4: runtime geometry sharing ALSO uses the canonical verified
        -- material palette, preventing unverified recolor corruption.
        -- NPC identity and animation entity remain variant-specific.
        texture="assets/textures/"..geometryBase..((geometryBase=="copycat_doll_bird" or geometryBase=="copycat_doll_fairy" or geometryBase=="copycat_doll_monster" or geometryBase=="red_surf") and ".jpg" or ".png"),
        paletteMode="direct",shading=shade,poly=poly
    }
    if clip then
        asset.animation={model=geometryBase,clip=clip,time=time,entity=entity}
    end
    return asset
end

----------------------------------------------------------------
-- Fly composite lookup
--
-- Kept in the Registry so the renderer only receives a semantic
-- composite definition and does not hard-code asset filenames.
----------------------------------------------------------------

-- Fly mount selection is intentionally limited to models shipped here.
-- If the game exposes the HM user's species, the Dramaless adapter can
-- select it; otherwise the user may set Tuning.fly.mount_base explicitly.
local availableFlyMounts = {
    pokemon_pidgeot = true,
    pokemon_articuno = true,
    pokemon_zapdos = true,
    pokemon_moltres = true
}

-- Custom Pidgeot is selected for HM Fly regardless of which Pokemon used the HM.
-- All model data and textures are this mod's; the actual destination and map
-- transition are owned by Gen1Recomp / the selected external voxel renderer.
function Registry.lookupFly(pose, phase, jumpTime, requestedMount)
    local step=math.floor(animationTime()*12)%12
    local frame=string.format("_%02d_rest.bin",step)
    local riderFrame=frame
    local riderBase="custom_red_flyride"
    if phase=="jump" or phase=="boarding" or phase=="dismount" or phase=="land_jump" then
        local t=tonumber(jumpTime) or 0
        local index=math.max(0,math.min(11,math.floor(t/1.875*11+0.5)))
        riderBase="custom_red_jump"
        riderFrame=string.format("_%02d_rest.bin",index)
    elseif phase=="idle" then
        riderBase="custom_red_idle";riderFrame="_00_rest.bin"
    end
    return {
        flying_offset=Registry.fly_mount.flying_offset,
        rider_offset=Registry.fly_mount.rider_offset,
        parts={
           {role="mount",asset={mesh="assets/render/custom_pidgeot_fly"..frame,
             texture="assets/textures/pokemon_pidgeot.png",paletteMode="direct"}},
           {role="rider",asset={mesh="assets/render/"..riderBase..riderFrame,
             texture="assets/textures/custom_red_flyride.png",paletteMode="direct"}}
        }
    }
end

----------------------------------------------------------------
-- Pokémon Center authored-figure special lookup
--
-- The seated character is emitted by Dramatic Shape as an authored
-- FIGURE rather than a normal SpriteBillboards entity. The renderer
-- identifies that FIGURE directly on Pokémon Center maps.
----------------------------------------------------------------

function Registry.lookupPokecenterSeatedFigure(mapId)

    -- Decorative sitting figure is NOT the walking trainer; give each center
    -- a coherent visitor identity, without cloning Cooltrainer on every map.
    local center=slugify(mapId)
    -- Use characters with authored Sit clips. Alternating visitors avoids
    -- making every Center the same stationary Cool Trainer.
    local occupants={
        viridianpokecenter="middle_age_woman_new",
        pewterpokecenter="little_girl_new",
        ceruleanpokecenter="middle_age_woman_new",
        vermilionpokecenter="little_girl_new",
        lavenderpokecenter="middle_age_woman_new",
        celadonpokecenter="little_girl_new",
        fuchsiapokecenter="middle_age_woman_new",
        saffronpokecenter="little_girl_new",
        cinnabarpokecenter="middle_age_woman_new",
        mtmoonpokecenter="little_girl_new",
        rocktunnelpokecenter="middle_age_woman_new",
        indigoplateaulobby="little_girl_new",
    }
    local base=occupants[center] or "middle_age_woman_new"
    local character = {base=base}

    if not character.base then return nil end


    local spe1 = character.spe1 or {}
    -- Keep the authored bench figure's animation identity independent from
    -- whichever walking NPC was last looked up by the renderer.
    local priorContext=Registry._lookupContext
    Registry._lookupContext={mapId=mapId,objectId="pokecenter_seated",isPlayer=false}
    local seatedAsset=buildAsset(character.base,"spe1")
    Registry._lookupContext=priorContext

    return {

        spriteId =
            "SPRITE_MIDDLE_AGED_MAN",

        pose =
            "spe1",

        asset = seatedAsset,

        facing =
            "down",

        mirror =
            false,

        yaw =
            spe1.yaw
            or math.rad(90)
    }
end


----------------------------------------------------------------
-- Registry lookup
----------------------------------------------------------------

function Registry.lookup(
    spriteId,
    frame,
    mirror,
    facing,
    context
)

    Registry._lookupContext=context

    -- The game maintains an explicit surfing state.  The visual sprite can
    -- remain RED (or be substituted by the renderer), so do not require
    -- SPRITE_SEEL to select the user's authored Red + Lapras GLB.
    -- Never use this rule for regular SEEL or other NPC entities.
    if context and context.isPlayer
        and (context.surfing == true or spriteId == "SPRITE_SEEL") then
        return {
            asset = buildAsset("red_surf", "idle"),
            facing = facing,
            mirror = mirror
        }
    end


----------------------------------------------------------------
-- PLAYER FISHING
--
-- Fishing is an explicit player semantic state supplied by the
-- renderer bridge. The fishing rod is authored directly into the
-- player mesh; it is not a separate Porygonal asset.
--
-- Asset:
--   assets/<player>_fishing_idle.lua
----------------------------------------------------------------

if context
    and context.isPlayer
    and context.fishing then

    local player =
        Registry.player


    if player
        and player.base then

        return {
            type =
                "fishing",

            asset =
                buildAsset(
                    "red_fishing",
                    "idle"
                ),

            facing =
                facing,

            mirror =
                mirror
        }
    end
end


    ------------------------------------------------------------
    -- PLAYER BICYCLE VISUAL SWITCH
    --
    -- Gen1/Recomp may expose the bicycle as a simple replacement
    -- of the player's current visual sprite rather than as a separate
    -- world entity/composite.
    --
    -- We keep recognition deliberately semantic:
    --   * player only
    --   * symbolic sprite id contains BIKE/BICYCLE, OR
    --   * current sprite image path contains bike/bicycle
    --
    -- This cannot collide with NPC SPRITE_BIKER or the bike-shop
    -- clerk because `context.isPlayer` is required.
    --
    -- Assets:
    --   assets/<player>_bike_idle.lua
    --   assets/<player>_bike_walk.lua
    ------------------------------------------------------------

    if context
        and context.isPlayer then

        local idText =
            string.upper(
                tostring(
                    spriteId
                    or ""
                )
            )


        local imageText =
            string.lower(
                tostring(
                    context.spriteImage
                    or ""
                )
            )


        local isBikeVisual =
            context.cycling == true
            or string.find(
                idText,
                "BIKE",
                1,
                true
            ) ~= nil
            or string.find(
                idText,
                "BICYCLE",
                1,
                true
            ) ~= nil
            or string.find(
                imageText,
                "bike",
                1,
                true
            ) ~= nil
            or string.find(
                imageText,
                "bicycle",
                1,
                true
            ) ~= nil


        if isBikeVisual then

            local player =
                Registry.player


            if player
                and player.base then

                local pose =
                    (
                        frame == 3
                        or frame == 4
                        or frame == 5
                    )
                    and "walk"
                    or "idle"


                return {

                    type =
                        "bike",

                    asset =
                        buildAsset(
                            "red_cycling",
                            pose
                        ),

                    facing =
                        facing,

                    mirror =
                        mirror
                }
            end
        end
    end


    local character = Registry.characters[spriteId]
    if not (context and context.isPlayer) then
        local db=Registry.Decisions
        local ref=context and context.entityRef
        local mapKey=slugify(context and context.mapId)
        local cached=nil
        if type(ref)=="table" then
            cached=Registry._npcIdentityLocks[ref]
            -- Same Lua entity table can theoretically be reused after a map
            -- transition; map-qualified identity avoids stale replacements.
            if cached and cached.mapKey~=mapKey then cached=nil end
        end

        local selected
        if cached then
            selected=cached.base
        else
            local obj=tostring(context and context.objectId or "")
            -- Explicit game-version coordinate overrides are editable data
            -- (e.g. Red/Blue Slowbro vs Yellow Electrode in Cerulean City).
            -- Everything without a version override follows the original
            -- fixed Pokémon -> unique object -> map spawn -> sprite precedence.
            local specialPokemon=nil
            local versionCell=nil
            if context and mapKey~="" and type(context.cellX)=="number" and type(context.cellY)=="number" then
                local coord=mapKey..":"..tostring(math.floor(context.cellX))..":"..tostring(math.floor(context.cellY))
                local prefix=IS_YELLOW and "yellow:" or "redblue:"
                versionCell=db.byMapCell[prefix..coord]
                local candidate=versionCell or db.byMapCell[coord]
                if type(candidate)=="string" and candidate:sub(1,8)=="pokemon_" then
                    specialPokemon=candidate
                end
            end
            -- v29: dialogue-confirmed job/role, then unique game object identity,
            -- then version-scoped Pokémon cells; generic sprite is strictly last.
            local dialogueChoice = (db.byDialogue or {})[obj]
                or (db.byDialogue or {})[obj:upper()]
            if not dialogueChoice and context and mapKey~=""
                and type(context.cellX)=="number" and type(context.cellY)=="number" then
                local xy=mapKey..":"..tostring(math.floor(context.cellX))..":"..tostring(math.floor(context.cellY))
                dialogueChoice=(db.byDialogueCell or {})[(IS_YELLOW and "yellow:" or "redblue:")..xy]
                    or (db.byDialogueCell or {})[xy]
            end
            -- v39: ORIGINAL ROM trainer class is authoritative. Exact game
            -- version + map + object (or spawn cell) outranks dialogue labels,
            -- decorative sprite and old map appearance guesses. A numeric
            -- objectId is deliberately never trusted without map coordinates.
            local sourceTrainer=nil
            local sourceVersion=IS_YELLOW and "yellow" or "redblue"
            if mapKey~="" and obj~="" then
                sourceTrainer=(db.bySourceTrainerObject or {})[
                    sourceVersion..":"..mapKey..":"..obj:upper()]
            end
            if not sourceTrainer and mapKey~="" and context
                and type(context.cellX)=="number"
                and type(context.cellY)=="number" then
                sourceTrainer=(db.bySourceTrainerCell or {})[
                    sourceVersion..":"..mapKey..":"..
                    tostring(math.floor(context.cellX))..":"..
                    tostring(math.floor(context.cellY))]
            end
            -- v40: Dialogue-first civilian casting. Do not let old generic
            -- sprite, object alias, or outdated color variants override a
            -- verified NPC identity; actual ROM trainer class still wins.
            local sourceDialogue=nil
            if mapKey~="" and obj~="" then
                sourceDialogue=(db.bySourceDialogueObject or {})[
                    sourceVersion..":"..mapKey..":"..obj:upper()]
            end
            if not sourceDialogue and mapKey~="" and context
                and type(context.cellX)=="number"
                and type(context.cellY)=="number" then
                sourceDialogue=(db.bySourceDialogueCell or {})[
                    sourceVersion..":"..mapKey..":"..
                    tostring(math.floor(context.cellX))..":"..
                    tostring(math.floor(context.cellY))]
            end
            -- v46: Bill's (6,5) location is shared by two original story states.
            -- SPRITE_MONSTER is the pre-restoration state;
            -- SPRITE_SUPER_NERD is human Bill. v51 enforces the final choice
            -- after any cached object/map fallback, independent of object ID.
            -- This guarded fallback matters when renderer reports numeric IDs only.
            if not sourceTrainer and not sourceDialogue and mapKey=="billshouse"
                and spriteId=="SPRITE_SUPER_NERD" and context
                and type(context.cellX)=="number" and type(context.cellY)=="number"
                and math.floor(context.cellX)==6 and math.floor(context.cellY)==5 then
                sourceDialogue="bill"
            end
            selected=sourceTrainer or sourceDialogue or dialogueChoice or versionCell or specialPokemon
                or db.byObject[obj] or db.byObject[obj:upper()]
            local recognized=(selected~=nil)
            -- Exact role reconstruction for Route 1: the Mart sample worker uses
            -- the SAME sprite as the ledge youngster and moves between cells.
            -- Resolve from stable original-spawn vicinity before sprite fallback.
            if mapKey=="route1" and spriteId=="SPRITE_YOUNGSTER"
                and context and not context.isPlayer then
                if obj=="ROUTE1_YOUNGSTER1" then
                    selected="employee"
                elseif obj=="ROUTE1_YOUNGSTER2" then
                    selected="youngster"
                elseif not dialogueChoice and type(context.cellX)=="number" and type(context.cellY)=="number" then
                    local x,y=context.cellX,context.cellY
                    local first=(x-5)^2+(y-24)^2
                    local second=(x-15)^2+(y-13)^2
                    -- The two source spawns occupy separate ends of Route 1.
                    -- This is semantic source-casting, not movement-speed logic.
                    selected=(first<=second) and "employee" or "youngster"
                end
                recognized=selected~=nil
            end

            -- Identity overrides are data-driven: npc_decisions.lua.
            -- If the original object ID is unknown, try its map spawn cell.
            if not selected and context then
                local x,y=context.cellX,context.cellY
                if mapKey~="" and type(x)=="number" and type(y)=="number" then
                    selected=db.byMapCell[mapKey..":"..tostring(math.floor(x))..":"..tostring(math.floor(y))]
                    if selected then recognized=true end
                end
            end

            -- v11: Missing logical object IDs in some renderer versions:
            -- restore only the uniquely identified zoo animals using their
            -- original map sprites and authored start coordinates.
            -- Do not replace generic MONSTER/FAIRY globally.
            if not selected and mapKey=="fuchsiacity" then
                if spriteId=="SPRITE_FAIRY" then
                    selected="pokemon_chansey"
                elseif spriteId=="SPRITE_SEEL" then
                    selected="pokemon_lapras"
                elseif spriteId=="SPRITE_MONSTER" and context
                   and type(context.cellX)=="number" and type(context.cellY)=="number" then
                    local x,y=context.cellX,context.cellY
                    if math.abs(x-12)<=3 and math.abs(y-6)<=3 then
                        selected="pokemon_kangaskhan"
                    elseif math.abs(x-30)<=3 and math.abs(y-12)<=3 then
                        selected="pokemon_slowpoke"
                    end
                elseif spriteId=="SPRITE_POKE_BALL" and context
                   and type(context.cellX)=="number" and type(context.cellY)=="number"
                   and math.abs(context.cellX-25)<=2 and math.abs(context.cellY-6)<=2 then
                    selected="pokemon_voltorb"
                end
                if selected then recognized=true end
            end
            -- Additional verified single-species monster placements. A tight
            -- proximity threshold prevents unrelated Monster sprites hijacking
            -- the replacement on the same map.
            if not selected and context and type(context.cellX)=="number"
                and type(context.cellY)=="number" then
                local x,y=context.cellX,context.cellY
                if mapKey=="ceruleancity" and spriteId=="SPRITE_MONSTER"
                   and math.abs(x-28)<=2 and math.abs(y-26)<=2 then
                    selected="pokemon_slowbro"
                elseif mapKey=="celadoncity" and spriteId=="SPRITE_MONSTER"
                   and math.abs(x-30)<=2 and math.abs(y-12)<=2 then
                    selected="pokemon_poliwrath"
                elseif mapKey=="pewternidoranhouse" and spriteId=="SPRITE_MONSTER"
                   and math.abs(x-4)<=2 and math.abs(y-5)<=2 then
                    selected="pokemon_nidoran_m"
                end
                if selected then recognized=true end
            end

            -- v30: Source-backed nearest trainer spawn for numeric-only renderer IDs.
            if not selected and context and mapKey~="" and
                type(context.cellX)=="number" and type(context.cellY)=="number" then
                local roster=(db.trainerSpawnRoster or {})[mapKey]
                if type(roster)=="table" then
                    local winner,best,runner=nil,13,math.huge
                    for _,spawn in ipairs(roster) do
                        if spawn.sprite==spriteId and
                            (not spawn.version or spawn.version==(IS_YELLOW and "yellow" or "redblue")) then
                            local dx=context.cellX-spawn.x
                            local dy=context.cellY-spawn.y
                            local ds=dx*dx+dy*dy
                            if ds<best then runner=best;best=ds;winner=spawn
                            elseif ds<runner then runner=ds end
                        end
                    end
                    if winner and runner-best>=1 then
                        selected=winner.base;recognized=true
                    end
                end
            end

            -- v29: source-spawn nearest-neighbor fallback for ambiguous numeric
            -- object IDs. Activated only for dialogue-confirmed / diversified
            -- actors whose renderer has lost the exported ROM object name.
            if not selected and mapKey~="" and context
                and type(context.cellX)=="number" and type(context.cellY)=="number" then
                local roster=(db.spawnRoster or {})[mapKey]
                if type(roster)=="table" then
                    local winner=nil
                    local best=13 -- within sqrt(13) tiles of authored spawn
                    local runner=math.huge
                    for _,spawn in ipairs(roster) do
                        if spawn.sprite==spriteId then
                            local dx=context.cellX-spawn.x
                            local dy=context.cellY-spawn.y
                            local ds=dx*dx+dy*dy
                            if ds<best then runner=best;best=ds;winner=spawn
                            elseif ds<runner then runner=ds end
                        end
                    end
                    if winner and runner-best>=1 then
                        selected=winner.base;recognized=true
                    end
                end
            end
            -- Viridian-only role fallback for incomplete runtime object IDs.
            -- The named city boys are resolved above by unique ID / spawn cell.
            if not selected and spriteId=="SPRITE_YOUNGSTER" then
                if mapKey=="viridiancity" then
                    local xpos=tonumber(context and context.cellX)
                    selected=(xpos and xpos>=24) and "bug_catcher" or "boy"
                elseif mapKey=="viridianmart" or mapKey=="viridianpokemart" then
                    selected="employee"
                end
            end
            -- Generic sprite fallback is deliberately NOT a unique NPC identity.
            -- Named leaders and Elite Four are never assigned through this path.
            if not selected and mapKey:find("pokecenter",1,true) then
                -- Stable visual categories, no global seated Cooltrainer clone.
                -- Named nurses/receptionists resolve via object/cell tables.
                local visitors={
                    SPRITE_ROCKER="jr_trainer_m",
                    SPRITE_SUPER_NERD="scientist_m",
                    SPRITE_GENTLEMAN="gentleman",
                    SPRITE_COOLTRAINER_M="jr_trainer_m",
                    SPRITE_COOLTRAINER_F="jr_trainer_f",
                    SPRITE_YOUNGSTER="boy",
                    SPRITE_LITTLE_BOY="boy",
                    SPRITE_LITTLE_GIRL="lass",
                    SPRITE_GIRL="lass",
                    SPRITE_GAMBLER="old_guy2",
                    SPRITE_FISHER="fisherman",
                    SPRITE_SILPH_WORKER_M="employee",
                    SPRITE_SILPH_WORKER_F="scientist_f",
                }
                selected=visitors[spriteId]
            end
            if not selected and mapKey:find("mart",1,true) then
                -- Mart patrons are not automatically converted into Youngsters.
                if spriteId=="SPRITE_COOLTRAINER_M" then
                    selected="jr_trainer_m"
                elseif spriteId=="SPRITE_COOLTRAINER_F" then
                    selected="jr_trainer_f"
                end
            end
            if not selected and spriteId=="SPRITE_COOLTRAINER_F" then
                selected="cooltrainer_f"
            elseif not selected and spriteId=="SPRITE_COOLTRAINER_M" then
                selected="cooltrainer_m"
            end
            if not selected and mapKey=="fuchsiagym"
                and spriteId=="SPRITE_ROCKER" then
                selected="psychic_m"
            end
            -- v48: The source ROM has no ordinary SPRITE_GHOST map objects in
            -- Pokemon Tower. If an overworld renderer supplies a ghost sprite
            -- for a scripted apparition, use the existing Ghost GLB only in
            -- the Tower. This does not intercept the *battle* ghost sprite,
            -- does not replace Channelers, and does not add map NPC spawns.
            if not selected and mapKey:match("^pokemontower")
                and (spriteId=="SPRITE_GHOST" or spriteId=="GHOST") then
                selected="ghost"
                recognized=true
            end
            if not selected then selected=db.bySprite[spriteId] end
            -- Do not permanently lock the generic Youngster sprite on
            -- Route 1 when identifying data hasn't arrived yet; retry
            -- on the next frame until the specific identity is known.
            local unresolvedRoute1=(mapKey=="route1"
                and spriteId=="SPRITE_YOUNGSTER" and not recognized)
            -- Lock only a verified object/cell identity. Never freeze a
            -- sprite-only fallback before the real object identity arrives.
            if selected and recognized and mapKey~="" and type(ref)=="table"
                and not unresolvedRoute1 then
                Registry._npcIdentityLocks[ref]={mapKey=mapKey,base=selected}
            end
        end
        -- v51: Bill is story-state-specific.  Earlier builds could cache the
        -- Pokemon-form Nerd proxy on an entity and reuse it after the game
        -- changed that same entity to SPRITE_SUPER_NERD.  The initial legacy
        -- byObject/byMapCell aliases also selected Nerd in numeric-ID renderers.
        -- Only Bill's House is affected. Re-check the CURRENT source sprite on
        -- every lookup, so the human and Pokemon story states cannot crossfade.
        local billHouse = mapKey == "billshouse"
            or tostring(context and context.objectId or ""):upper():match("^BILLSHOUSE_BILL") ~= nil
        if billHouse and spriteId == "SPRITE_SUPER_NERD" then
            selected = "bill"                    -- restored human Bill
        elseif billHouse and spriteId == "SPRITE_MONSTER" then
            -- Temporary 3D monster-shaped visual proxy: never show a human
            -- Nerd here; do not change the source script or story state.
            selected = "pokemon_nidorino"
        end
        if billHouse and type(ref) == "table"
           and (spriteId == "SPRITE_SUPER_NERD" or spriteId == "SPRITE_MONSTER") then
            Registry._npcIdentityLocks[ref] = {
                mapKey = mapKey,
                base = selected,
                billSprite = spriteId
            }
        end
        if selected then
            if selected=="pokeball" or selected=="poke_ball" then
                character={base="pokeball",type="static",idle_animation=false}
            else
                character={base=selected}
            end
        end
    end


    ----------------------------------------------------------------
    -- v44: Authored chair-tile occupancy, not generic STAY movement.
    -- Do not change NPC world position or game collision/dialogue.
    -- These source-locked identities select only visual GLB animation.
    ----------------------------------------------------------------
    local chair=nil
    if context and not context.isPlayer and type(SeatedNPCs)=="table"
       and type(SeatedNPCs.resolve)=="function" then
        chair=SeatedNPCs.resolve(IS_YELLOW,context.mapId,context.cellX,
            context.cellY,spriteId,context.objectId)
    end
    if chair then
        -- Source-verified casting takes precedence over a generic sprite
        -- fallback, but only for the audited object in this exact tile.
        character={base=chair.base}
        if context then context.seatedId=chair.identity end
        local face=(chair.facing~="none" and chair.facing) or facing
        local isHuman=(chair.category~="fan_pet")
        local mode=(isHuman and chair.clip=="Sit") and "sit" or "idle"
        return {
            asset=buildAsset(character.base,mode),
            facing=face,
            mirror=(face=="right"),
            idle_animation=false
        }
    end

    ----------------------------------------------------------------
    -- Unknown sprite
    --
    -- Dramatic Shape keeps rendering its original sprite.
    ----------------------------------------------------------------

    if not character then
        return nil
    end

    -- Actual floating/swimming GLB for NPCs standing in a water cell.
    -- Keep the standing swimmer on land. Never change the shared sprite
    -- definition: one sprite type can be present in both environments.
    if context and not context.isPlayer and context.onWaterCell then
        local swimGender=character.base:match("^swimmer_([mf])")
        if swimGender then
            character = {base = "swimmer_submerged_" .. swimGender}
        end
    end

    ----------------------------------------------------------------
    -- PLAYER SURF COMPOSITE
    --
    -- Recomp uses SPRITE_SEEL as the player's visual sprite while
    -- surfing. The SAME sprite ID is also used by ordinary overworld
    -- creatures, so isPlayer is the discriminator.
    --
    -- The active player base is supplied by Registry.player because
    -- pose() has already substituted the Surf visual sprite at this point.
    -- That lets us resolve:
    --
    --   Seel creature:
    --       seel_idle / seel_walk
    --
    --   Player surfing on Seel:
    --       seel_idle / seel_walk
    --       +
    --       <player>_mount_idle / <player>_mount_walk
    ----------------------------------------------------------------

    if context
        and context.isPlayer
        and character.surf_mount then

        local riderCharacter =
            Registry.player


        if riderCharacter
            and riderCharacter.base then

            local pose =
                (
                    frame == 3
                    or frame == 4
                    or frame == 5
                )
                and "walk"
                or "idle"


            return {

                type =
                    "composite",

                facing =
                    facing,

                mirror =
                    mirror,

                floating_offset =
                    character.surf_mount.floating_offset,

                rider_offset =
                    character.surf_mount.rider_offset,

                parts = {

                    {
                        role =
                            "mount",

                        asset =
                            buildAsset(
                                character.base,
                                pose
                            ),

                        mirror =
                            mirror
                    },

                    {
                        role =
                            "rider",

                        asset =
                            buildAsset(
                                riderCharacter.base
                                .. "_mount",
                                pose
                            ),

                        mirror =
                            mirror
                    }
                }
            }
        end
    end


    ----------------------------------------------------------------
    -- STATIC OBJECT
    --
    -- Always uses a single idle mesh.
    --
    -- Orientation is fixed to DOWN / +Z.
    -- Mirror is disabled.
    ----------------------------------------------------------------

    if character.type == "static" then

        return {

            type = "static",

            asset =
                buildAsset(
                    character.base,
                    "idle"
                ),

            facing =
                "down",

            mirror =
                false,

            -- Static props must never receive renderer-generated breathing.
            idle_animation = false
        }

    end


    -- One-off Red ledge hops: game collision/step timing is untouched.
    -- Native Player/NPC.hopStep owns the two-cell ledge movement.
    -- The pre-existing GLB Red jump frames supply the visual replacement.
    if context and context.isPlayer and context.isLedgeJump
        and not context.surfing and not context.cycling
        and not context.fishing and character.base=="red" then
        local elapsed=tonumber(context.jumpProgress) or 0
        local frames=tonumber(context.jumpFrames) or 16
        local p=math.max(0,math.min(1,elapsed/math.max(1,frames)))
        local frameNumber=math.max(0,math.min(11,math.floor(p*11+0.5)))
        local base=string.format("custom_red_jump_%02d_rest.bin",frameNumber)
        local shade,poly=Registry.getStyle()
        return {asset={mesh="assets/render/"..base,
            texture="assets/textures/custom_red_flyride.png",
            paletteMode="direct",shading=shade,poly=poly},
            facing=facing,mirror=mirror,idle_animation=false}
    end

    -- Use the renderer's measured entity motion as the primary 3D walk
    -- signal. Gen1 sprite frames can temporarily look "idle" mid-step;
    -- that must not restart the GLB Walking animation.
    local freeRunMotion = context and context.isPlayer
        and type(Registry.shouldPlayerRun)=="function"
        and Registry.shouldPlayerRun(context)
    if context and (context.isMoving or freeRunMotion) and character.type~="static" then
        -- Only the live player may sprint. NPCs keep their original Walking
        -- clip; Surf, Bike, Fishing and Fly were dispatched earlier.
        -- Only the live Red player uses the authored Running GLB clip.
        -- v50: normal grid run and free-roam camera running both use the
        -- authored Red Running clip. NPCs retain original step timing.
        local locomotion="walk"
        if context and context.isPlayer and type(Registry.shouldPlayerRun)=="function" then
            local ok,run=pcall(Registry.shouldPlayerRun,context)
            if ok and run==true then locomotion="run" end
        end
        return {
            asset=buildAsset(character.base,locomotion),
            facing=facing,
            mirror=mirror
        }
    end

    ----------------------------------------------------------------
    -- CHARACTER IDLE
    --
    -- Gen1:
    --
    -- frame 0 = down
    -- frame 1 = up
    -- frame 2 = side
    ----------------------------------------------------------------

    if frame == 0
        or frame == 1
        or frame == 2 then

        return {

            asset =
                buildAsset(
                    character.base,
                    "idle"
                ),

            facing =
                facing,

            mirror =
                mirror
        }

    end


    ----------------------------------------------------------------
    -- CHARACTER WALK
    --
    -- Gen1:
    --
    -- frame 3 = down walk
    -- frame 4 = up walk
    -- frame 5 = side walk
    ----------------------------------------------------------------

    if frame == 3
        or frame == 4
        or frame == 5 then

        return {

            asset =
                buildAsset(
                    character.base,
                    "walk"
                ),

            facing =
                facing,

            mirror =
                mirror
        }

    end


    ----------------------------------------------------------------
    -- Unsupported frame
    ----------------------------------------------------------------

    return nil
end


return Registry
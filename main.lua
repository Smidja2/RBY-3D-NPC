local mod = ...
-- NPC / decorative Pokemon replacements use an external VOXEL renderer.
-- HM Fly alone is drawn independently by this mod using the game HUD hook.
-- Does not install, configure, or replace any world/voxel pipeline.

----------------------------------------------------------------
-- Active game version
----------------------------------------------------------------

local GameVersion =
    require(
        "src.core.GameVersion"
    )


----------------------------------------------------------------
-- Load a Lua file belonging to this mod.
----------------------------------------------------------------

local function loadLocalModule(
    path,
    ...
)

    local src, err =
        mod:read(path)

    if not src then
        mod.log:error(
            "Could not read local module %s: %s",
            path,
            tostring(err)
        )
        return nil
    end


    local loader =
        loadstring or load


    local chunk, loadErr =
        loader(
            src,
            "@" .. mod.path .. "/" .. path
        )


    if not chunk then
        mod.log:error(
            "Could not load local module %s: %s",
            path,
            tostring(loadErr)
        )
        return nil
    end


    local ok, result =
        pcall(
            chunk,
            ...
        )


    if not ok then
        mod.log:error(
            "Error executing local module %s: %s",
            path,
            tostring(result)
        )
        return nil
    end


    return result
end


----------------------------------------------------------------
-- Configure Porygonal version identity
----------------------------------------------------------------

local Version =
    loadLocalModule(
        "game_version_profile.lua"
    )

if not Version then
    return
end


local gameVersion =
    GameVersion.get()


local versionGroup =
    nil


if gameVersion == "red"
    or gameVersion == "blue" then

    versionGroup =
        Version.RED_BLUE

elseif gameVersion == "yellow" then

    versionGroup =
        Version.YELLOW

else

    mod.log:error(
        "Unsupported Porygonal game version: %s",
        tostring(gameVersion)
    )

    return
end


Version.configure(
    versionGroup
)


----------------------------------------------------------------
-- Load persistent attributes tuning
----------------------------------------------------------------

local Tuning =
    loadLocalModule(
        "character_tuning.lua"
    )

if not Tuning then
    return
end


----------------------------------------------------------------
-- Load Character Core
--
-- Registry receives Tuning as an injected dependency.
-- This keeps all mod-local file loading centralized in main.lua.
----------------------------------------------------------------

-- Persistent, independent graphic options in the mod manager.
-- The only user-adjustable controls in this standalone sprite replacement.
-- Occluded sprite silhouettes are always hidden for successfully replaced
-- actors, while any unmapped actor remains handled by the host renderer.
-- Asset caching stays map-scoped and walk animation speed stays 1.00X.
mod.options:define({
    {key="render_style", type="choice", label="3D CHARACTER SHADING", default="n64",
     choices={{"N64", "n64"}, {"TOON SHADING", "toon"},
              {"TOON CEL SHADING", "toon_cel"}, {"SMOOTH SHADING", "smooth"},
              {"LOW POLY SHADING", "low_poly"}},
     help="Character-only shading. Does not change the voxel/world renderer, textures, or model geometry."},
    {key="player_model_scale", type="choice", label="PLAYER SIZE", default="1.0",
     choices={{"ORIGINAL 1.0X","1.0"}, {"1.1X","1.1"}, {"1.2X","1.2"}, {"1.3X","1.3"}, {"1.4X","1.4"}, {"1.5X","1.5"}, {"1.6X","1.6"}, {"1.7X","1.7"}, {"1.8X","1.8"}, {"1.9X","1.9"}, {"2.0X","2.0"}},
     help="Scale Red independently, including walking, cycling, surfing and fishing (visual only)."},
    {key="npc_model_scale", type="choice", label="NPC SIZE", default="1.0",
     choices={{"ORIGINAL 1.0X","1.0"}, {"1.1X","1.1"}, {"1.2X","1.2"}, {"1.3X","1.3"}, {"1.4X","1.4"}, {"1.5X","1.5"}, {"1.6X","1.6"}, {"1.7X","1.7"}, {"1.8X","1.8"}, {"1.9X","1.9"}, {"2.0X","2.0"}},
     help="Scale NPCs and decorative Pokemon independently of the player (visual only)."},
    {key="npc_draw_distance", type="choice", label="RENDER VIEW RANGE", default="12",
     choices={{"8 CELLS","8"},{"12 CELLS","12"},{"16 CELLS","16"},{"24 CELLS","24"},{"UNLIMITED","off"}},
     help="NPC/decorative Pokemon draw radius in cells; map events and gameplay continue normally."}
})

local Decisions=loadLocalModule("npc_decisions.lua")
local AnimationCatalog=loadLocalModule("assets/animation_catalog.lua")
assert(AnimationCatalog, "NPC animation catalog is missing")
-- Source-tile-approved indoor chair occupants.  No generic STAY inference.
local SeatedNPCs = loadLocalModule("seated_npcs.lua")
local Registry = loadLocalModule("character_registry.lua",Tuning,Version,Decisions,AnimationCatalog,SeatedNPCs)

if not Registry then
    return
end

-- v50: HOLD Shift in normal grid movement and Dramaless/Dramatic free roam.
-- Running GLB on the player only; never speed NPCs or own a world renderer.
local PlayerShiftRun = loadLocalModule("player_shift_run.lua")
if PlayerShiftRun and type(PlayerShiftRun.install)=="function" then
    local ok,installed=pcall(PlayerShiftRun.install,mod)
    if not ok or not installed then
        mod.log:warn("Player Shift run hook unavailable: %s", tostring(installed))
    end
end
Registry.shouldPlayerRun=function(ctx)
    return PlayerShiftRun and type(PlayerShiftRun.isRunning)=="function"
        and PlayerShiftRun.isRunning(ctx) or false
end

-- Runtime animation sampler only. Never touches gameplay movement.speed or map physics.
Registry.walkAnimationSpeed=function()
    return 1.0 -- normal playback speed; no separate user option
end

Registry.getStyle=function()
    -- One mutually exclusive setting. No old SHADING/POLY combinations
    -- that accidentally keep the arms and models in the wrong style.
    local style=mod.options:get("render_style") or "n64"
    if style=="toon" then return "toon_outline", "smooth" end
    if style=="toon_cel" then return "toon", "smooth" end
    if style=="smooth" then return "smooth_lit", "smooth" end
    if style=="low_poly" then return "low_poly", "low" end
    return "n64", "low"
end

-- Player inactivity is based on actual Game Boy input, not keyboard alone.
-- The engine unifies keyboard, gamepad and touch in src.core.Input.
local gameInput=nil
local inputOK,inputModule=pcall(require,"src.core.Input")
if inputOK and type(inputModule)=="table" then gameInput=inputModule end
local gameButtons={"up","down","left","right","a","b","start","select","l","r"}
Registry.isGameplayButtonDown=function()
    if gameInput and type(gameInput.isDown)=="function" then
        local available=false
        for _,btn in ipairs(gameButtons) do
            local ok,down=pcall(gameInput.isDown,gameInput,btn)
            if ok then
                available=true
                if down then return true end
            end
            if type(gameInput.wasPressed)=="function" then
                local pressedOK,pressed=pcall(gameInput.wasPressed,gameInput,btn)
                if pressedOK and pressed then return true end
            end
        end
        if available then return false end
    end
    -- Defensive fallback for older builds without the unified Input API.
    if love and love.keyboard and type(love.keyboard.isDown)=="function" then
        local keys={"up","down","left","right","w","a","s","d",
             "z","x","return","space","backspace","escape","tab",
             "lshift","rshift","q","e","lctrl","rctrl"}
        for _,key in ipairs(keys) do
            local ok,pressed=pcall(love.keyboard.isDown,key)
            if ok and pressed then return true end
        end
        return false
    end
    return nil
end



----------------------------------------------------------------
-- Initialize renderer-independent character runtime
----------------------------------------------------------------

local CharacterRuntimeModule =
    loadLocalModule(
        "character_runtime.lua"
    )

if not CharacterRuntimeModule
    or type(CharacterRuntimeModule.create)
        ~= "function" then

    mod.log:error(
        "Porygonal character_runtime.lua could not be loaded"
    )

    return
end


local CharacterRuntime =
    CharacterRuntimeModule.create(
        mod,
        loadLocalModule,
        Version.group()
    )

if not CharacterRuntime then

    mod.log:error(
        "Porygonal character runtime could not be initialized"
    )

    return
end


----------------------------------------------------------------
-- Load renderer manager
----------------------------------------------------------------

local RendererManager =
    loadLocalModule(
        "renderers/renderer_manager.lua"
    )


if not RendererManager then
    return
end


----------------------------------------------------------------
-- Attach to an EXTERNAL voxel renderer after mod load completes.
-- The previous single startup attempt ran before renderer exports were ready,
-- so the addon silently showed only native sprites for some load orders.
-- This module never registers a world/voxel pipeline or changes voxel options.
----------------------------------------------------------------
local attached = false
local attaching = false
local attachFailureLogged = false

-- RUMBLE V57: use the renderer-owned 3D cinematic, not a fixed-size
-- render.hud overlay. The HUD implementation caused Fly to change size
-- independently of Dramaless's world camera, broke the mount/saddle scale,
-- and competed with the host renderer's native Fly effects.
-- Dramaless, Potato, Dramatic and Battle Art already implement the authored
-- world-space Pidgeot + Red Fly. Let the adapter own it end-to-end.
-- This also restores the native bird sprite automatically if no compatible
-- 3D renderer can draw the replacement, avoiding an invisible HM move.
Registry.standaloneFlyOwnsFly = false
Registry.standaloneFlyActive = function() return false end
Registry.standaloneFlyPresenting = function() return false end

local function attachToRenderer(source)
    if attached or attaching then return attached end
    attaching = true
    local ok, result = pcall(RendererManager.initialize, mod,
        loadLocalModule, Registry, CharacterRuntime)
    attaching = false
    if not ok then
        mod.log:warn("Character-only adapter attach (%s) failed: %s",
            tostring(source), tostring(result))
        return false
    end
    if not result then return false end
    attached = true
    mod.log:info("NPC sprite-to-GLB active via %s (attached at %s)",
        tostring(RendererManager.active and RendererManager.active.name),
        tostring(source))
    return true
end

-- If renderer exports already exist, attach immediately.
attachToRenderer("initial load")

-- Otherwise retry AFTER all external renderer mods expose their libraries.
-- These are lifecycle events, not game graphics hooks.
if mod.events and type(mod.events.on)=="function" then
    mod.events:on("mods.loaded", function()
        attachToRenderer("mods.loaded")
    end)
    mod.events:on("game.ready", function()
        if not attachToRenderer("game.ready") and not attachFailureLogged then
            attachFailureLogged=true
            mod.log:warn("NPC GLB addon did not find an initialized supported voxel renderer. "..
                "Install and enable Potato, Dramaless, Dramatic, or Battle Art Voxel; "..
                "leave world rendering with that mod.")
        end
    end)
end

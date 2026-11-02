local function originalHmFlyActive(state)
    if type(state)~="table" then return false end
    -- Gen1Recomp stores Fly phases on the OverworldState; some external
    -- renderers pass its wrapper rather than the exact overworld object.
    local world=state
    if not (state.flyAnim or state.flyArrive or state.flyFade) then
        if type(state.overworld)=="table" then world=state.overworld
        elseif type(state.game)=="table"
            and type(state.game.overworld)=="table" then
            world=state.game.overworld
        end
    end
    if world.flyFade or world.flyArrive then return true end
    local anim=world.flyAnim
    if type(anim)~="table" then return false end
    return anim.phase~=nil and anim.phase~="done" and anim.phase~="idle"
end

local DramalessShapeAdapter = {}

DramalessShapeAdapter.info = {
    adapterVersion = "1.0.0",

    targetMod = {
        id = "DRAMALESS_SHAPE",
        name = "Dramaless Shape",
        validatedVersion = "2.0.3",
    },
}

----------------------------------------------------------------
-- Porygonal - Dramaless Shape renderer adapter
--
-- Compatibility adapter for DRAMALESS_SHAPE 2.0.3.
--
-- Dramaless Shape retains the core VoxelScene / Voxel3D /
-- SpriteBillboards / ShadowMap / FirstPerson surfaces used by the
-- validated Dramatic Shape adapter. This adapter intentionally starts
-- from that proven integration strategy rather than using the Voxel
-- Companion API, because Companion API v1 is additive and does not
-- provide ownership/replacement of the host's ordinary actor pass.
--
-- Runtime-validated integration; see DRAMALESS_SHAPE_README.txt for tested scope.
----------------------------------------------------------------


----------------------------------------------------------------
-- Detect Dramaless Shape
--
-- Detection only.
-- No hooks or runtime modifications are installed here.
----------------------------------------------------------------

function DramalessShapeAdapter.detect(
    mod
)

    local ds = mod.find("DRAMALESS_SHAPE")


    if not ds then
        return false
    end


    if not (
        ds.exports
        and ds.exports.lib
    ) then

        return false
    end


    return true
end


function DramalessShapeAdapter.initialize(
    mod,
    loadLocalModule,
    Registry,
    CharacterRuntime
)

    ----------------------------------------------------------------
    -- Find Dramaless Shape
    ----------------------------------------------------------------

    local ds = mod.find("DRAMALESS_SHAPE")


    if not ds then

        mod.log:info(
            "Dramaless Shape not installed"
        )

        return false
    end


    if not (
        ds.exports
        and ds.exports.lib
    ) then

        mod.log:error(
            "Dramaless Shape API unavailable"
        )

        return false
    end


    ----------------------------------------------------------------
    -- Dramaless Shape modules
    ----------------------------------------------------------------

    local V =
        ds.exports.lib


    local VoxelScene =
        V.require("VoxelScene")


    local Voxel3D =
        V.require("Voxel3D")


    local Mat4 =
        V.require("Mat4")


    local FirstPerson =
        V.require("FirstPerson")


    local SpriteBillboards =
        V.require("SpriteBillboards")


    local ShadowMap =
        V.require("ShadowMap")


    local ChunkMesher =
        V.require("ChunkMesher")

    -- Dramaless Shape v6 ships its own baked RED model, independent of
    -- SpriteBillboards. Hand the player back to the normal character draw
    -- path so the Porygonal GLB (including Surf/Bike/Fish) can replace it.
    -- VoxelScene draws the sprite path when PlayerModel.draw returns false.
    local playerModelOk, PlayerModel = pcall(V.require,"PlayerModel")
    if not playerModelOk then PlayerModel = nil end



    ----------------------------------------------------------------
    -- Gen1Recomp modules
    ----------------------------------------------------------------


    local PaletteFX =
        require(
            "src.render.PaletteFX"
        )

    -- Read live save state (onBike), not just the player sprite artwork.
    -- Gen1Recomp can display the same logical SPRITE_RED on and off a bike.
    local CoreGame = require("src.core.Game")


    ----------------------------------------------------------------
    -- Porygonal character runtime
    --
    -- The runtime interprets character assets into renderer-agnostic
    -- packages (geometry + ImageData + Gen1 pose semantics).
    --
    -- This renderer alone converts those packages into Dramaless Shape
    -- GPU resources.
    ----------------------------------------------------------------

    
    if not CharacterRuntime
        or type(CharacterRuntime.loadAsset) ~= "function"
        or type(CharacterRuntime.textureDataFor) ~= "function"
        or type(CharacterRuntime.getSpritePose) ~= "function" then

        mod.log:error(
            "Porygonal character runtime unavailable"
        )

        return false
    end


    ----------------------------------------------------------------
    -- Performance and size options. Changes are applied to the drawing
    -- transform, never to the authored RED-relative mesh or animation data.
    -- These settings affect the Dramaless NPC renderer only.
    ----------------------------------------------------------------
    local function safeOption(key, fallback)
        if mod.options and type(mod.options.get) == "function" then
            local ok, result = pcall(mod.options.get, mod.options, key)
            if ok and result ~= nil then return result end
        end
        return fallback
    end

    -- The mod options expose independent RED/NPC scales from 1.0 to 2.0,
    -- in 0.1 steps. Read live so changes take effect without reloading maps.
    local function selectedScale(key)
        local v = tonumber(safeOption(key, "1.0")) or 1
        v = math.max(1.0, math.min(2.0, v))
        return math.floor(v * 10 + 0.5) / 10
    end

    local function selectedNpcScale()
        return selectedScale("npc_model_scale")
    end

    local function selectedPlayerScale()
        return selectedScale("player_model_scale")
    end

    local function maxNpcDistanceSquared()
        local tiles = tonumber(safeOption("npc_draw_distance", "12"))
        if not tiles or tiles <= 0 then return nil end
        local units = tiles * 16 -- the Gen1 engine uses 16 world units per map cell
        return units * units
    end

    local function npcBeyondRange(ctx, px, py)
        if not ctx or not ctx.npcMaxDistanceSquared
           or type(ctx.playerPx) ~= "number"
           or type(ctx.playerPy) ~= "number"
           or type(px) ~= "number" or type(py) ~= "number" then
            return false
        end
        local dx, dz = px-ctx.playerPx, py-ctx.playerPy
        return (dx*dx + dz*dz) > ctx.npcMaxDistanceSquared
    end

    local function billboardBeyondRange(ctx, model)
        -- Recover only the character billboard's original world position.
        -- Not used on geometry, terrain, buildings, figures or FX.
        if type(model) ~= "table"
           or type(model[1]) ~= "number" or type(model[4]) ~= "number"
           or type(model[9]) ~= "number" or type(model[12]) ~= "number" then
            return false
        end
        local px = model[4] - 8 + 8 * model[1]
        local py = model[12] - 8 + 8 * model[9]
        return npcBeyondRange(ctx, px, py)
    end

    local function enlargeNpcDrawModel(model, isPlayer, ctx)
        if not model then return model end
        local amount
        if isPlayer then
            amount = ctx and ctx.playerScale or selectedPlayerScale()
        else
            amount = ctx and ctx.npcScale or selectedNpcScale()
        end
        if amount == 1 then return model end
        -- Multiplying on the right scales locally around the GLB's origin.
        -- It does not displace the feet or scale the world position.
        return Mat4.mul(model, Mat4.scale(amount, amount, amount))
    end

    ----------------------------------------------------------------
    -- Dramaless Shape GPU resource cache
    --
    -- Renderer-agnostic data stays in character_runtime.lua.
    -- Voxel3D meshes and Love2D Images stay here.
    ----------------------------------------------------------------

    local gpuAssetCache =
        setmetatable(
            {},
            {
                __mode = "k"
            }
        )


    -- Character-only toon silhouettes; renderer/world code is not modified.
    local ToonOutline = loadLocalModule("toon_outline.lua")

    local function prepareGpuAsset(
        assetPackage
    )

        if not assetPackage then
            return nil
        end


        if gpuAssetCache[assetPackage] then

            return gpuAssetCache[
                assetPackage
            ]
        end


        local mesh =
            Voxel3D.newMesh(
                assetPackage.vertices,
                assetPackage.indices
            )


        if not mesh then
            return nil
        end


        local mirroredMesh =
            Voxel3D.newMesh(
                assetPackage.mirroredVertices,
                assetPackage.mirroredIndices
            )


        if not mirroredMesh then
            return nil
        end


        local gpuAsset = {

            mesh =
                mesh,

            mirroredMesh =
                mirroredMesh,

            textures =
                {}
        }


        gpuAssetCache[assetPackage] =
            gpuAsset


        if ToonOutline and type(ToonOutline.prepare)=="function" then
            ToonOutline.prepare(assetPackage,gpuAsset,Voxel3D)
        end
        return gpuAsset
    end


    ----------------------------------------------------------------
    -- Dramaless Shape / Love2D texture realization
    ----------------------------------------------------------------

    local function textureFor(
        assetPackage,
        gpuAsset,
        sprite,
        colors
    )

        local imageData,
              textureKey =

            CharacterRuntime.textureDataFor(
                assetPackage,
                sprite,
                colors
            )


        if not imageData then
            return nil
        end


        textureKey =
            textureKey
            or "raw"


        if gpuAsset.textures[
            textureKey
        ] then

            return gpuAsset.textures[
                textureKey
            ]
        end


        local image =
            love.graphics.newImage(
                imageData
            )


        image:setFilter(
            assetPackage.rumbleTexture and "nearest" or "linear",
            assetPackage.rumbleTexture and "nearest" or "linear"
        )


        gpuAsset.textures[
            textureKey
        ] =
            image


        return image
    end


    ----------------------------------------------------------------
    -- Load and realize one asset for Dramaless Shape
    ----------------------------------------------------------------

    local function loadAsset(
        definition
    )

        local assetPackage =
            CharacterRuntime.loadAsset(
                definition
            )


        if not assetPackage then
            return nil
        end


        local gpuAsset =
            prepareGpuAsset(
                assetPackage
            )

        if gpuAsset and CharacterRuntime.animateAsset then
            local ok, updated = pcall(CharacterRuntime.animateAsset, definition, assetPackage, gpuAsset)
            if not ok or updated == false then
                mod.log:warn('Original GLB animation update failed for %s',tostring(definition.mesh))
            end
        end


        if not gpuAsset then
            return nil
        end


        return {

            package =
                assetPackage,

            mesh =
                gpuAsset.mesh,

            mirroredMesh =
                gpuAsset.mirroredMesh,

            gpu =
                gpuAsset
        }
    end


    ----------------------------------------------------------------
    -- Renderer-independent Gen1 pose bridge
    ----------------------------------------------------------------

    local function getSpritePose(
        sprite,
        facing,
        phase,
        flip
    )

        return CharacterRuntime.getSpritePose(
            sprite,
            facing,
            phase,
            flip
        )
    end


    ----------------------------------------------------------------
    -- Renderer texture bridge
    ----------------------------------------------------------------

    local function textureForLoadedAsset(
        asset,
        sprite,
        colors
    )

        return textureFor(
            asset.package,
            asset.gpu,
            sprite,
            colors
        )
    end


    ----------------------------------------------------------------
    -- Find private upvalue
    --
    -- Historical helper used only by COMPAT 0.1.83.
    ----------------------------------------------------------------

    local function findUpvalue(
        fn,
        wantedName,
        wantedValue
    )

        if type(fn) ~= "function" then
            return nil
        end


        if not debug
            or not debug.getupvalue then

            return nil
        end


        for i = 1, 96 do

            local name,
                  value =

                debug.getupvalue(
                    fn,
                    i
                )


            if not name then
                break
            end


            if name == wantedName
                or (
                    wantedValue ~= nil
                    and value == wantedValue
                ) then

                return i,
                       value
            end

        end


        return nil
    end


    ----------------------------------------------------------------
    -- COMPATIBILITY PROFILES
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- COMPAT: RECOMP 0.1.99
    --
    -- Integration introduced for Recomp 0.1.99.
    -- Uses observable/public Dramaless Shape module surfaces and 3D
    -- shadow casters. No private-function upvalue hooks are used.
    ----------------------------------------------------------------

    local function installCompat0199()

        local originalVoxelRender =
            VoxelScene.render


        local originalVoxelDraw =
            Voxel3D.draw


        local originalBillboardMesh =
            SpriteBillboards.mesh


        local originalShadowQuad =
            SpriteBillboards.shadowQuad


        local originalShadowDraw =
            ShadowMap.draw


        local originalBeginOverlay =
            Voxel3D.beginOverlay


        local originalEndOverlay =
            Voxel3D.endOverlay


        local originalEndScene =
            Voxel3D.endScene


        ------------------------------------------------------------
        -- Validate every surface needed by the modern profile BEFORE
        -- installing any wrapper. A failed initialization must not leave
        -- partial mutations behind.
        ------------------------------------------------------------

        if type(originalVoxelRender) ~= "function"
            or type(originalVoxelDraw) ~= "function"
            or type(originalBillboardMesh) ~= "function"
            or type(originalShadowQuad) ~= "function"
            or type(originalShadowDraw) ~= "function"
            or type(originalBeginOverlay) ~= "function"
            or type(originalEndOverlay) ~= "function"
            or type(originalEndScene) ~= "function" then

            mod.log:error(
                "Dramaless Shape adapter: modern compatibility surfaces unavailable"
            )

            return false
        end


        ------------------------------------------------------------
        -- PORYGONAL FLY STATE
        --
        -- Visual offsets / trajectory timings are read through Registry
        -- from character_tuning.lua and are not owned by this renderer.
        --
        -- Fly is not a normal Dramaless Shape character pose. Recomp
        -- draws a dedicated 2D bird FX while Dramaless Shape removes
        -- the player from its normal pose list.
        --
        -- Porygonal keeps its own small state machine across the map
        -- transition and renders:
        --
        --   bird_walk + <player>_mount_walk
        --
        -- The original 2D bird image is identified once during the
        -- departure and then suppressed by exact Image identity.
        ------------------------------------------------------------

        local originalLoveDraw =
            love.graphics.draw


        ------------------------------------------------------------
        -- Dramaless composites field FX inside Voxel3D.beginOverlay() /
        -- endOverlay(), after VoxelScene.render has returned.
        --
        -- Keep the latest OverworldState and a narrowly scoped overlay flag
        -- so fishing/Fly filtering only applies during that exact FX pass.
        ------------------------------------------------------------

        local latestWorldState =
            nil


        local fieldFxOverlayActive =
            false


        local FlySpriteGuard = loadLocalModule("fly_sprite_guard.lua")
        local activeFlyWorldState = nil
        local flyState = {

            mode =
                "normal",

            startedAt =
                0,

            landingAt =
                0,

            startMap =
                nil,

            startPx =
                0,

            startPy =
                0,

            startGround =
                0,

            targetPx =
                0,

            targetPy =
                0,

            targetGround =
                0,

            playerSprite =
                nil,

            colors =
                nil,

            birdImage =
                nil,

            captureBird =
                false
        }


        ------------------------------------------------------------
        -- Fly trajectory is authored in Registry.fly_animation.
        -- The renderer only interprets those world-space parameters.
        ------------------------------------------------------------

        local function flyAnimationConfig()

            return Registry.fly_animation
                or {}
        end


        ------------------------------------------------------------
        -- Native Fly alternates its two visible bird frames roughly
        -- every 0.05 s. Use the same cadence to switch the authored
        -- idle/walk meshes for both mount and rider.
        ------------------------------------------------------------

        local FLY_POSE_STEP =
            0.05


        local function flyNowSeconds()

            if love.timer
                and love.timer.getTime then

                local ok,
                      t =
                    pcall(
                        love.timer.getTime
                    )


                if ok
                    and type(t)
                        == "number" then

                    return t
                end
            end


            return 0
        end


        local function flyObjectLike(value)

            local t =
                type(value)


            return t == "userdata"
                or t == "table"
        end


        local function flySafeDimensions(drawable)

            if not flyObjectLike(
                drawable
            ) then

                return nil,
                       nil
            end


            local okMethod,
                  method =
                pcall(
                    function()
                        return drawable.getDimensions
                    end
                )


            if not okMethod
                or type(method)
                    ~= "function" then

                return nil,
                       nil
            end


            local ok,
                  w,
                  h =
                pcall(
                    method,
                    drawable
                )


            if ok then
                return w,
                       h
            end


            return nil,
                   nil
        end


        local function flySafeViewport(quad)

            if not flyObjectLike(
                quad
            ) then

                return nil,
                       nil,
                       nil,
                       nil
            end


            local okMethod,
                  method =
                pcall(
                    function()
                        return quad.getViewport
                    end
                )


            if not okMethod
                or type(method)
                    ~= "function" then

                return nil,
                       nil,
                       nil,
                       nil
            end


            local ok,
                  x,
                  y,
                  w,
                  h =
                pcall(
                    method,
                    quad
                )


            if ok then
                return x,
                       y,
                       w,
                       h
            end


            return nil,
                   nil,
                   nil,
                   nil
        end


        ----------------------------------------------------------------
        -- Scoped field-FX interception.
        --
        -- Dramaless main.lua calls:
        --
        --     Voxel3D.beginOverlay()
        --     ctx.drawFx(...)
        --     Voxel3D.endOverlay()
        --
        -- We use that renderer-owned semantic boundary instead of filtering
        -- every Love2D draw globally.
        ----------------------------------------------------------------

        -- Only intercept field FX while the host renderer's overlay is open.
        -- A persistent love.graphics.draw replacement can poison unrelated
        -- world/UI rendering after Fly transitions or an FX exception.
        local overlayOriginalDraw = nil
        local overlayDrawWrapper = nil
        local renderedCustomFly = false
        local lastFlyVisibleDrawn = false
        -- The native overworld fishing action is often a table, not a boolean.
        -- The 3D fishing pose is registered while this action is active;
        -- only then can the native rod field effect be suppressed safely.
        local lastFishingGlbDrawn = false

        local function restoreFxDraw()
            if fieldFxOverlayActive and FlySpriteGuard and type(FlySpriteGuard.endFx)=="function" then
                FlySpriteGuard.endFx()
            end
            fieldFxOverlayActive = false
            if overlayOriginalDraw then
                if love.graphics.draw == overlayDrawWrapper then
                    love.graphics.draw = overlayOriginalDraw
                end
                overlayOriginalDraw = nil
                overlayDrawWrapper = nil
            end
        end

        -- v34: Reproduce the working Dramaless v8.4 HM Fly suppression
        -- at the actual field-FX boundary. Dramaless drawWorld does:
        --     if Voxel3D.beginOverlay() then ctx.drawFx(...); Voxel3D.endOverlay() end
        -- Returning false prevents the ENTIRE Fly-only field-FX overlay,
        -- including fxBird(), BEFORE its native sprite can be submitted.
        -- Keep native effects if Pidgeot/Red did not successfully render.
        local nativeFlyFxSkipLogged = false
        Voxel3D.beginOverlay = function(...)
            restoreFxDraw()
            -- Red's fishing rod is already part of the 3D GLB. Gen1Recomp
            -- renders another fishing animation in the native field-FX pass.
            -- Once the 3D model was actually submitted, skip that native pass
            -- rather than relying on state.rodImg, which does not identify
            -- every native fishing drawable on all engine versions.
            -- No GLB draw -> keep the original effect as a safe fallback.
            if lastFishingGlbDrawn then
                return false
            end
            local customOn = true -- 3D Fly always enabled; no menu toggle
            local flyingNow = latestWorldState and FlySpriteGuard
                and type(FlySpriteGuard.isNativeFly)=="function"
                and FlySpriteGuard.isNativeFly(latestWorldState)
            if customOn and lastFlyVisibleDrawn and flyingNow then
                if not nativeFlyFxSkipLogged and mod.log then
                    nativeFlyFxSkipLogged = true
                    mod.log:info("NPC Fly v34: custom GLBs drawn; skipping native Fly field-FX overlay (Dramaless v8.4 method)")
                end
                return false
            end
            if not flyingNow then nativeFlyFxSkipLogged = false end
            local result = originalBeginOverlay(...)
            fieldFxOverlayActive = result ~= false
            if fieldFxOverlayActive and lastFlyVisibleDrawn
                and FlySpriteGuard and type(FlySpriteGuard.beginFx)=="function" then
                FlySpriteGuard.beginFx(latestWorldState)
            end
            if fieldFxOverlayActive and type(love.graphics.draw) == "function" then
                overlayOriginalDraw = love.graphics.draw
                local baseDraw = overlayOriginalDraw
                overlayDrawWrapper = function(drawable, ...)
                    local state = latestWorldState
                    if state and state.fishing and state.rodImg
                        and drawable == state.rodImg then
                        return
                    end
                    -- Exact Fly field image identity when the engine draws
                    -- directly through love.graphics.draw rather than SpriteRenderer.
                    if FlySpriteGuard and type(FlySpriteGuard.hideImage)=="function"
                        and FlySpriteGuard.hideImage(drawable) then return end
                    return baseDraw(drawable, ...)
                end
                love.graphics.draw = overlayDrawWrapper
            end
            return result
        end

        Voxel3D.endOverlay = function(...)
            local ok, a, b, c = pcall(originalEndOverlay, ...)
            restoreFxDraw()
            if not ok then error(a) end
            return a, b, c
        end

        ----------------------------------------------------------------
        -- Billboard identity
        --
        -- SpriteBillboards caches one GPU mesh for:
        --
        --     def.image .. "#" .. frame
        --
        -- Remember which meshes are character billboards and which sprite
        -- definition/frame produced them.
        ----------------------------------------------------------------

        -- V57: Dramaless's ghost pass (behind buildings/trees) uses the
        -- native sprite's shadowQuad independently of its solid character
        -- and cast-shadow passes. Scope our replacement strictly to that
        -- pass; never confuse it with sunlight shadows or normal billboards.
        local insideOcclusionPass = false
        local originalBeginGhost = Voxel3D.beginGhost
        local originalEndGhost = Voxel3D.endGhost
        if type(originalBeginGhost) == "function"
            and type(originalEndGhost) == "function" then
            Voxel3D.beginGhost = function(...)
                local result = originalBeginGhost(...)
                insideOcclusionPass = true
                return result
            end
            Voxel3D.endGhost = function(...)
                insideOcclusionPass = false
                return originalEndGhost(...)
            end
        end

        local billboardInfo =
            setmetatable(
                {},
                {
                    __mode = "k"
                }
            )


        ----------------------------------------------------------------
        -- Current VoxelScene.render context
        ----------------------------------------------------------------

        local renderContext =
            nil

        ------------------------------------------------------------
        -- Dramaless Adjustable Waves v6 player-model compatibility.
        --
        -- VoxelScene.drawCast first calls PlayerModel.draw(p), whose
        -- baked RED geometry bypasses our SpriteBillboards / Voxel3D
        -- character replacement hooks. Returning false *only during
        -- the active Porygonal render pass* routes the native player
        -- back through drawEntity (and SpriteBillboards.mesh) where
        -- red_surf / red_cycling / red_fishing are actually selected.
        --
        -- Preserve Dramaless water heights, rider wave following,
        -- camera, terrain, and actor logic. If a replacement asset
        -- fails, drawEntity can still show the native 2D sprite.
        -- Also hand the shadow pass to Porygonal to prevent a second
        -- baked RED shadow on top of the rider and mount.
        ------------------------------------------------------------
        if PlayerModel and type(PlayerModel.draw) == "function" then
            local originalPlayerModelDraw = PlayerModel.draw
            PlayerModel.draw = function(p)
                if renderContext and p and p.isPlayer == true then
                    return false
                end
                return originalPlayerModelDraw(p)
            end
        end

        if PlayerModel and type(PlayerModel.drawShadow) == "function" then
            local originalPlayerModelDrawShadow = PlayerModel.drawShadow
            PlayerModel.drawShadow = function(p, shadowMap)
                if renderContext and p and p.isPlayer == true then
                    return false
                end
                return originalPlayerModelDrawShadow(p, shadowMap)
            end
        end


        ----------------------------------------------------------------
        -- Per-entity motion history for procedural idle.
        --
        -- Do not rely on entity.progress / entity.moving here: some entity
        -- implementations keep those flags/values after a completed step.
        -- We compare actual world position from one captured pose to the next.
        ----------------------------------------------------------------

        local idleMotionHistory =
            {}


        ----------------------------------------------------------------
        -- World yaw
        ----------------------------------------------------------------

        local function facingToYaw(
            facing,
            isPlayer
        )

            ------------------------------------------------------------
            -- Player + Dramaless Shape free camera:
            -- use the continuous body orientation.
            ------------------------------------------------------------

            if isPlayer
                and FirstPerson
                and FirstPerson.engaged
                and FirstPerson.engaged()
                and FirstPerson.bodyYaw ~= nil then

                return FirstPerson.bodyYaw
            end


            ------------------------------------------------------------
            -- Normal world-space facing.
            ------------------------------------------------------------

            if facing == "down" then
                return 0
            end


            if facing == "left" then
                return math.rad(-90)
            end


            if facing == "up" then
                return math.rad(180)
            end


            if facing == "right" then
                return math.rad(90)
            end


            return 0
        end


        ----------------------------------------------------------------
        -- Palette supplied to a character standing on `map`.
        ----------------------------------------------------------------

        local function colorsForMap(
            paletteFor,
            map
        )

            if PaletteFX.usesGbcPack() then
                return nil
            end


            if VoxelScene._modeColors then

                return VoxelScene._modeColors(
                    paletteFor,
                    map
                )
            end


            if paletteFor then
                return paletteFor(map)
            end


            return nil
        end


        ----------------------------------------------------------------
        -- Palette for authored character FIGURES.
        --
        -- Normal GBC sprites use PaletteFX.spriteObp(realSpriteDef, seed),
        -- but an authored FIGURE has no real Sprite object. A fabricated
        -- minimal sprite def is insufficient for the OBP resolver and falls
        -- back to the raw grey Porygonal texture.
        --
        -- For these map-authored figures, use the map's EFFECTIVE palette
        -- directly. This keeps GRAY/CLASSIC/INVERTED/GBC modes consistent
        -- with the active scene instead of leaving the model uncolored.
        ----------------------------------------------------------------

        local function colorsForAuthoredFigure(
            paletteFor,
            map,
            state
        )

            if PaletteFX.usesGbcPack()
                and state
                and state.player
                and state.player.sprite
                and state.player.sprite.def then

                local playerColors =
                    PaletteFX.spriteObp(
                        state.player.sprite.def,
                        state.player.sprite.seed
                    )


                if playerColors then
                    return playerColors
                end
            end


            if VoxelScene._modeColors then

                local colors =
                    VoxelScene._modeColors(
                        paletteFor,
                        map
                    )


                if colors then
                    return colors
                end
            end


            if paletteFor then
                return paletteFor(map)
            end


            return nil
        end


        ----------------------------------------------------------------
        -- Temporarily observe one entity's existing pose() call.
        --
        -- IMPORTANT: we never call pose() ourselves.
        ----------------------------------------------------------------

    -- v9: only lower swimmer models while their actual movement cell is WATER.
    -- This checks the game's collision tile (not a map-name guess), so
    -- characters standing on the adjacent jetty/shore remain on dry ground.
    local function swimmerWaterCell(map, cellX, cellY)
        if type(map) == "table" and type(map.isWaterCell) == "function"
            and type(cellX) == "number" and type(cellY) == "number" then
            local ok, water = pcall(map.isWaterCell, map, cellX, cellY)
            if ok then return water == true end
        end
        if type(map) ~= "table" or type(map.waterTiles) ~= "table"
            or type(map.cellTile) ~= "function"
            or type(cellX) ~= "number" or type(cellY) ~= "number" then
            return false
        end
        if type(map.inBounds) == "function" then
            local ok, within = pcall(map.inBounds, map, cellX, cellY)
            if not ok or not within then return false end
        end
        local ok, tile = pcall(map.cellTile, map, cellX, cellY)
        if not ok or tile == nil then return false end
        local flag = map.waterTiles[tile]
        return flag ~= nil and flag ~= false
    end

    local function swimmerWaterOffset(p, replacement)
        if not p or not p.onWaterCell or p.isPlayer then return 0 end
        local asset = replacement and replacement.asset
        local path = asset and asset.mesh
        if type(path) ~= "string" then return 0 end
        if path == "assets/render/swimmer_submerged_m_rest.bin"
            or path == "assets/render/swimmer_submerged_f_rest.bin" then return 0 end
        if path == "assets/render/swimmer_m_rest.bin" then return -9.0 end
        if path == "assets/render/swimmer_f_rest.bin" then return -8.7 end
        return 0
    end

        local function wrapEntityPose(
            entity,
            map,
            offsetX,
            offsetY,
            isPlayer,
            colors,
            restorers,
            alreadyWrapped
        )

            if type(entity) ~= "table"
                or type(entity.pose) ~= "function" then

                return
            end


            if alreadyWrapped[entity] then
                return
            end


            alreadyWrapped[entity] =
                true


            local originalPose =
                entity.pose


            local hadOwnPose =
                rawget(
                    entity,
                    "pose"
                ) ~= nil


            local ownPose =
                rawget(
                    entity,
                    "pose"
                )


            entity.pose =
                function(self, ...)

                    local sprite,
                          vx,
                          vy,
                          facing,
                          phase,
                          flip =

                        originalPose(
                            self,
                            ...
                        )


                    local ctx =
                        renderContext


                    if ctx
                        and sprite then

                        local basePy =
                            self.py
                            or vy
                            or 0


                        local ground =
                            0


                        if map
                            and VoxelScene.groundAt
                            and self.cellX ~= nil
                            and self.cellY ~= nil then

                            ground =
                                VoxelScene.groundAt(
                                    map,
                                    self.cellX,
                                    self.cellY
                                )
                                or 0
                        end


                        local visualY =
                            vy
                            or basePy


                        ctx.poses[
                            #ctx.poses + 1
                        ] = {

                            sprite =
                                sprite,

                            px =
                                (vx or self.px or 0)
                                + (offsetX or 0),

                            py =
                                basePy
                                + (offsetY or 0),

                            facing =
                                facing,

                            phase =
                                phase,

                            flip =
                                flip,

                            gh =
                                ground,


                            onWaterCell = not isPlayer and swimmerWaterCell(map, self.cellX, self.cellY),

                            lift =
                                basePy
                                - visualY,

                            colors =
                                colors,

                            isPlayer =
                                isPlayer
                                and true
                                or false,

                            fishing =
                                isPlayer and (
                                    self.fishing ~= nil and self.fishing ~= false
                                    or (ctx and ctx.playerFishing == true)
                                ) or false,

                            surfing =
                                isPlayer and (
                                    self.surfing == true
                                    or (ctx and ctx.playerSurfing == true)
                                ) or false,

                            cycling =
                                isPlayer and (
                                    self.onBike == true
                                    or (ctx and ctx.playerCycling == true)
                                ) or false,

                                

                                
                            ------------------------------------------------
                            -- Logical sprite identity of the map entity.
                            --
                            -- Important for Surf: pose() may return SEEL as
                            -- the visual sprite while the entity itself is
                            -- still RED / YELLOW / another player variant.
                            ------------------------------------------------

                            logicalSpriteId =
                                self.def
                                and self.def.id
                                or nil,

                            ------------------------------------------------
                            -- Stable per-entity identity + motion state.
                            -- Used by the procedural idle layer so nearby
                            -- NPCs do not breathe in perfect synchrony.
                            ------------------------------------------------

                            mapId = map and (map.id or map.name or map.key) or nil,
                            cellX = self.cellX,
                            cellY = self.cellY,
                            entityRef = self,

                            objectId = self.id or (self.def and self.def.name) or nil,
                            entityKey =
                                self.id
                                or (
                                    self.def
                                    and self.def.name
                                )
                                or tostring(self),

                            ------------------------------------------------
                            -- Filled just below from actual world-position
                            -- delta, not from sticky movement flags.
                            ------------------------------------------------

                            isLedgeJump = isPlayer and ((self.hopStep ~= nil and self.hopStep ~= false and self.hopStep ~= 0) or self.ledgeJump == true or self.jumping == true or self.hopping == true) or false,

                            jumpProgress = self.progress or self.stepProgress or 0,

                            jumpFrames = self.stepFramesCur or self.stepFrames or 16,

                            isMoving = false
                        }





                    local captured =
                        ctx.poses[
                            #ctx.poses
                        ]

                    
                




                    local motionKey =
                        captured.entityKey


                    local previousMotion =
                        idleMotionHistory[
                            motionKey
                        ]


                    if previousMotion then

                        local dx =
                            captured.px
                            - previousMotion.x


                        local dz =
                            captured.py
                            - previousMotion.z


                        captured.isMoving =
                            (
                                dx * dx
                                + dz * dz
                            )
                            > 0.0001
                    end


                    idleMotionHistory[
                        motionKey
                    ] = {
                        x =
                            captured.px,

                        z =
                            captured.py
                    }
                    end


                    return sprite,
                           vx,
                           vy,
                           facing,
                           phase,
                           flip
                end


            restorers[
                #restorers + 1
            ] =
                function()

                    if hadOwnPose then

                        entity.pose =
                            ownPose

                    else

                        entity.pose =
                            nil
                    end
                end
        end


        ----------------------------------------------------------------
        -- Observe SpriteBillboards.mesh.
        --
        -- This establishes:
        --
        --     GPU mesh -> sprite definition + frame
        ----------------------------------------------------------------

        local function rememberBillboard(
            mesh,
            def,
            frame
        )

            if mesh then

                billboardInfo[mesh] = {

                    def =
                        def,

                    frame =
                        frame
                }
            end


            return mesh
        end


        SpriteBillboards.mesh =
            function(
                def,
                frame
            )

                return rememberBillboard(
                    originalBillboardMesh(
                        def,
                        frame
                    ),
                    def,
                    frame
                )
            end


        ----------------------------------------------------------------
        -- shadowQuad was assigned to the original mesh function when
        -- Dramaless Shape loaded. Wrap it separately so the FIRST shadow
        -- pass of a fresh session is identifiable too.
        ----------------------------------------------------------------

        SpriteBillboards.shadowQuad =
            function(
                def,
                frame
            )

                return rememberBillboard(
                    originalShadowQuad(
                        def,
                        frame
                    ),
                    def,
                    frame
                )
            end


        ----------------------------------------------------------------
        -- Poses that drawCast actually renders.
        ----------------------------------------------------------------

        local function visiblePoses(ctx)

            if ctx.visible then
                return ctx.visible
            end


            local hidePlayer =
                FirstPerson
                and FirstPerson.hidePlayer
                and FirstPerson.hidePlayer()
                or false


            ctx.visible =
                {}


            for _, p in ipairs(
                ctx.poses
            ) do

                if not (
                    (p.isPlayer and hidePlayer)
                    or (not p.isPlayer and npcBeyondRange(ctx, p.px, p.py))
                ) then

                    ctx.visible[
                        #ctx.visible + 1
                    ] =
                        p
                end
            end


            return ctx.visible
        end


        ----------------------------------------------------------------
        -- Dramaless Shape visible-draw -> pose association.
        --
        -- Dramaless 2.0.x applies withinRenderDistance() inside drawCast.
        -- That means not every captured pose produces a visible billboard
        -- draw. A simple sequential draw index can therefore drift and make
        -- the adapter fall back to the original flat cards.
        --
        -- The incoming billboard model matrix contains enough information
        -- to recover the entity's original px/py exactly:
        --
        --   px = model[4]  - 8 + 8 * model[1]
        --   py = model[12] - 8 + 8 * model[9]
        --
        -- Match by BOTH sprite definition and recovered world position.
        -- This also remains stable when the same sprite definition is used
        -- by several NPCs and when drawCast is repeated for water reflection.
        ----------------------------------------------------------------

        local function poseForVisibleBillboard(
            ctx,
            info,
            model
        )

            if not ctx
                or not info
                or type(model) ~= "table" then

                return nil
            end


            local m1 =
                model[1]

            local tx =
                model[4]

            local m9 =
                model[9]

            local tz =
                model[12]


            if type(m1) ~= "number"
                or type(tx) ~= "number"
                or type(m9) ~= "number"
                or type(tz) ~= "number" then

                return nil
            end


            local drawPx =
                tx
                - 8
                + 8 * m1


            local drawPy =
                tz
                - 8
                + 8 * m9


            local best =
                nil

            local bestDistance =
                nil


            for _, p in ipairs(
                visiblePoses(ctx)
            ) do

                if p
                    and p.sprite
                    and p.sprite.def
                    and p.sprite.def == info.def then

                    local dx =
                        (p.px or 0)
                        - drawPx


                    local dz =
                        (p.py or 0)
                        - drawPy


                    local distance =
                        dx * dx
                        + dz * dz


                    if bestDistance == nil
                        or distance < bestDistance then

                        best =
                            p

                        bestDistance =
                            distance
                    end
                end
            end


            ------------------------------------------------------------
            -- A billboard transform recovered from the exact draw should
            -- coincide with its captured pose. Keep a small tolerance for
            -- floating-point camera/yaw arithmetic, otherwise preserve the
            -- renderer's native fallback.
            ------------------------------------------------------------

            if best
                and bestDistance
                and bestDistance <= 0.01 then

                return best
            end

            -- Player-only safety net: a Surf/Bike/Fishing sprite may not
            -- retain the same sprite DEF instance as the captured player
            -- pose in every Gen1Recomp renderer revision. Resolve a real
            -- player draw by both the authoritative entity position AND
            -- one of that player's own SpriteRenderer objects. Do not use
            -- this for NPCs sharing RED/SEEL sprites.
            local active = ctx.livePlayer
            if active and type(active.px) == "number"
                and type(active.py) == "number" then
                local pxDist = drawPx - active.px
                local pyDist = drawPy - active.py
                local nearPlayer = pxDist*pxDist + pyDist*pyDist <= 0.01
                local function sameDef(sprite)
                    return type(sprite) == "table" and sprite.def == info.def
                end
                if nearPlayer and (
                    sameDef(active.sprite)
                    or sameDef(active.surfSprite)
                    or sameDef(active.surfPikachuSprite)
                    or sameDef(active.bikeSprite)
                ) then
                    for _, captured in ipairs(ctx.poses) do
                        if captured.entityRef == active and captured.isPlayer then
                            return captured
                        end
                    end
                end
            end

            return nil
        end


        ----------------------------------------------------------------
        -- Resolve one authored FIGURE replacement.
        --
        -- This path is separate from the normal SpriteBillboards path.
        -- It never changes draw-index/pose association for normal NPCs.
        ----------------------------------------------------------------

        local function applyFigureIdleScale(
            model,
            info
        )

            local cfg =
                Registry.idle_animation
                or {}


            if cfg.enabled == false then
                return model
            end


            local speed =
                cfg.speed
                or 1.15


            local amountY =
                cfg.scale_y
                or 0.012


            local amountXZ =
                cfg.scale_xz
                or 0.003


            local now =
                0


            if love.timer
                and love.timer.getTime then

                local ok,
                      t =
                    pcall(
                        love.timer.getTime
                    )


                if ok
                    and type(t) == "number" then

                    now =
                        t
                end
            end


            ------------------------------------------------------------
            -- Stable ID-only-ish phase for authored figures.
            -- The key is supplied by the renderer (map + semantic role),
            -- so each recurring figure can breathe independently.
            ------------------------------------------------------------

            local key =
                tostring(
                    info.idleKey
                    or "figure"
                )


            local hash =
                17


            for i = 1, #key do

                hash =
                    (
                        hash * 131
                        + string.byte(
                            key,
                            i
                        )
                    )
                    % 104729
            end


            local timeOffset =
                1.0
                + (
                    hash
                    / 104729
                )


            local breath =
                (
                    math.sin(
                        (
                            now
                            + timeOffset
                        )
                        * speed
                        * math.pi
                        * 2
                    )
                    + 1
                )
                * 0.5


            local sy =
                1
                + breath
                * amountY


            local sxz =
                1
                - breath
                * amountXZ


            return Mat4.mul(
                model,
                Mat4.scale(
                    sxz,
                    sy,
                    sxz
                )
            )
        end


        local function replacementDataForFigure(
            info
        )

            if not info
                or not info.replacement
                or not info.replacement.asset then

                return nil
            end


            local asset =
                loadAsset(
                    info.replacement.asset
                )


            if not asset then
                return nil
            end


            local figure =
                info.figure


            local x =
                (figure.wx or 0)
                + (
                    (figure.w or 16)
                    / 2
                )


            local y =
                figure.y
                or 0


            local z =
                figure.wz
                or 0


            local model =
                Mat4.mul(
                    Mat4.translate(
                        x,
                        y,
                        z
                    ),
                    Mat4.rotateY(
                        info.replacement.yaw
                        or 0
                    )
                )


            model =
                applyFigureIdleScale(
                    model,
                    info
                )


            local texture =
                textureForLoadedAsset(
                    asset,
                    info.sprite,
                    info.colors
                )


            if not texture then
                return nil
            end


            return {

                mesh =
                    asset.mesh,

                texture =
                    texture,

                model =
                    model
            }
        end


        ----------------------------------------------------------------
        -- Resolve one Porygonal replacement.
        --
        -- The same geometry/model is used by BOTH the camera pass and
        -- the sun pass. That is essential: the shadow map must contain
        -- the geometry the lit mesh later asks about.
        ----------------------------------------------------------------

        local function idleTimeOffsetForKey(key)

            ------------------------------------------------------------
            -- Stable per-entity idle desynchronization.
            --
            -- IMPORTANT:
            --   * ID ONLY
            --   * world position is deliberately ignored
            --
            -- For common entity IDs ending in a number (obj_1, obj_2...),
            -- use that number directly and scramble it with the golden-ratio
            -- fraction so consecutive IDs land far apart.
            --
            -- The result is a deterministic time offset in [1, 2) seconds.
            ------------------------------------------------------------

            local text =
                tostring(
                    key
                    or ""
                )


            local number =
                tonumber(
                    string.match(
                        text,
                        "(%d+)%D*$"
                    )
                )


            local unit


            if number then

                unit =
                    (
                        number
                        * 0.61803398875
                    )
                    % 1

            else

                local hash =
                    17


                for i = 1, #text do

                    hash =
                        (
                            hash * 131
                            + string.byte(
                                text,
                                i
                            )
                        )
                        % 104729
                end


                unit =
                    hash
                    / 104729
            end


            return
                1.0
                + unit
        end


        local function applyProceduralIdleScale(
            model,
            p,
            replacement
        )
            -- v21: The user-authored GLB idle clips already animate the body.
            -- Do not layer whole-body procedural breathing on an authored clip:
            -- that incorrectly scales head, hair and arms over torso breathing.
            -- This also preserves every original animation track untouched.
            if type(replacement) == "table"
                and type(replacement.asset) == "table"
                and type(replacement.asset.animation) == "table"
                and replacement.asset.animation.clip ~= nil then
                return model
            end

            local cfg =
                Registry.idle_animation
                or {}


            if cfg.enabled == false then
                return model
            end


            ------------------------------------------------------------
            -- Only truly stationary ordinary characters.
            --
            -- Do not breathe:
            --   * while the entity is moving,
            --   * Surf composites,
            --   * Fly composites.
            --
            -- Bike is intentionally allowed here: when stationary it uses
            -- the same subtle idle scale; p.isMoving disables it while riding.
            ------------------------------------------------------------

            if replacement.idle_animation == false
                or p.isMoving
                or replacement.type == "composite"
                or replacement.type == "fly_composite" then

                return model
            end


            local speed =
                cfg.speed
                or 1.15


            local amountY =
                cfg.scale_y
                or 0.012


            local amountXZ =
                cfg.scale_xz
                or 0.003


            local now =
                0


            if love.timer
                and love.timer.getTime then

                local ok,
                      t =
                    pcall(
                        love.timer.getTime
                    )


                if ok
                    and type(t) == "number" then

                    now =
                        t
                end
            end


            local timeOffset =
                idleTimeOffsetForKey(
                    p.entityKey
                )


            ------------------------------------------------------------
            -- 0..1 breathing wave rather than -1..1:
            -- the authored idle mesh remains the minimum-size pose.
            --
            -- Each entity receives a stable 1..2 second offset derived
            -- only from its ID, so nearby characters do not correlate
            -- merely because they stand close together.
            ------------------------------------------------------------

            local breath =
                (
                    math.sin(
                        (
                            now
                            + timeOffset
                        )
                        * speed
                        * math.pi
                        * 2
                    )
                    + 1
                )
                * 0.5


            local sy =
                1
                + breath
                * amountY


            local sxz =
                1
                - breath
                * amountXZ


            ------------------------------------------------------------
            -- Character meshes are authored with their feet at Y=0.
            -- Scaling after translate/rotation therefore keeps the feet
            -- planted while the upper body subtly expands/contracts.
            ------------------------------------------------------------

            return Mat4.mul(
                model,
                Mat4.scale(
                    sxz,
                    sy,
                    sxz
                )
            )
        end


        local lastPlayerVisualReport = nil

        local function replacementDataForPose(p)

            local worldFacing =
                p.facing


            local spriteId,
                  frame,
                  mirror =

                getSpritePose(
                    p.sprite,
                    worldFacing,
                    p.phase,
                    p.flip
                )


            -- Read the authoritative current player entity at the moment
            -- the model is drawn; don't depend solely on pose() flags or
            -- a visual sprite ID (which can change during Surf/Bike).
            local ctx = renderContext
            local live = ctx and ctx.livePlayer
            local isLivePlayer = p.isPlayer == true
                or (live ~= nil and p.entityRef == live)
            local fishing = isLivePlayer and (
                p.fishing == true or (live and live.fishing ~= nil and live.fishing ~= false)
                or (ctx and ctx.playerFishing == true)) or false
            local cycling = isLivePlayer and (
                p.cycling == true or (live and live.onBike == true)
                or (ctx and ctx.playerCycling == true)) or false
            local surfing = isLivePlayer and (
                p.surfing == true or (live and live.surfing == true)
                or (live and p.sprite ~= nil and (
                    p.sprite == live.surfSprite
                    or p.sprite == live.surfPikachuSprite
                )) or (ctx and ctx.playerSurfing == true)) or false

            -- Always derive Surf/Bike/Fishing from the live game state.
            -- No diagnostic model override is exposed or applied.
            if isLivePlayer then
                local report = tostring(surfing)
                    .. ":" .. tostring(cycling) .. ":" .. tostring(fishing)
                    .. ":" .. tostring(spriteId)
                if report ~= lastPlayerVisualReport then
                    lastPlayerVisualReport = report
                    mod.log:info("Player GLB mode: surf=%s bike=%s fish=%s sprite=%s",
                        tostring(surfing), tostring(cycling),
                        tostring(fishing), tostring(spriteId))
                end
            end

            local replacement =
                Registry.lookup(
                    spriteId,
                    frame,
                    mirror,
                    worldFacing,
                    {
                        isPlayer = isLivePlayer,
                        objectId = p.objectId or p.entityKey,
                        entityRef = p.entityRef,
                        entityKey = p.entityKey,
                        isMoving = p.isMoving,
                        isLedgeJump = p.isLedgeJump or (p.entityRef and ((p.entityRef.hopStep ~= nil and p.entityRef.hopStep ~= false and p.entityRef.hopStep ~= 0) or p.entityRef.ledgeJump == true or p.entityRef.jumping == true)),
                        jumpProgress = p.jumpProgress or (p.entityRef and p.entityRef.progress),
                        jumpFrames = p.jumpFrames or (p.entityRef and (p.entityRef.stepFramesCur or p.entityRef.stepFrames)),
                        isRunning = false, -- custom Red Shift Running disabled
                        mapId = p.mapId,
                        cellX = p.cellX,
                        cellY = p.cellY,
                        onWaterCell = p.onWaterCell == true,

                        fishing = fishing,
                        surfing = surfing,
                        cycling = cycling,

                        spriteDef =
                            p.sprite
                            and p.sprite.def
                            or nil,

                        spriteImage =
                            p.sprite
                            and p.sprite.def
                            and p.sprite.def.image
                            or nil
                    }
                )


            if not replacement then
                return nil
            end


            local y =
                (p.gh or 0)
                + (p.lift or 0)

            -- Only water-cell swimmers sink; never lower walking NPCs or player.
            y = y + swimmerWaterOffset(p, replacement)


            local yaw =
                facingToYaw(
                    replacement.facing
                    or worldFacing,
                    p.isPlayer
                )


            local baseModel =
                Mat4.mul(
                    Mat4.translate(
                        p.px + 8,
                        y,
                        p.py + 8
                    ),
                    Mat4.rotateY(
                        yaw
                    )
                )


            baseModel =
                applyProceduralIdleScale(
                    baseModel,
                    p,
                    replacement
                )

            -- Player and NPC size settings are independent.
            -- Applied after idle breathing; preserves authored mesh data.
            baseModel = enlargeNpcDrawModel(baseModel, p.isPlayer, renderContext)


            ------------------------------------------------------------
            -- Composite replacement (currently Surf).
            ------------------------------------------------------------

            if replacement.type == "composite"
                and replacement.parts then

                local floating =
                    replacement.floating_offset
                    or {}


                local rider =
                    replacement.rider_offset
                    or {}


                local mountModel =
                    Mat4.mul(
                        baseModel,
                        Mat4.translate(
                            floating.x or 0,
                            floating.y or 0,
                            floating.z or 0
                        )
                    )


                local riderModel =
                    Mat4.mul(
                        baseModel,
                        Mat4.translate(
                            (floating.x or 0)
                                + (rider.x or 0),

                            (floating.y or 0)
                                + (rider.y or 0),

                            (floating.z or 0)
                                + (rider.z or 0)
                        )
                    )


                local draws =
                    {}


                for _, part in ipairs(
                    replacement.parts
                ) do

                    local asset =
                        loadAsset(
                            part.asset
                        )


                    ----------------------------------------------------
                    -- Composite is atomic:
                    -- if one required part is missing, preserve the
                    -- original 2D fallback rather than draw half of it.
                    ----------------------------------------------------

                    if not asset then
                        return nil
                    end


                    local meshToDraw =
                        asset.mesh


                    if part.mirror then
                        meshToDraw =
                            asset.mirroredMesh
                    end


                    local texture =
                        textureForLoadedAsset(
                            asset,
                            p.sprite,
                            p.colors
                        )


                    if not texture then
                        return nil
                    end


                    draws[
                        #draws + 1
                    ] = {

                        mesh =
                            meshToDraw,

                        texture =
                            texture,

                        model =
                            part.role == "rider"
                            and riderModel
                            or mountModel
                    }
                end


                return {

                    composite =
                        true,

                    draws =
                        draws
                }
            end


            ------------------------------------------------------------
            -- Normal single-asset replacement.
            ------------------------------------------------------------

            if not replacement.asset then
                return nil
            end


            local asset =
                loadAsset(
                    replacement.asset
                )


            if not asset then
                return nil
            end


            local meshToDraw =
                asset.mesh


            if replacement.mirror then
                meshToDraw =
                    asset.mirroredMesh
            end


            local texture =
                textureForLoadedAsset(
                    asset,
                    p.sprite,
                    p.colors
                )


            return {

                mesh =
                    meshToDraw,

                texture =
                    texture,

                model =
                    baseModel
            }
        end


        ----------------------------------------------------------------
        -- Draw one visible Porygonal replacement.
        ----------------------------------------------------------------

        local function drawWithToonOutline(mesh,texture,model,pull,sunModel)
        if ToonOutline and type(ToonOutline.draw)=="function" then
            return ToonOutline.draw(originalVoxelDraw,mesh,texture,model,pull,sunModel)
        end
        return originalVoxelDraw(mesh,texture,model,pull,sunModel)
    end

    local function drawPorygonal(p)

            local data =
                replacementDataForPose(
                    p
                )


            if not data then
                return false
            end


            love.graphics.setMeshCullMode(
                "none"
            )


            ------------------------------------------------------------
            -- The sunModel is the SAME model used by ShadowMap.draw.
            --
            -- Do not use ShadowMap.snug here: snug is designed for thin
            -- billboard stand-ins. Our character is real 3D geometry,
            -- like a building, so caster and lookup should match exactly.
            ------------------------------------------------------------

            if data.composite
                and data.draws then

                for _, draw in ipairs(
                    data.draws
                ) do

                    drawWithToonOutline(
                        draw.mesh,
                        draw.texture,
                        draw.model,
                        0,
                        draw.model
                    )
                end

            else

                drawWithToonOutline(
                    data.mesh,
                    data.texture,
                    data.model,
                    0,
                    data.model
                )
            end


            love.graphics.setMeshCullMode(
                "none"
            )


            return true
        end


        ----------------------------------------------------------------
        -- Draw one Porygonal shadow caster.
        ----------------------------------------------------------------

        local function drawPorygonalShadow(p)

            local data =
                replacementDataForPose(
                    p
                )


            if not data then
                return false
            end


            ------------------------------------------------------------
            -- ShadowMap.begin() already owns depth/shader/cull state.
            -- Keep culling disabled so the complete 3D volume can cast.
            ------------------------------------------------------------

            if data.composite
                and data.draws then

                for _, draw in ipairs(
                    data.draws
                ) do

                    originalShadowDraw(
                        draw.mesh,
                        draw.texture,
                        draw.model
                    )
                end

            else

                originalShadowDraw(
                    data.mesh,
                    data.texture,
                    data.model
                )
            end


            return true
        end


        ------------------------------------------------------------
        -- Fly trajectory.
        --
        -- Returns world offset + yaw for the current Porygonal Fly state.
        -- X is used as the first prototype's horizontal travel axis;
        -- this can later be promoted to a camera-relative axis if needed.
        ------------------------------------------------------------

        -- U-shaped cinematic: descending bird -> Red leaps at the nadir ->
        -- bird climbs away. Both coordinates are visual-only; native Fly
        -- destination, map changes and collision are owned by Gen1Recomp.
        local function flyClamp(n)
            return math.max(0, math.min(1, n))
        end

        local function flyEase(n)
            n = flyClamp(n)
            return n * n * (3 - 2 * n)
        end

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

        local function flyMountFromGame(state)
            -- Some Gen1Recomp builds report the actual HM user in flyAnim;
            -- others expose only animation timing. Do not guess a party slot.
            local anim = state and state.flyAnim
            local mon = type(anim)=="table" and
                (anim.species or anim.pokemon or anim.mon or anim.flySpecies) or nil
            if type(mon)=="table" then
                mon = mon.species or mon.name or mon.pokemon
            end
            if type(mon)=="string" then
                local lowered = mon:lower():gsub("[^a-z]","")
                if lowered=="pidgeot" or lowered=="pokemonpidgeot" then return "pokemon_pidgeot" end
                if lowered=="articuno" or lowered=="pokemonarticuno" then return "pokemon_articuno" end
                if lowered=="zapdos" or lowered=="pokemonzapdos" then return "pokemon_zapdos" end
                if lowered=="moltres" or lowered=="pokemonmoltres" then return "pokemon_moltres" end
            end
            return Registry.fly_mount.base
        end

        local function flyReplacementData()
            local step=flyStep()
            if not step then return nil end
            local mountBase=flyState.mountBase or Registry.fly_mount.base
            local definition=Registry.lookupFly and Registry.lookupFly(
                step.pose,step.phase,(step.jump or 0)*1.875,mountBase) or nil
            if not (definition and definition.parts) then return nil end
            local mountModel,riderModel,actor=FlyChoreography.models(
                Mat4,flyState,definition,step)
            mountModel=enlargeNpcDrawModel(mountModel,true,renderContext)
            riderModel=enlargeNpcDrawModel(riderModel,true,renderContext)
            -- Ranch may provide the mount's geometry; it shares the same
            -- choreography and actor coordinates instead of another route.
            local ranchApi=rawget(_G,"UNIVERSAL_RANCH_FLY_API")
            local ranchActive=false
            if ranchApi and type(ranchApi.prepare)=="function" then
                local ok,ready=pcall(ranchApi.prepare,latestWorldState)
                ranchActive=ok and ready==true
            end
            if ranchActive and type(ranchApi.seatHeight)=="function"
                and step.rx==nil then
                local ok,seat=pcall(ranchApi.seatHeight)
                if ok and type(seat)=="number" then
                    local floating=definition.flying_offset or {}
                    local rider=definition.rider_offset or {}
                    local origin=Mat4.mul(Mat4.translate(actor.x,actor.y,actor.z),
                        Mat4.rotateY(step.yaw or 0))
                    riderModel=enlargeNpcDrawModel(Mat4.mul(origin,
                        Mat4.translate(rider.x or 0,seat,rider.z or 0)),true,renderContext)
                end
            end
            local draws={}
            for _,part in ipairs(definition.parts) do
                if not (ranchActive and part.role=="mount") then
                    local asset=loadAsset(part.asset)
                    if not asset then return nil end
                    local texture=textureForLoadedAsset(asset,
                        flyState.playerSprite,flyState.colors)
                    if not texture then return nil end
                    draws[#draws+1]={mesh=asset.mesh,texture=texture,
                        model=part.role=="rider" and riderModel or mountModel,role=part.role}
                end
            end
            if ranchActive then draws.ranch=actor end
            draws.mountWorld=actorCoords or actor
            return draws
        end

        -- Flight draws are never allowed to abort the hosting voxel renderer.
        local flyDrawWarningIssued = false
        local function flyDrawWarning(stage, err)
            if flyDrawWarningIssued then return end
            flyDrawWarningIssued = true
            if mod and mod.log then
                pcall(function() mod.log:warn("NPC Fly: %s failed; using native fallback: %s", tostring(stage), tostring(err)) end)
            end
        end

        local flySuccessLogged=false
        local function drawFlyVisible()
            -- v38: HM Fly cinematic is fully drawn by standalone_fly.lua.
            if Registry.standaloneFlyOwnsFly then return false end
            local okData, draws = pcall(flyReplacementData)
            if not okData then
                flyDrawWarning("build mesh", draws)
                return false
            end
            if type(draws) ~= "table" or #draws == 0 then
                return false
            end
            local gfx = love and love.graphics
            local oldCull = "none"
            if gfx and type(gfx.getMeshCullMode) == "function" then
                local okMode, mode = pcall(gfx.getMeshCullMode)
                if okMode and type(mode) == "string" then oldCull = mode end
            end
            local okDraw, err = pcall(function()
                if gfx and type(gfx.setMeshCullMode) == "function" then gfx.setMeshCullMode("none") end
                for _, draw in ipairs(draws) do
                    if not (draw and draw.mesh and draw.texture and draw.model) then
                        error("incomplete Pidgeot/Red model")
                    end
                    local external = draw.role=="mount" and FlyMounts and
                        FlyMounts.draw(originalVoxelDraw,draws.mountWorld,flyNowSeconds())
                    if not external then
                        originalVoxelDraw(draw.mesh,draw.texture,draw.model,0,draw.model)
                    end
                end
            end)
            -- Return the graphics state to the external renderer even on error.
            if gfx and type(gfx.setMeshCullMode) == "function" then
                pcall(gfx.setMeshCullMode, oldCull)
            end
            if not okDraw then
                renderedCustomFly = false
                flyDrawWarning("visible pass", err)
                return false
            end
            renderedCustomFly = true
            if not flySuccessLogged then
                flySuccessLogged=true
                if mod.log then
                    mod.log:info("NPC Fly: custom Pidgeot + Red GLBs submitted to 3D")
                end
            end
            return true
        end


        ----------------------------------------------------------------
        -- GUARANTEED DRAMALESS FLY VISIBLE INSERTION
        --
        -- An earlier approach used the grass mesh as a post-reflection anchor.
        -- Carmin-sur-Mer exposed the flaw: grass is map content, therefore
        -- it is not guaranteed to exist.
        --
        -- Voxel3D.endScene() is the real renderer lifecycle boundary:
        -- it executes for the main world scene, never for the internal
        -- water-reflection copy, and 3D submission is still valid
        -- immediately before the original endScene() call.
        --
        -- Fly is therefore injected once, immediately before endScene().
        ----------------------------------------------------------------

        Voxel3D.endScene =
            function(
                ...
            )

                local ctx =
                    renderContext


                if ctx
                    and ctx.flyActive
                    and not ctx.flyVisibleDrawn then

                    local flyDrawOK, flyRendered = pcall(drawFlyVisible)

                    ctx.flyVisibleDrawn = flyDrawOK and flyRendered == true
                    if ctx.flyVisibleDrawn and FlySpriteGuard then
                        FlySpriteGuard.mark(activeFlyWorldState)
                    end
                end


                return originalEndScene(
                    ...
                )
            end


        local function drawFlyShadow()
            local okData, draws = pcall(flyReplacementData)
            if not okData then
                flyDrawWarning("shadow mesh", draws)
                return false
            end
            if type(draws) ~= "table" or #draws == 0 then return false end
            local ok, err = pcall(function()
                for _, draw in ipairs(draws) do
                    if not (draw and draw.mesh and draw.texture and draw.model) then
                        error("incomplete Fly shadow asset")
                    end
                    local usedExternal = draw.role=="mount" and FlyMounts and
                        FlyMounts.shadow(originalShadowDraw)
                    if not usedExternal then originalShadowDraw(draw.mesh,draw.texture,draw.model) end
                end
            end)
            if not ok then flyDrawWarning("shadow pass", err); return false end
            return true
        end


        ----------------------------------------------------------------
        -- Observe ShadowMap.draw.
        --
        -- The shadow pass iterates ALL captured poses (including the
        -- player even when first-person hides the visible card).
        -- Billboard identity keeps authored figures / battle cards /
        -- terrain out of this path.
        ----------------------------------------------------------------

        ShadowMap.draw =
            function(
                mesh,
                texture,
                model
            )

                local info =
                    billboardInfo[mesh]


                local ctx =
                    renderContext


                --------------------------------------------------------
                -- Porygonal Fly shadow: draw once per shadow pass.
                --------------------------------------------------------

                if ctx
                    and ctx.flyActive
                    and not ctx.flyShadowDrawn then

                    local flyShadowOK, flyShadowDrawn = pcall(drawFlyShadow)

                    ctx.flyShadowDrawn = flyShadowOK and flyShadowDrawn == true
                end


                --------------------------------------------------------
                -- Authored FIGURE replacement.
                --------------------------------------------------------

                if ctx
                    and ctx.specialFigures
                    and ctx.specialFigures[mesh] then

                    local data =
                        replacementDataForFigure(
                            ctx.specialFigures[
                                mesh
                            ]
                        )


                    if data then

                        originalShadowDraw(
                            data.mesh,
                            data.texture,
                            data.model
                        )

                        return
                    end
                end


                if info
                    and ctx then

                    local poses =
                        ctx.poses


                    local count =
                        #poses


                    if count > 0 then

                        ctx.shadowDrawIndex =
                            (ctx.shadowDrawIndex or 0)
                            + 1


                        local poseIndex =
                            (
                                (
                                    ctx.shadowDrawIndex
                                    - 1
                                )
                                % count
                            )
                            + 1


                        local p =
                            poses[
                                poseIndex
                            ]


                        if p
                            and p.sprite
                            and p.sprite.def
                            and p.sprite.def == info.def then

                            if p.isPlayer and ((Registry.standaloneFlyPresenting
                            and Registry.standaloneFlyPresenting())
                            or (ctx.flyActive and ctx.flyVisibleDrawn == true)) then

                                return
                            end


                            -- Never animate/upload distant NPC shadow meshes.
                            if not p.isPlayer and npcBeyondRange(ctx, p.px, p.py) then
                                return
                            end

                            if drawPorygonalShadow(
                                p
                            ) then

                                return
                            end
                        end
                    end
                end


                return originalShadowDraw(
                    mesh,
                    texture,
                    model
                )
            end


        ----------------------------------------------------------------
        -- Observe Voxel3D.draw.
        --
        -- A solid character draw is identified by BOTH:
        --
        --     * its mesh was returned by SpriteBillboards.mesh
        --     * sunModel is present
        --
        -- Ghost and fallback-shadow draws use billboard meshes too, but
        -- do not supply sunModel and therefore pass through untouched.
        ----------------------------------------------------------------

        -- V57 hidden-character silhouettes: the Dramaless host intentionally
        -- draws its *sprite* quad with inverted depth BEFORE its solid actors.
        -- The normal actor replacement below only runs with sunModel ~= nil,
        -- so without this scoped handler the 2D Game Boy outline survives.
        --
        -- This handler preserves the host's inverted-depth shader and draws
        -- our identical posed GLB transform through the original Voxel3D
        -- draw routine. It does NOT re-enter the solid actor wrapper, add
        -- sprites, patch textures, or change any world shadow caster.
        local function drawReplacementOcclusionGhost(p)
            if not p then return false end
            local data = replacementDataForPose(p)
            if not data then return false end
            -- Fly is owned by the independent Pidgeot overlay. No native
            -- Red shadowQuad should leak in behind buildings during Fly.
            if p.isPlayer and (
                (Registry.standaloneFlyPresenting
                    and Registry.standaloneFlyPresenting())
                or (renderContext and renderContext.flyActive)
            ) then
                return true
            end
            -- For successfully replaced actors, suppress just the inverted-
            -- depth sprite/GLB silhouette pass. Do not suppress regular
            -- visible NPCs, world shading, collisions or Fly.
            return true
        end

        Voxel3D.draw =
            function(
                mesh,
                texture,
                model,
                pull,
                sunModel
            )

                local info =
                    billboardInfo[mesh]


                local ctx =
                    renderContext

                --------------------------------------------------------
                -- Inverted-depth OCCLUSION pass only (not cast shadows).
                -- Dramaless calls SpriteBillboards.shadowQuad here and
                -- Voxel3D.draw without sunModel. The same sprite definition
                -- and billboard transform let us resolve the matching
                -- captured Red/NPC pose without classifying world geometry.
                --------------------------------------------------------
                if insideOcclusionPass and ctx and info then
                    local p = poseForVisibleBillboard(ctx, info, model)
                    if p then
                        if (not p.isPlayer and npcBeyondRange(ctx,p.px,p.py))
                            or (p.isPlayer and FirstPerson
                                and FirstPerson.hidePlayer
                                and FirstPerson.hidePlayer()) then
                            return
                        end
                        if drawReplacementOcclusionGhost(p) then
                            return
                        end
                    end
                    -- Unknown/unmapped character: leave the host's native
                    -- Game Boy outline untouched as a safety fallback.
                    return originalVoxelDraw(mesh,texture,model,pull,sunModel)
                end


                --------------------------------------------------------
                -- Porygonal Fly visible composite: draw once in the solid
                -- camera pass, then suppress the normal player card/model
                -- until Porygonal's landing has completed.
                --------------------------------------------------------

                -- v30.7: submit the Pidgeot + Red mesh in the active solid
                -- camera pass.  Waiting exclusively for endScene() was
                -- unreliable in some external renderer pipelines: if that
                -- deferred call is missed, native fxBird() is the only Fly
                -- visual and the suppression guard never arms.  Keep the
                -- endScene fallback for scenes without any solid draws.
                if ctx and ctx.flyActive and sunModel ~= nil
                    and not ctx.flyVisibleDrawn then
                    local okFly, didDraw = pcall(drawFlyVisible)
                    ctx.flyVisibleDrawn = okFly and didDraw == true
                    if ctx.flyVisibleDrawn and FlySpriteGuard then
                        FlySpriteGuard.mark(activeFlyWorldState)
                    end
                end

                --------------------------------------------------------
                -- Authored FIGURE replacement.
                --
                -- The figure mesh is identified directly, so this path
                -- does not consume or modify the normal character draw
                -- index. Normal NPC rendering stays untouched.
                --------------------------------------------------------

                if ctx
                    and ctx.specialFigures
                    and ctx.specialFigures[mesh]
                    and sunModel ~= nil then

                    local data =
                        replacementDataForFigure(
                            ctx.specialFigures[
                                mesh
                            ]
                        )


                    if data then

                        love.graphics.setMeshCullMode(
                            "none"
                        )


                        originalVoxelDraw(
                            data.mesh,
                            data.texture,
                            data.model,
                            0,
                            data.model
                        )


                        love.graphics.setMeshCullMode(
                            "none"
                        )


                        return
                    end
                end


                -- Apply view cutoff only to character billboards.
                -- Suppress their distant 2D fallback as well as the 3D mesh;
                -- leave terrain, buildings, authored figures and FX alone.
                if info and ctx and sunModel ~= nil
                    and billboardBeyondRange(ctx, model) then
                    return
                end

                if info
                    and ctx
                    and sunModel ~= nil then

                    local p =
                        poseForVisibleBillboard(
                            ctx,
                            info,
                            model
                        )


                    if p then

                        if not p.isPlayer and npcBeyondRange(ctx, p.px, p.py) then
                            return
                        end

                        if p.isPlayer and ((Registry.standaloneFlyPresenting
                            and Registry.standaloneFlyPresenting())
                            or (ctx.flyActive and ctx.flyVisibleDrawn == true)) then

                            ------------------------------------------------
                            -- Do not let the normal player reappear between
                            -- departure, map transition and Porygonal landing.
                            ------------------------------------------------

                            return
                        end


                        if drawPorygonal(
                            p
                        ) then
                            if p.isPlayer and (ctx.playerFishing or p.fishing) then
                                lastFishingGlbDrawn = true
                            end
                            return
                        end
                    end
                end


                return originalVoxelDraw(
                    mesh,
                    texture,
                    model,
                    pull,
                    sunModel
                )
            end


        ----------------------------------------------------------------
        -- Observe VoxelScene.render.
        --
        -- This is the frame boundary and provides the OverworldState.
        ----------------------------------------------------------------

        VoxelScene.render =
            function(
                state,
                w,
                h,
                vw,
                vh,
                paletteFor,
                eyes
            )

                --------------------------------------------------------
                -- Keep the current state after VoxelScene.render returns:
                -- Dramaless runs ctx.drawFx in the overlay immediately after
                -- this call, outside renderContext.
                --------------------------------------------------------

                -- Recover from an interrupted field FX overlay (e.g. Fly teleport).
                restoreFxDraw()
                latestWorldState =
                    state
                renderedCustomFly = false
                lastFlyVisibleDrawn = false
                lastFishingGlbDrawn = false

                -- Identify the currently loaded map before any character
                -- render calls. Off-map characters are NOT preloaded; visible
                -- neighboring-map ghost entities are still handled normally.
                -- This affects only the NPC model cache, not world rendering,
                -- sprite movement, game logic, or original drawing methods.
                if CharacterRuntime.setActiveMap and state and state.map then
                    local activeMap = state.map.id or state.map.name or state.map.key
                    if activeMap ~= nil then
                        local mapOK, mapErr = pcall(CharacterRuntime.setActiveMap, activeMap)
                        if not mapOK then
                            mod.log:warn("Could not update character model map cache: %s", tostring(mapErr))
                        end
                    end
                end


                --------------------------------------------------------
                -- Porygonal Fly state machine.
                --------------------------------------------------------

                local now =
                    flyNowSeconds()


                local player =
                    state
                    and state.player
                    or nil


                activeFlyWorldState = state
                if FlySpriteGuard and type(FlySpriteGuard.begin)=="function" then
                    FlySpriteGuard.begin(state)
                end
                local flyNativeActive,activeFlyAnim = FlyChoreography.nativeFlyActive(state)

                -- Fly destination arrival is a native Gen1Recomp state, not a
                -- player-position update. Read Game.overworld because render
                -- context snapshots may not yet contain flyArrive on the first
                -- destination frame. Keep the table reference as a per-arrival
                -- latch so the cinematic cannot restart during the same Fly.
                local flyEngineWorld = state
                if type(state)~="table" or type(state.flyArrive)~="table" then
                    local coreOK, coreGame = pcall(require, "src.core.Game")
                    if coreOK and type(coreGame)=="table" and
                        type(coreGame.overworld)=="table" then
                        flyEngineWorld=coreGame.overworld
                    end
                end
                local nativeFlyArrival = (type(flyEngineWorld)=="table"
                    and type(flyEngineWorld.flyArrive)=="table")
                    and flyEngineWorld.flyArrive or nil
                local newNativeFlyArrival = nativeFlyArrival ~= nil
                    and nativeFlyArrival ~= flyState.lastArrival
                if flyState.mode == "normal" and nativeFlyArrival then
                    flyState.lastArrival = nativeFlyArrival
                end
                if not flyNativeActive then flyState.lastActiveFlyAnim=nil end




                local playerPx =
                    player
                    and player.px
                    or 0


                local playerPy =
                    player
                    and player.py
                    or 0


                local playerGround =
                    0


                if player
                    and state
                    and state.map
                    and VoxelScene.groundAt
                    and player.cellX ~= nil
                    and player.cellY ~= nil then

                    local groundOK, groundResult = pcall(VoxelScene.groundAt,
                        state.map, player.cellX, player.cellY)
                    playerGround = (groundOK and groundResult) or 0
                end


                --------------------------------------------------------
                -- Start departure on native Fly.
                --------------------------------------------------------

                -- Fail open if the game cancelled Fly without switching maps.
                if flyState.mode == "departure" and not flyNativeActive
                    and flyState.startMap == (state and state.map)
                    and (now - (flyState.startedAt or now)) > 7.0 then
                    flyState.mode = "normal"
                    flyState.captureBird = false
                    flyState.birdImage = nil
                end

                if flyState.mode
                    == "normal"
                    and flyNativeActive
                    and activeFlyAnim ~= flyState.lastActiveFlyAnim
                    and player then

                    flyState.mode =
                        "departure"
                    if FlyMounts then FlyMounts.begin(mod,state,activeFlyAnim) end
                    flyState.lastActiveFlyAnim=activeFlyAnim
                    if mod.log then
                        mod.log:info("NPC Fly: native HM Fly detected; starting species-aware Fly + Red")
                    end


                    flyState.startedAt =
                        now


                    flyState.startMap =
                        state.map


                    flyState.startPx =
                        playerPx


                    flyState.startPy =
                        playerPy


                    flyState.startGround =
                        playerGround


                    flyState.playerSprite =
                        player.sprite


                    flyState.colors =
                        colorsForMap(
                            paletteFor,
                            state.map
                        )


                    flyState.birdImage =
                        nil


                    flyState.mountBase =
                        flyMountFromGame(state)

                    flyState.captureBird =
                        true
                end


                --------------------------------------------------------
                -- Detect destination.
                --
                -- Prefer map identity change. The position fallback also
                -- handles a destination represented by the same map object.
                --------------------------------------------------------

                if flyState.mode == "departure" and player then

                    local mapChanged =
                        state.map
                        ~= flyState.startMap


                    local dx =
                        playerPx
                        - flyState.startPx


                    local dz =
                        playerPy
                        - flyState.startPy


                    local movedFar =
                        (
                            dx * dx
                            + dz * dz
                        )
                        > (
                            16 * 16
                        )


                    if newNativeFlyArrival or mapChanged
                        or (not flyNativeActive and movedFar) then

                        flyState.mode =
                            "landing"
                    flyState.arrivalMap=state.map
                        -- Consume this native arrival immediately, before the
                        -- player takes any step. Use one cinematic per arrival.
                        if newNativeFlyArrival then
                            flyState.lastArrival = nativeFlyArrival
                        end



                        flyState.landingAt =
                            now


                        flyState.targetPx =
                            playerPx


                        flyState.targetPy =
                            playerPy


                        flyState.targetGround =
                            playerGround
                    flyState.targetFacing = player.facing


                        flyState.playerSprite =
                            player.sprite
                            or flyState.playerSprite


                        flyState.colors =
                            colorsForMap(
                                paletteFor,
                                state.map
                            )
                            or flyState.colors
                    end
                end


                --------------------------------------------------------
                -- End Porygonal landing and hand control back to the
                -- ordinary player renderer.
                --------------------------------------------------------

                if flyState.mode
                    == "landing" then

                    local flyCfg =
                        flyAnimationConfig()


                    local landingDuration = FlyChoreography.landingDuration(flyCfg)


                    local settle = 0


                    if (state and flyState.arrivalMap and state.map ~= flyState.arrivalMap) or
                    (now - flyState.landingAt) >= (landingDuration + settle) then

                    flyState.mode =
                        "normal"


                    flyState.captureBird =
                        false


                    flyState.birdImage =
                        nil
                    local ranchApi=rawget(_G,"UNIVERSAL_RANCH_FLY_API")
                    if ranchApi and type(ranchApi.finish)=="function" then
                        pcall(ranchApi.finish)
                    end
                    end
                end
            if FlyFollowers then FlyFollowers.sync(mod,flyState.mode~="normal") end



                local previousContext =
                    renderContext


                -- Render states are sampled from the actual Gen1 player
                -- and persistent save.  Fishing can live on the overworld
                -- state instead of on the player entity itself.
                local save = (state.game and state.game.save)
                    or state.save
                    or (CoreGame and CoreGame.save)
                local ctx = {

                    playerPx = playerPx,
                    playerPy = playerPy,
                    livePlayer = player,
                    playerSurfing = (player and player.surfing == true)
                        or (state.surfing == true),
                    playerCycling = (save and save.onBike == true)
                        or (player and player.onBike == true)
                        or (state.onBike == true),
                    playerFishing = (state.fishing ~= nil and state.fishing ~= false)
                        or (player and player.fishing ~= nil and player.fishing ~= false) or false,
                    npcMaxDistanceSquared = maxNpcDistanceSquared(),
                    npcScale = selectedNpcScale(),
                    playerScale = selectedPlayerScale(),

                    poses =
                        {},

                    visible =
                        nil,

                    characterDrawIndex =
                        0,

                    shadowDrawIndex =
                        0,



                    flyActive =
                        flyState.mode
                        ~= "normal",

                    flyVisibleDrawn =
                        false,

                    flyShadowDrawn =
                        false,

                    specialFigures =
                        setmetatable(
                            {},
                            {
                                __mode = "k"
                            }
                        )
                }


                renderContext =
                    ctx


                local restorers =
                    {}


                local alreadyWrapped =
                    setmetatable(
                        {},
                        {
                            __mode = "k"
                        }
                    )


                --------------------------------------------------------
                -- Ghost entities first, matching Dramaless Shape posesOf().
                --------------------------------------------------------

                for _, ghost in ipairs(
                    state.ghosts
                    or {}
                ) do

                    local npc =
                        ghost.npc


                    local map =
                        ghost.map
                        or state.map


                    wrapEntityPose(
                        npc,
                        map,
                        ghost.ox or 0,
                        ghost.oy or 0,
                        false,
                        colorsForMap(
                            paletteFor,
                            map
                        ),
                        restorers,
                        alreadyWrapped
                    )
                end


                --------------------------------------------------------
                -- Current-map entities.
                --------------------------------------------------------

                local mapColors =
                    colorsForMap(
                        paletteFor,
                        state.map
                    )


                --------------------------------------------------------
                -- Pokémon Center seated authored FIGURE.
                --
                -- The seated man is not a normal state.entities NPC.
                -- In tested Pokémon Centers (Viridian, Vermilion), he is
                -- exposed by Dramaless Shape as the map's authored FIGURE.
                --
                -- Therefore do NOT associate him with a nearby logical NPC.
                -- In a Pokémon Center, when the current map exposes exactly
                -- one authored FIGURE, that FIGURE gets the seated spe1 model.
                --------------------------------------------------------

                do
                    local mapId =
                        state.map
                        and state.map.id
                        or ""


                    local isPokecenter =
                        string.find(
                            string.upper(
                                tostring(mapId)
                            ),
                            "POKECENTER",
                            1,
                            true
                        ) ~= nil


                    if isPokecenter
                        and Registry.lookupPokecenterSeatedFigure
                        and ChunkMesher
                        and ChunkMesher.figures then

                        local figures =
                            ChunkMesher.figures(
                                state.map
                            )
                            or {}


                        ------------------------------------------------
                        -- Conservative rule:
                        -- only auto-assign when there is ONE authored
                        -- FIGURE on the Pokémon Center map.
                        ------------------------------------------------

                        if #figures == 1 then

                            local figure =
                                figures[1]


                            local special =
                                Registry.lookupPokecenterSeatedFigure(mapId)


                            if figure
                                and figure.mesh
                                and special then

                                ctx.specialFigures[
                                    figure.mesh
                                ] = {

                                    figure =
                                        figure,

                                    replacement =
                                        special,

                                    ------------------------------------------------
                                    -- Authored FIGURE palette.
                                    --
                                    -- The seated figure has no real Sprite instance.
                                    -- Use a stable character palette in GBC mode,
                                    -- and the effective map palette in other modes.
                                    ------------------------------------------------

                                    sprite =
                                        nil,

                                    colors =
                                        colorsForAuthoredFigure(
                                            paletteFor,
                                            state.map,
                                            state
                                        ),
                                    ------------------------------------------------
                                    -- Stable semantic key for procedural idle.
                                    ------------------------------------------------

                                    idleKey =
                                        tostring(mapId)
                                        .. ":pokecenter_seated"
                                }
                            end
                        end
                    end
                end


                for _, entity in ipairs(
                    state.entities
                    or {}
                ) do

                    wrapEntityPose(
                        entity,
                        state.map,
                        0,
                        0,
                        entity == state.player,
                        mapColors,
                        restorers,
                        alreadyWrapped
                    )
                end


                --------------------------------------------------------
                -- Let Dramaless Shape execute its normal renderer.
                --------------------------------------------------------

                local ok,
                      resultA,
                      resultB,
                      resultC =

                    pcall(
                        function()

                            return originalVoxelRender(
                                state,
                                w,
                                h,
                                vw,
                                vh,
                                paletteFor,
                                eyes
                            )
                        end
                    )


                --------------------------------------------------------
                -- Always restore entity pose methods.
                --------------------------------------------------------

                for i =
                    #restorers,
                    1,
                    -1 do

                    pcall(
                        restorers[i]
                    )
                end


                lastFlyVisibleDrawn = ctx.flyVisibleDrawn == true
                renderContext =
                    previousContext


                if not ok then

                    error(
                        resultA
                    )
                end


                return resultA,
                       resultB,
                       resultC
            end



        return true
    end


    ----------------------------------------------------------------
    -- COMPAT: RECOMP 0.1.83
    --
    -- Original integration using Lua private-function hooks
    -- (debug.getupvalue / debug.setupvalue).
    -- Kept frozen as a fallback for the older runtime.
    ----------------------------------------------------------------

    local function installCompat0183()

        ----------------------------------------------------------------
        -- Locate drawCast
        ----------------------------------------------------------------

        local _,
              drawCast =

            findUpvalue(
                VoxelScene.render,
                "drawCast"
            )


        if type(drawCast)
            ~= "function" then

            mod.log:error(
                "Dramaless Shape adapter: drawCast was not found"
            )

            return false
        end


        ----------------------------------------------------------------
        -- Track the exact pose currently passed through viewFacing()
        --
        -- Dramaless Shape does:
        --
        -- viewFacing(p)
        -- immediately followed by
        -- drawEntity(...)
        --
        -- So we do not need to associate data with sprite objects.
        -- We only remember the current p.
        ----------------------------------------------------------------

        local currentPose =
            nil


        local viewFacingIndex,
              originalViewFacing =

            findUpvalue(
                drawCast,
                "viewFacing"
            )


        if not viewFacingIndex
            or type(originalViewFacing)
                ~= "function" then

            mod.log:error(
                "Dramaless Shape adapter: viewFacing was not found"
            )

            return false
        end


        local function trackedViewFacing(p)

            currentPose =
                p


            return originalViewFacing(
                p
            )
        end


        local viewFacingResult =
            debug.setupvalue(
                drawCast,
                viewFacingIndex,
                trackedViewFacing
            )


        if not viewFacingResult then

            mod.log:error(
                "Dramaless Shape adapter could not track current pose"
            )

            return false
        end


        ----------------------------------------------------------------
        -- Resolve true world-facing
        ----------------------------------------------------------------

        local function trueFacing(
            fallbackFacing
        )

            if currentPose
                and currentPose.facing then

                return currentPose.facing
            end


            return fallbackFacing
        end


        ----------------------------------------------------------------
        -- Is current pose the player?
        ----------------------------------------------------------------

        local function currentPoseIsPlayer()

            return currentPose
                and currentPose.isPlayer
                and true
                or false
        end


        ----------------------------------------------------------------
        -- World yaw
        ----------------------------------------------------------------

        local function facingToYaw(
            facing
        )

            ------------------------------------------------------------
            -- Player + free camera:
            -- continuous body yaw
            ------------------------------------------------------------

            if currentPoseIsPlayer()
                and FirstPerson
                and FirstPerson.engaged
                and FirstPerson.engaged()
                and FirstPerson.bodyYaw ~= nil then

                return FirstPerson.bodyYaw
            end


            ------------------------------------------------------------
            -- NPC / normal camera:
            -- original world facing
            ------------------------------------------------------------

            if facing == "down" then
                return 0
            end


            if facing == "left" then
                return math.rad(-90)
            end


            if facing == "up" then
                return math.rad(180)
            end


            if facing == "right" then
                return math.rad(90)
            end


            return 0
        end


        ----------------------------------------------------------------
        -- Locate drawEntity
        ----------------------------------------------------------------

        local entityIndex,
              originalDrawEntity =

            findUpvalue(
                drawCast,
                "drawEntity",
                VoxelScene.drawEntity
            )


        if not entityIndex
            or type(originalDrawEntity)
                ~= "function" then

            mod.log:error(
                "Dramaless Shape adapter: drawEntity was not found"
            )

            return false
        end


        ----------------------------------------------------------------
        -- Porygonal draw
        ----------------------------------------------------------------

        local function drawEntity(
            sprite,
            px,
            py,
            facing,
            phase,
            flip,
            gh,
            colors,
            lift
        )

            ------------------------------------------------------------
            -- `facing` may be Dramaless Shape viewFacing.
            --
            -- currentPose.facing is the original world-facing.
            ------------------------------------------------------------

            local worldFacing =
                trueFacing(
                    facing
                )


            ------------------------------------------------------------
            -- Determine Gen1 pose from real world-facing
            ------------------------------------------------------------

            local spriteId,
                  frame,
                  mirror =

                getSpritePose(
                    sprite,
                    worldFacing,
                    phase,
                    flip
                )


            ------------------------------------------------------------
            -- Registry lookup
            ------------------------------------------------------------

            local replacement =
                Registry.lookup(
                    spriteId,
                    frame,
                    mirror,
                    worldFacing
                )


            ------------------------------------------------------------
            -- Porygonal asset available
            ------------------------------------------------------------

            if replacement
                and replacement.asset then

                local asset =
                    loadAsset(
                        replacement.asset
                    )


                if asset then

                    local y =
                        (gh or 0)
                        + (lift or 0)


                    local yaw =
                        facingToYaw(
                            replacement.facing
                            or worldFacing
                        )


                    local model =
                        Mat4.mul(
                            Mat4.translate(
                                px + 8,
                                y,
                                py + 8
                            ),
                            Mat4.rotateY(
                                yaw
                            )
                        )


                    -- Old renderer profile also applies scale at draw time.
                    model = enlargeNpcDrawModel(model, currentPoseIsPlayer(), nil)

                    local meshToDraw =
                        asset.mesh


                    if replacement.mirror then

                        meshToDraw =
                            asset.mirroredMesh

                    end


                    local texture =
                        textureForLoadedAsset(
                    asset,
                            sprite,
                            colors
                        )


                    love.graphics.setMeshCullMode(
                        "none"
                    )


                    Voxel3D.draw(
                        meshToDraw,
                        texture,
                        model,
                        0
                    )


                    love.graphics.setMeshCullMode(
                        "none"
                    )


                    return true
                end
            end


            ----------------------------------------------------------------
            -- No 3D asset:
            -- preserve Dramaless Shape's original 2D behaviour.
            ----------------------------------------------------------------

            return originalDrawEntity(
                sprite,
                px,
                py,
                facing,
                phase,
                flip,
                gh,
                colors,
                lift
            )

        end


        ----------------------------------------------------------------
        -- Install replacement
        ----------------------------------------------------------------

        local result =
            debug.setupvalue(
                drawCast,
                entityIndex,
                drawEntity
            )


        if not result then

            mod.log:error(
                "Dramaless Shape adapter could not replace drawEntity"
            )

            return false
        end



        return true
    end


    ----------------------------------------------------------------
    -- Select compatibility profile
    ----------------------------------------------------------------

    if installCompat0199() then

        mod.log:info(
            "Dramaless Shape Porygonal adapter installed"
        )

        mod.log:info(
            "Porygonal COMPAT RECOMP 0.1.99 + 3D shadows installed"
        )

        return true
    end


    mod.log:info(
        "Porygonal COMPAT RECOMP 0.1.99 unavailable; trying 0.1.83"
    )


    if installCompat0183() then

        mod.log:info(
            "Dramaless Shape Porygonal adapter installed"
        )

        mod.log:info(
            "Porygonal COMPAT RECOMP 0.1.83 installed"
        )

        return true
    end


    mod.log:error(
        "Dramaless Shape adapter: no compatible Recomp integration found"
    )

    return false

end


return DramalessShapeAdapter

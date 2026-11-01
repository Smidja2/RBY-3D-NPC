-- Native HM Fly bird suppression owned by this NPC/GLB replacement mod.
-- No dependency on Dramaless, Ranch, or voxel renderer field-FX hooks.
-- The Gen1 overworld's local fxBird() creates overworld.birdSprite and calls
-- birdSprite:draw() through src.render.SpriteRenderer. Intercept the exact
-- actor at the SpriteRenderer entry point, BEFORE its image is rendered.
-- Other characters, decorative bird Pokemon and non-Fly field FX are not touched.
local M = { version = 1 }

function M.install(mod)
    local srOK, SR = pcall(require, "src.render.SpriteRenderer")
    local gameOK, Game = pcall(require, "src.core.Game")
    if not srOK or type(SR) ~= "table" or type(SR.draw) ~= "function"
        or not gameOK or type(Game) ~= "table" then
        return false, "native SpriteRenderer/Game unavailable"
    end

    -- Refresh the owner on hot reload instead of stacking a second wrapper.
    local hook = SR._gen1NpcDirectFlyBirdSuppression
    if type(hook) == "table" and hook.wrapper == SR.draw then
        hook.mod = mod
        return true
    end

    local original = SR.draw
    hook = { mod = mod, suppressed = 0, sessionActive = false }

    hook.wrapper = function(self, ...)
        -- Game.overworld is the OverworldState singleton initialized after mods
        -- load. The native fxBird() stores its private SpriteRenderer HERE.
        local world = Game.overworld
        local liveFly = type(world) == "table"
            and (world.flyAnim ~= nil and world.flyAnim ~= false
                 or world.flyArrive ~= nil and world.flyArrive ~= false)

        if liveFly
            and world.birdSprite ~= nil and self == world.birdSprite then
            hook.suppressed = hook.suppressed + 1
            if not hook.sessionActive then
                hook.sessionActive = true
                if hook.mod.log and hook.mod.log.info then
                    pcall(hook.mod.log.info, hook.mod.log,
                        "NPC Fly direct suppression active: native birdSprite hidden; GLB animation remains renderer-owned")
                end
            end
            -- Returning before the original draw preserves the native HM
            -- state machine, destination warp, and game-side timing.
            return
        end
        if not liveFly then hook.sessionActive = false end
        return original(self, ...)
    end
    SR.draw = hook.wrapper
    SR._gen1NpcDirectFlyBirdSuppression = hook
    return true
end

return M

-- Standalone NPC-only toon silhouette. No terrain/postprocess hooks.
-- Safe to load without a renderer: GPU work is lazy and optional.
local ToonOutline = {}
local shells = setmetatable({}, {__mode="k"})
local blackTexture = nil

local function solidBlackTexture()
    if blackTexture then return blackTexture end
    if not (love and love.image and love.graphics
        and type(love.image.newImageData)=="function"
        and type(love.graphics.newImage)=="function") then return nil end
    local ok,tex=pcall(function()
        local pixels=love.image.newImageData(1,1)
        pixels:setPixel(0,0,0,0,0,1)
        local image=love.graphics.newImage(pixels)
        if image.setFilter then image:setFilter("nearest","nearest") end
        return image
    end)
    if ok then blackTexture=tex end
    return blackTexture
end

-- Both shell meshes use the normal mesh winding. During the silhouette
-- pass FRONT faces are culled, exposing only the slightly expanded rear
-- surface around the character contour (inverted-hull toon technique).
function ToonOutline.prepare(asset,gpu,Voxel3D)
    if not asset or not asset.toonOutline or not gpu or not Voxel3D then return end
    if not asset.outlineVertices or not asset.outlineMirroredVertices then return end
    local ok,front,back=pcall(function()
        return Voxel3D.newMesh(asset.outlineVertices,asset.indices),
               Voxel3D.newMesh(asset.outlineMirroredVertices,asset.mirroredIndices)
    end)
    if not ok or not front or not back then return end
    gpu.outlineMesh,gpu.mirroredOutlineMesh=front,back
    shells[gpu.mesh]=front
    shells[gpu.mirroredMesh]=back
end

function ToonOutline.draw(draw,mesh,texture,model,pull,sunModel)
    local outline = mesh and shells[mesh] or nil
    if outline and love and love.graphics then
        local gfx=love.graphics
        local black=solidBlackTexture()
        if black and type(gfx.setMeshCullMode)=="function" then
            local prev="none"
            if type(gfx.getMeshCullMode)=="function" then
                local ok,mode=pcall(gfx.getMeshCullMode)
                if ok and type(mode)=="string" then prev=mode end
            end
            local ok=pcall(function()
                gfx.setMeshCullMode("front")
                draw(outline,black,model,pull,sunModel)
            end)
            -- Always restore culling so original model remains double-sided.
            pcall(gfx.setMeshCullMode,prev)
        end
    end
    return draw(mesh,texture,model,pull,sunModel)
end
return ToonOutline

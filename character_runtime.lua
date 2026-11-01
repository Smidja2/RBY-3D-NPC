local CharacterRuntime = {}


function CharacterRuntime.create(
    mod,
    loadLocalModule,
    versionGroup
)

assert(
    versionGroup ~= nil,
    "character_runtime.lua expected versionGroup"
)

    ----------------------------------------------------------------
    -- Gen1Recomp modules
    --
    -- These describe the CHARACTER DATA semantics used by Porygonal.
    -- They are intentionally kept out of renderer-specific adapters.
    ----------------------------------------------------------------

    local DynamicAnimation = loadLocalModule('assets/runtime/animation_engine.lua', mod, loadLocalModule)
    if not DynamicAnimation or not DynamicAnimation.hasRuntime then
        mod.log:error('Original GLB animation playback unavailable; runtime initialization aborted')
        return nil
    end

    local SR =
        require(
            "src.render.SpriteRenderer"
        )


    local TileRenderer =
        require(
            "src.render.TileRenderer"
        )


    local PaletteFX =
        require(
            "src.render.PaletteFX"
        )

    ----------------------------------------------------------------
    -- Version-aware palette resolver
    ----------------------------------------------------------------

    local PaletteResolverModule =
        loadLocalModule(
            "palettes/palette_resolver.lua"
        )

    assert(
        PaletteResolverModule
            and type(PaletteResolverModule.create)
                == "function",
        "Could not load Porygonal palette resolver"
    )


    local PaletteResolver =
        PaletteResolverModule.create(
            loadLocalModule
        )
        

    ----------------------------------------------------------------
    -- Protected character package V4
    --
    -- The package is a storage layer only. Registry and renderer adapters
    -- continue to request the same logical .lua paths as before.
    --
    -- V4 does NOT contain Lua source. Each protected chunk decodes directly
    -- to the mesh table expected by the existing renderer pipeline.
    ----------------------------------------------------------------

    local PACKAGE_PATH =
        "assets/porygonal_characters.pak"

    local PACKAGE_MAGIC =
        "PGCHAR04"

    local PACKAGE_VERSION =
        4

    local PACKAGE_MASTER_SEED =
        0x51A7C3D9

    local FIXED_SCALE =
        1000000

    local bitlib =
        bit

    if not bitlib then

        local okBit,
              loadedBit =
            pcall(
                require,
                "bit"
            )

        if okBit then
            bitlib = loadedBit
        end

    end

    assert(
        bitlib
            and bitlib.band
            and bitlib.bxor
            and bitlib.lshift
            and bitlib.rshift,
        "Porygonal protected assets require LuaJIT bit operations"
    )

    local band =
        bitlib.band

    local bxor =
        bitlib.bxor

    local lshift =
        bitlib.lshift

    local rshift =
        bitlib.rshift

    local packageState = {
        loaded = false,
        failed = false,
        bytes = nil,
        index = nil
    }


    local function u32(value)

        if value < 0 then
            return value + 4294967296
        end

        return value
    end


    local function readU16LE(
        bytes,
        offset
    )

        local a,
              b =
            bytes:byte(
                offset,
                offset + 1
            )

        if not b then
            return nil
        end

        return a
            + b * 256
    end


    local function readU32LE(
        bytes,
        offset
    )

        local a,
              b,
              c,
              d =
            bytes:byte(
                offset,
                offset + 3
            )

        if not d then
            return nil
        end

        return a
            + b * 256
            + c * 65536
            + d * 16777216
    end


    local function readS32LE(
        bytes,
        offset
    )

        local value =
            readU32LE(
                bytes,
                offset
            )

        if not value then
            return nil
        end

        if value >= 2147483648 then
            value =
                value - 4294967296
        end

        return value
    end


    local function assetHash(path)

        local normalized =
            tostring(path)
                :gsub("\\", "/")
                :lower()

        local h =
            5381

        for i = 1, #normalized do

            h =
                band(
                    h
                        + lshift(h, 5)
                        + normalized:byte(i),
                    0xffffffff
                )

        end

        return u32(h)
    end


    local function streamSeed(
        nameHash,
        rawSize
    )

        local seed =
            bxor(
                PACKAGE_MASTER_SEED,
                nameHash,
                lshift(rawSize, 7),
                rshift(rawSize, 3)
            )

        seed =
            band(
                seed,
                0xffffffff
            )

        if seed == 0 then
            seed = 0x6d2b79f5
        end

        return seed
    end


    local function nextStreamByte(state)

        state =
            bxor(
                state,
                lshift(state, 13)
            )

        state =
            bxor(
                state,
                rshift(state, 17)
            )

        state =
            bxor(
                state,
                lshift(state, 5)
            )

        state =
            band(
                state,
                0xffffffff
            )

        return state,
               band(state, 0xff)
    end


    local function unprotect(
        protected,
        seed
    )

        local out = {}
        local state = seed
        local piece = {}
        local pieceCount = 0

        for i = 1, #protected do

            local keyByte

            state,
            keyByte =
                nextStreamByte(
                    state
                )

            pieceCount =
                pieceCount + 1

            piece[pieceCount] =
                string.char(
                    bxor(
                        protected:byte(i),
                        keyByte
                    )
                )

            if pieceCount >= 4096 then

                out[#out + 1] =
                    table.concat(
                        piece
                    )

                piece = {}
                pieceCount = 0
            end

        end

        if pieceCount > 0 then

            out[#out + 1] =
                table.concat(
                    piece
                )

        end

        return table.concat(
            out
        )
    end


    local function ensurePackage()

        if packageState.loaded then
            return true
        end

        if packageState.failed then
            return false
        end

        local bytes,
              readErr =
            mod:read(
                PACKAGE_PATH
            )

        if not bytes then

            mod.log:error(
                "Could not read Porygonal character package %s: %s",
                PACKAGE_PATH,
                tostring(readErr)
            )

            packageState.failed =
                true

            return false
        end

        if bytes:sub(1, 8)
            ~= PACKAGE_MAGIC then

            mod.log:error(
                "Invalid Porygonal character package signature"
            )

            packageState.failed =
                true

            return false
        end

        local version =
            readU32LE(
                bytes,
                9
            )

        local count =
            readU32LE(
                bytes,
                13
            )

        if version ~= PACKAGE_VERSION
            or not count then

            mod.log:error(
                "Unsupported Porygonal character package version: %s",
                tostring(version)
            )

            packageState.failed =
                true

            return false
        end

        local index = {}
        local cursor = 17

        for i = 1, count do

            local nameHash =
                readU32LE(
                    bytes,
                    cursor
                )

            local offset =
                readU32LE(
                    bytes,
                    cursor + 4
                )

            local packedSize =
                readU32LE(
                    bytes,
                    cursor + 8
                )

            local rawSize =
                readU32LE(
                    bytes,
                    cursor + 12
                )

            local check =
                readU32LE(
                    bytes,
                    cursor + 16
                )

            if not nameHash
                or not offset
                or not packedSize
                or not rawSize
                or not check then

                mod.log:error(
                    "Truncated Porygonal character package index"
                )

                packageState.failed =
                    true

                return false
            end

            index[nameHash] = {
                offset = offset,
                packedSize = packedSize,
                rawSize = rawSize,
                check = check
            }

            cursor =
                cursor + 20
        end

        packageState.bytes =
            bytes

        packageState.index =
            index

        packageState.loaded =
            true

        mod.log:info(
            "Porygonal character package V4 ready (%d assets)",
            count
        )

        return true
    end


    local function decodeMeshBinary(
        bytes,
        nameHash,
        expectedCheck
    )

        local vertexCount =
            readU32LE(
                bytes,
                1
            )

        local indexCount =
            readU32LE(
                bytes,
                5
            )

        if not vertexCount
            or not indexCount then

            return nil,
                   "truncated mesh header"
        end

        local expectedSize =
            8
                + vertexCount * 24
                + indexCount * 2

        if #bytes ~= expectedSize then

            return nil,
                   "mesh binary size mismatch"
        end

        local calculatedCheck =
            band(
                vertexCount * 65537
                    + indexCount * 257
                    + nameHash,
                0xffffffff
            )

        calculatedCheck =
            u32(
                calculatedCheck
            )

        if calculatedCheck
            ~= expectedCheck then

            return nil,
                   "mesh metadata check failed"
        end

        local vertices = {}
        local cursor = 9

        for i = 1, vertexCount do

            local a =
                readS32LE(bytes, cursor)

            local b =
                readS32LE(bytes, cursor + 4)

            local c =
                readS32LE(bytes, cursor + 8)

            local d =
                readS32LE(bytes, cursor + 12)

            local e =
                readS32LE(bytes, cursor + 16)

            local f =
                readS32LE(bytes, cursor + 20)

            if not f then

                return nil,
                       "truncated vertex data"
            end

            vertices[i] = {
                a / FIXED_SCALE,
                b / FIXED_SCALE,
                c / FIXED_SCALE,
                d / FIXED_SCALE,
                e / FIXED_SCALE,
                f / FIXED_SCALE
            }

            cursor =
                cursor + 24
        end

        local indices = {}

        for i = 1, indexCount do

            local index =
                readU16LE(
                    bytes,
                    cursor
                )

            if not index then

                return nil,
                       "truncated index data"
            end

            indices[i] =
                index

            cursor =
                cursor + 2
        end

        return {
            vertices = vertices,
            indices = indices
        }
    end


    -- GLB meshes are pre-converted by the bundled offline converter.
    -- This independent asset loader reads our own fixed-point .bin files.
    -- No proprietary Porygonal .pak assets are used or included.
    local function loadProtectedMesh(path)
        local bytes = mod:read(path)
        if not bytes then
            return nil
        end
        local vertexCount = readU32LE(bytes, 1)
        local indexCount = readU32LE(bytes, 5)
        if not vertexCount or not indexCount then return nil end
        if vertexCount <= 0 or indexCount <= 0 then return nil end
        if vertexCount > 65535 or indexCount > 150000 then return nil end
        local hash = assetHash(path)
        local check = u32(band(vertexCount * 65537 + indexCount * 257 + hash, 0xffffffff))
        local mesh, err = decodeMeshBinary(bytes, hash, check)
        if not mesh and mod.log then
            mod.log:warn("Cannot decode mesh %s: %s", tostring(path), tostring(err))
        end
        return mesh
    end

    ----------------------------------------------------------------
    -- Renderer-agnostic asset cache
    --
    -- IMPORTANT:
    -- This cache contains DATA only:
    -- vertices, indices and ImageData.
    --
    -- It does NOT contain Voxel3D meshes, Love2D Images, Mat4 objects,
    -- ShadowMap objects or any other renderer-specific GPU resource.
    ----------------------------------------------------------------

    local assetCache = {}

    -- Map-scoped, demand-loaded character assets. This is CPU-side mesh and
    -- ImageData cache only; renderer-owned GPU meshes use weak asset keys.
    -- Do not unload RED/GREEN player assets, avoiding a hitch each doorway.
    local activeMapKey = nil

    local function playerCacheKey(key)
        return key:sub(1,18) == "assets/render/red_"
            or key:sub(1,20) == "assets/render/green_"
    end

    local function setActiveMap(mapId)
        if mapId == nil then return end
        local nextMap = tostring(mapId)
        if nextMap == "" or nextMap == activeMapKey then return end
        local previousMap = activeMapKey
        activeMapKey = nextMap
        if previousMap == nil then return end

        local mode = "map" -- fixed map-scoped asset caching
        if mode ~= "map" then return end
        local count = 0
        for key in pairs(assetCache) do
            if not playerCacheKey(key) then
                assetCache[key] = nil
                count = count + 1
            end
        end
        local animationModels = 0
        if DynamicAnimation and type(DynamicAnimation.releaseMapModels) == "function" then
            animationModels = DynamicAnimation.releaseMapModels()
        end
        if mod.log and mod.log.info then
            mod.log:info("3D character map cache: %s -> %s; %d mesh instances, %d animation models released",
                previousMap, nextMap, count, animationModels)
        end
    end


    ----------------------------------------------------------------
    -- Load texture ImageData
    ----------------------------------------------------------------

    local function loadTextureData(path)

        local bytes =
            mod:read(path)


        if not bytes then
            return nil
        end


        local fileData =
            love.filesystem.newFileData(
                bytes,
                path
            )


        local okImageData,
              imageData =

            pcall(
                love.image.newImageData,
                fileData
            )


        if not okImageData then

            mod.log:error(
                "Could not decode texture %s: %s",
                path,
                tostring(imageData)
            )

            return nil
        end


        return imageData
    end


    ----------------------------------------------------------------
    -- Palette cache key
    ----------------------------------------------------------------

    local function paletteKey(colors)

        if not colors then
            return "raw"
        end


        local parts = {}


        for i = 1, 4 do

            local c =
                colors[i]


            if c then

                parts[#parts + 1] =
                    tostring(c[1])

                parts[#parts + 1] =
                    tostring(c[2])

                parts[#parts + 1] =
                    tostring(c[3])

            else

                parts[#parts + 1] =
                    "nil"

            end

        end


        return table.concat(
            parts,
            ","
        )
    end


 ----------------------------------------------------------------
-- Resolve active character palette
--
-- Palette policy belongs to the active version resolver.
-- CharacterRuntime only requests the resolved colors.
----------------------------------------------------------------

local function resolveCharacterColors(
    sprite,
    colors
)

    return PaletteResolver.resolve(
        versionGroup,
        PaletteFX,
        sprite,
        colors
    )
end


    ----------------------------------------------------------------
    -- Recolor shared four-shade texture as ImageData
    --
    -- No love.graphics.newImage() here:
    -- GPU texture creation belongs to the active renderer.
    ----------------------------------------------------------------

    local function buildPaletteImageData(
        sourceImageData,
        colors
    )

        local width,
              height =

            sourceImageData:getDimensions()


        local output =
            love.image.newImageData(
                width,
                height
            )


        for y = 0, height - 1 do

            for x = 0, width - 1 do

                local r,
                      g,
                      b,
                      a =

                    sourceImageData:getPixel(
                        x,
                        y
                    )


                r,
                g,
                b,
                a =

                    TileRenderer.recolorSample(
                        r,
                        g,
                        b,
                        a,
                        colors
                    )


                output:setPixel(
                    x,
                    y,
                    r,
                    g,
                    b,
                    a
                )

            end

        end


        return output
    end


    ----------------------------------------------------------------
    -- Build renderer-agnostic mirrored geometry
    --
    -- X is negated and triangle winding is reversed so a renderer can
    -- safely use back-face culling on the mirrored model.
    ----------------------------------------------------------------

    local function buildMirroredMeshData(
        vertices,
        indices
    )

        local mirroredVertices = {}
        local mirroredIndices = {}


        for i, vertex in ipairs(vertices) do

            mirroredVertices[i] = {
                -vertex[1],
                vertex[2],
                vertex[3],
                vertex[4],
                vertex[5],
                vertex[6]
            }

        end


        for i = 1, #indices, 3 do

            local a =
                indices[i]

            local b =
                indices[i + 1]

            local c =
                indices[i + 2]


            mirroredIndices[#mirroredIndices + 1] =
                a

            mirroredIndices[#mirroredIndices + 1] =
                c

            mirroredIndices[#mirroredIndices + 1] =
                b

        end


        return mirroredVertices,
               mirroredIndices
    end


    ----------------------------------------------------------------
    -- Runtime rendering styles using ONE source geometry per frame.
    -- Toon/N64 changes the light bands; Low/Smooth changes vertex-light
    -- interpolation, NOT triangle count.  Low generates a faceted mesh
    -- in RAM, leaving the shipped source triangles and textures alone.
    ----------------------------------------------------------------
    local function stylizeMesh(meshData, shading, poly)
        local sourceVertices = meshData.vertices
        local sourceIndices = meshData.indices
        local function clamp(x)
            return math.max(0, math.min(1, tonumber(x) or 1))
        end
        local function band(x)
            x = clamp(x)
            if x < 0.55 then return 0.43 end
            if x < 0.82 then return 0.72 end
            return 1.0
        end
        -- Fixed directional light in character LOCAL space. This only changes
        -- shading of replacements, never the world/sun shader or geometry.
        local lx,ly,lz = 0.39,0.84,0.39
        local function faceNormal(a,b,c)
            local ax,ay,az=b[1]-a[1],b[2]-a[2],b[3]-a[3]
            local bx,by,bz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
            local x,y,z=ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx
            local size=math.sqrt(x*x+y*y+z*z)
            if size<0.00000001 then return 0,1,0 end
            return x/size,y/size,z/size
        end
        local function light(nx,ny,nz)
            -- Absolute lighting handles both mesh winding conventions in
            -- Rumble sources without blackening double-sided polygons.
            return 0.46+0.54*math.abs(nx*lx+ny*ly+nz*lz)
        end
        if shading=="smooth_lit" or shading=="toon" or shading=="toon_outline" then
            -- Rumble face-atlas geometry splits vertices at UV seams.
            -- Average incident face normals by POSITION, not vertex index,
            -- to make the shading continuous across these seams.
            local sums={}
            local vertexKeys={}
            for i,v in ipairs(sourceVertices) do
                local key=string.format("%0.3f,%0.3f,%0.3f",v[1],v[2],v[3])
                vertexKeys[i]=key
                if not sums[key] then sums[key]={0,0,0} end
            end
            for i=1,#sourceIndices-2,3 do
                local ia,ib,ic=sourceIndices[i],sourceIndices[i+1],sourceIndices[i+2]
                local a,b,c=sourceVertices[ia],sourceVertices[ib],sourceVertices[ic]
                if a and b and c then
                    local nx,ny,nz=faceNormal(a,b,c)
                    for _,idx in ipairs({ia,ib,ic}) do
                        local entry=sums[vertexKeys[idx]]
                        entry[1]=entry[1]+nx;entry[2]=entry[2]+ny;entry[3]=entry[3]+nz
                    end
                end
            end
            local vertices={}
            for i,v in ipairs(sourceVertices) do
                local entry=sums[vertexKeys[i]]
                local norm=math.sqrt(entry[1]^2+entry[2]^2+entry[3]^2)
                local factor=norm>0.00001 and light(entry[1]/norm,entry[2]/norm,entry[3]/norm) or 1
                local lit=clamp(v[6]*factor)
                if shading=="toon" or shading=="toon_outline" then lit=band(lit) end
                vertices[i]={v[1],v[2],v[3],v[4],v[5],lit}
            end
            return {vertices=vertices,indices=sourceIndices}
        end
        if poly=="low" then
            local vertices,indices,vertexMap={},{},{}
            -- Flat-shaded triangle-local vertices; keep the same geometry
            -- and stable vertexMap for any existing animation retarget.
            for i=1,#sourceIndices-2,3 do
                local ia,ib,ic=sourceIndices[i],sourceIndices[i+1],sourceIndices[i+2]
                local a,b,c=sourceVertices[ia],sourceVertices[ib],sourceVertices[ic]
                if a and b and c then
                    local lit=(a[6]+b[6]+c[6])/3
                    if shading=="toon" or shading=="toon_outline" then
                        lit=band(lit)
                    elseif shading=="low_poly" then
                        local nx,ny,nz=faceNormal(a,b,c)
                        lit=clamp(lit*light(nx,ny,nz))
                    else
                        -- Keep the exact legacy N64 lighting baseline.
                        lit=math.max(0.2, math.floor(lit*5+0.5)/5)
                    end
                    local n=#vertices
                    vertices[n+1]={a[1],a[2],a[3],a[4],a[5],lit}
                    vertices[n+2]={b[1],b[2],b[3],b[4],b[5],lit}
                    vertices[n+3]={c[1],c[2],c[3],c[4],c[5],lit}
                    indices[n+1],indices[n+2],indices[n+3]=n+1,n+2,n+3
                    vertexMap[n+1],vertexMap[n+2],vertexMap[n+3]=ia,ib,ic
                end
            end
            return {vertices=vertices,indices=indices,vertexMap=vertexMap}
        end
        if shading=="toon" or shading=="toon_outline" then
            local vertices={}
            for i,v in ipairs(sourceVertices) do
                vertices[i]={v[1],v[2],v[3],v[4],v[5],band(v[6])}
            end
            return {vertices=vertices,indices=sourceIndices}
        end
        return meshData
    end

    ----------------------------------------------------------------
    -- The returned package is renderer-agnostic.
    ----------------------------------------------------------------

    -- Additional visual-only size adjustment for the combined RED_SURF model.
    -- This is applied to *both* initial rest vertices and animated positions.
    -- It never modifies the GLB animation tracks or normal RED's size.
    -- v30.7: RED_SURF has a fixed, visual-only 50%% setting.  The earlier
    -- v30.6 size option was calibrated relative to a 30%% source baseline:
    -- displayedScale = selectedFraction / 0.30.  Preserve exactly the old
    -- 50%% selection as a constant, regardless of saved mod-manager options.
    -- Apply to both rest and animated vertices via the same existing calls.
    local function currentSurfVisualScale()
        return 5 / 3
    end

    -- A silhouette shell is a slightly expanded second copy of the SAME
    -- active GLB geometry. Its triangles are drawn with FRONT culling and
    -- a black one-pixel material. Front surfaces remain untouched, allowing
    -- double-sided source details (eyebrows/capes) to render normally.
    local OUTLINE_EXPANSION = 1.06
    local function buildToonOutline(vertices, mirrored, outline, mirroredOutline)
        outline = outline or {}
        mirroredOutline = mirroredOutline or {}
        local minX,minY,minZ = math.huge,math.huge,math.huge
        local maxX,maxY,maxZ = -math.huge,-math.huge,-math.huge
        for i=1,#vertices do
            local v=vertices[i]
            if v then
                minX=math.min(minX,v[1]); maxX=math.max(maxX,v[1])
                minY=math.min(minY,v[2]); maxY=math.max(maxY,v[2])
                minZ=math.min(minZ,v[3]); maxZ=math.max(maxZ,v[3])
            end
        end
        if minX==math.huge then return outline,mirroredOutline end
        local cx,cy,cz = (minX+maxX)*0.5,(minY+maxY)*0.5,(minZ+maxZ)*0.5
        for i,v in ipairs(vertices) do
            local x=cx+(v[1]-cx)*OUTLINE_EXPANSION
            local y=cy+(v[2]-cy)*OUTLINE_EXPANSION
            local z=cz+(v[3]-cz)*OUTLINE_EXPANSION
            local a=outline[i]
            if not a then a={0,0,0,0.5,0.5,1};outline[i]=a end
            a[1],a[2],a[3]=x,y,z
            local b=mirroredOutline[i]
            if not b then b={0,0,0,0.5,0.5,1};mirroredOutline[i]=b end
            b[1],b[2],b[3]=-x,y,z
        end
        return outline,mirroredOutline
    end

    local function loadAsset(definition)

        if not definition
            or not definition.mesh then

            return nil
        end


        local key =
            tostring(definition.mesh)
            .. "|"
            .. tostring(definition.texture)
            .. "|"
            .. tostring(definition.shading or "n64")
            .. "|"
            .. tostring(definition.poly or "low")
            .. "|".. tostring(definition.animation and definition.animation.entity or 'static')
            .. "|".. tostring(definition.animation and definition.animation.model == "red_surf" and currentSurfVisualScale() or "not-surf")


        if assetCache[key] ~= nil then

            if assetCache[key] == false then
                return nil
            end


            return assetCache[key]
        end


        local meshData =
            loadProtectedMesh(
                definition.mesh
            )


        if not meshData then

            assetCache[key] =
                false

            return nil
        end


        if not meshData.vertices
            or not meshData.indices then

            mod.log:error(
                "Invalid mesh data: %s",
                tostring(definition.mesh)
            )


            assetCache[key] =
                false

            return nil
        end


        meshData = stylizeMesh(
            meshData,
            definition.shading or "n64",
            definition.poly or "low"
        )

        -- A scale applied only on the GLB's root nodes was not enough
        -- for reliably sizing the animated fallback across render modes.
        -- Make an independent copy so the shared source mesh is unchanged.
        if definition.animation and definition.animation.model == "red_surf" then
            local k = currentSurfVisualScale()
            local adjusted = {}
            for i, vertex in ipairs(meshData.vertices) do
                adjusted[i] = {
                    vertex[1] * k, vertex[2] * k, vertex[3] * k,
                    vertex[4], vertex[5], vertex[6]
                }
            end
            meshData = {
                vertices = adjusted,
                indices = meshData.indices,
                vertexMap = meshData.vertexMap
            }
        end

        local mirroredVertices,
              mirroredIndices =

            buildMirroredMeshData(
                meshData.vertices,
                meshData.indices
            )


        -- Toon outline: model-local, animated inverted hull. The CPU vertices
        -- remain separate from the original character surface, so the N64
        -- mode and the existing single-material GPU meshes are unchanged.
        local outlineMode = definition.shading == "toon_outline"
        local outlineVertices = nil
        local outlineMirroredVertices = nil
        local outlineCenter = nil
        if outlineMode then
            outlineVertices, outlineMirroredVertices, outlineCenter =
                buildToonOutline(meshData.vertices, meshData.mirroredVertices)
        end

        local textureData =
            loadTextureData(
                definition.texture
            )


        if not textureData then

            assetCache[key] =
                false

            return nil
        end


        local asset = {

            vertices =
                meshData.vertices,

            indices =
                meshData.indices,

            mirroredVertices =
                mirroredVertices,

            mirroredIndices =
                mirroredIndices,

            textureData =
                textureData,

            -- Rumble face-baked materials have isolated per-triangle UVs.
            -- Use their crisp sampled pixels, not linear bleed between faces.
            rumbleTexture = (type(definition.texture)=="string" and
                (definition.texture:match("^assets/textures/pokemon_") ~= nil)),

            dynamicVertexMap = meshData.vertexMap,
            toonOutline = outlineMode,
            outlineVertices = outlineVertices,
            outlineMirroredVertices = outlineMirroredVertices,
            lastAnimationTag = nil,

            paletteMode =
                definition.paletteMode,

            paletteImageData =
                {}
        }


        assetCache[key] =
            asset


        mod.log:info(
            "Loaded Porygonal asset package: %s",
            tostring(definition.mesh)
        )


        return asset
    end


    ----------------------------------------------------------------
    -- Palette-aware texture DATA
    --
    -- Returns:
    --   ImageData
    --   stable cache key for the renderer's own GPU texture cache
    ----------------------------------------------------------------

    local function textureDataFor(
        asset,
        sprite,
        colors
    )

        if asset.paletteMode
            ~= "gen1" then

            return asset.textureData,
                   "raw"
        end


        local resolvedColors =
            resolveCharacterColors(
                sprite,
                colors
            )


        if not resolvedColors then

            return asset.textureData,
                   "raw"
        end


        local key =
            paletteKey(
                resolvedColors
            )


        if asset.paletteImageData[key] then

            return asset.paletteImageData[key],
                   key
        end


        local imageData =
            buildPaletteImageData(
                asset.textureData,
                resolvedColors
            )


        asset.paletteImageData[key] =
            imageData


        return imageData,
               key
    end


    ----------------------------------------------------------------
    -- Original Gen1 sprite pose -> Porygonal identity
    ----------------------------------------------------------------

    local function getSpritePose(
        sprite,
        facing,
        phase,
        flip
    )

        if not sprite
            or not sprite.def then

            return nil,
                   nil,
                   false
        end


        local def =
            sprite.def


        local frame = 0
        local mirror = false


        if (def.frames or 1) > 1 then

            if def.walker
                and phase == 1 then

                frame =
                    SR.WALK[facing]

            else

                frame =
                    SR.STAND[facing]

            end


            --------------------------------------------------------
            -- Stable orientation for the full authored 3D walk cycle.
            -- NEVER XOR the mirror with the Game Boy sprite's step flip:
            -- doing so reverses the model every step and makes Walking
            -- look jerky even when its original GLB keyframes are smooth.
            --------------------------------------------------------
            mirror = facing == "right"

        end


        return def.id,
               frame,
               mirror
    end


    ----------------------------------------------------------------
    -- Update GPU mesh directly from original glTF keyframe tracks.
    -- Do not quantize, retime, or rewrite any GLB animation.
    ----------------------------------------------------------------
    local function updateAnimatedOutline(asset,gpu)
        if not asset.toonOutline or not gpu.outlineMesh
            or not gpu.mirroredOutlineMesh then return end
        buildToonOutline(asset.vertices,asset.mirroredVertices,
            asset.outlineVertices,asset.outlineMirroredVertices)
        pcall(gpu.outlineMesh.setVertices,gpu.outlineMesh,asset.outlineVertices)
        pcall(gpu.mirroredOutlineMesh.setVertices,gpu.mirroredOutlineMesh,asset.outlineMirroredVertices)
    end

    local function animateAsset(definition, asset, gpu)
        local a=definition and definition.animation
        if not a or not asset or not gpu then return true end
        local time=tonumber(a.time) or 0
        if a.pokemonBreathing then
            -- Procedural GLB-equivalent rest-scale animation at original speed.
            -- Absolute rest vertices avoid accumulated resizing over frames.
            local phase=(time % 2.4)/2.4*math.pi*2
            local sy=1+0.07*(0.5-0.5*math.cos(phase))
            local sx=1+0.03*(0.5-0.5*math.cos(phase))
            local source=asset.breathRest
            if not source then
                source={}
                for i,v in ipairs(asset.vertices) do
                    source[i]={v[1],v[2],v[3]}
                end
                asset.breathRest=source
            end
            for i,v in ipairs(asset.vertices) do
                local r=source[i]
                if r then v[1],v[2],v[3]=r[1]*sx,r[2]*sy,r[3]*sx end
            end
            for i,v in ipairs(asset.mirroredVertices) do
                local r=source[i]
                if r then v[1],v[2],v[3]=-r[1]*sx,r[2]*sy,r[3]*sx end
            end
            gpu.mesh:setVertices(asset.vertices)
            gpu.mirroredMesh:setVertices(asset.mirroredVertices)
            updateAnimatedOutline(asset,gpu)
            return true
        end
        local pose=DynamicAnimation.evaluate(a.model,a.clip,time)
        if not pose then return false end
        local surfK = (a.model == "red_surf") and currentSurfVisualScale() or 1
        local vm=asset.dynamicVertexMap
        for i,v in ipairs(asset.vertices) do
            local p=pose[vm and vm[i] or i]
            if p then v[1],v[2],v[3]=p[1]*surfK,p[2]*surfK,p[3]*surfK end
        end
        for i,v in ipairs(asset.mirroredVertices) do
            local p=pose[vm and vm[i] or i]
            if p then v[1],v[2],v[3]=-p[1]*surfK,p[2]*surfK,p[3]*surfK end
        end
        local ok,err=pcall(gpu.mesh.setVertices,gpu.mesh,asset.vertices)
        if not ok then
            mod.log:error('GLB animation GPU update failed: %s',tostring(err))
            return false
        end
        local mok,merr=pcall(gpu.mirroredMesh.setVertices,gpu.mirroredMesh,asset.mirroredVertices)
        if not mok then
            mod.log:error('GLB mirrored animation GPU update failed: %s',tostring(merr))
            return false
        end
        updateAnimatedOutline(asset,gpu)
        return true
    end

    return {

        setActiveMap =
            setActiveMap,

        loadAsset =
            loadAsset,

        animateAsset = animateAsset,

        textureDataFor =
            textureDataFor,

        getSpritePose =
            getSpritePose
    }
end


return CharacterRuntime

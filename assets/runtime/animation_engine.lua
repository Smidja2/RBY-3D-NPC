-- GLB original-keyframe animation evaluator for Gen1Recomp / LOVE LuaJIT.
-- The GLBs and keyframe values are never edited or baked into frame meshes.
-- Supports LINEAR/STEP/CUBICSPLINE, joint skinning, and animated morph targets.
local mod, loadLocalModule = ...
local M = {}
mod.log:info('NPC animation engine: pure Lua decoder active (no FFI)')
-- Pure-Lua decoder: Gen1Recomp blocks ffi inside mod sandboxes.
-- The exported .dat files remain untouched and retain original float32 data.
local function u16(s, i)
    local a,b=s:byte(i,i+1)
    if not b then return nil end
    return a+b*256
end
local function u32(s, i)
    local a,b,c,d=s:byte(i,i+3)
    if not d then return nil end
    return a+b*256+c*65536+d*16777216
end
local function f32(s,i)
    local bits=u32(s,i)
    if not bits then return nil end
    local negative=bits>=2147483648 and -1 or 1
    local exponent=math.floor(bits/8388608)%256
    local mantissa=bits%8388608
    if exponent==255 then
        if mantissa>0 then return 0/0 end
        return negative*math.huge
    end
    if exponent==0 then return negative*mantissa*2^-149 end
    return negative*(1+mantissa/8388608)*2^(exponent-127)
end
-- Struct NPCVertex is packed 36 bytes: 3 floats, 4 uint16, 4 floats.
local function unpackVertices(s,n)
    local vertices={}
    for v=1,n do
        local i=5+(v-1)*36
        local p={f32(s,i),f32(s,i+4),f32(s,i+8)}
        local j={u16(s,i+12),u16(s,i+14),u16(s,i+16),u16(s,i+18)}
        local w={f32(s,i+20),f32(s,i+24),f32(s,i+28),f32(s,i+32)}
        if not w[4] then return nil end
        vertices[v]={p=p,joints=j,weights=w}
    end
    return vertices
end
local MODEL={}
local abs,sqrt,sin,acos=math.abs,math.sqrt,math.sin,math.acos
local min,max,floor=math.min,math.max,math.floor
local function ident()return {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1}end
local function mul(a,b)
    local out={}
    for c=0,3 do
        local v=c*4
        for r=1,4 do
            out[v+r]=a[r]*b[v+1]+a[r+4]*b[v+2]+a[r+8]*b[v+3]+a[r+12]*b[v+4]
        end
    end
    return out
end
local function compose(t,q,s)
    local x,y,z,w=q[1],q[2],q[3],q[4]
    local sx,sy,sz=s[1],s[2],s[3]
    local xx,yy,zz=x*x,y*y,z*z
    local xy,xz,yz=x*y,x*z,y*z
    local xw,yw,zw=x*w,y*w,z*w
    return {
        (1-2*(yy+zz))*sx,2*(xy+zw)*sx,2*(xz-yw)*sx,0,
        2*(xy-zw)*sy,(1-2*(xx+zz))*sy,2*(yz+xw)*sy,0,
        2*(xz+yw)*sz,2*(yz-xw)*sz,(1-2*(xx+yy))*sz,0,
        t[1],t[2],t[3],1
    }
end
local function normalize(q)
    local v=sqrt(q[1]^2+q[2]^2+q[3]^2+q[4]^2)
    if v<1e-10 then return {0,0,0,1}end
    return {q[1]/v,q[2]/v,q[3]/v,q[4]/v}
end
local function interp(channel,t)
    local times=channel.times; local count=#times
    if count==0 then return nil end
    local n=channel.components;local mode=channel.interp
    local values=channel.values
    if count==1 then
        local out={};local start= mode=='CUBICSPLINE' and n+1 or 1
        for j=1,n do out[j]=values[start+j-1]end
        return out
    end
    local lo,hi=1,count
    while lo+1<hi do
        local mid=floor((lo+hi)*.5)
        if t>=times[mid] then lo=mid else hi=mid end
    end
    if t<times[1] then lo=1 elseif t>=times[count] then lo=count-1 end
    local delta=times[lo+1]-times[lo]
    local a=delta>0 and max(0,min(1,(t-times[lo])/delta)) or 0
    if mode=='STEP' then a=0 end
    local o={}
    local offset1,offset2
    if mode=='CUBICSPLINE' then
        offset1=(lo-1)*n*3+n
        offset2=lo*n*3+n
        local h00=2*a^3-3*a^2+1
        local h10=a^3-2*a^2+a
        local h01=-2*a^3+3*a^2
        local h11=a^3-a^2
        for j=1,n do
            local v1=values[offset1+j]
            local v2=values[offset2+j]
            local tangent1=values[offset1+n+j]
            local tangent2=values[offset2-n+j]
            o[j]=h00*v1+h10*delta*tangent1+h01*v2+h11*delta*tangent2
        end
    else
        offset1=(lo-1)*n;offset2=lo*n
        if channel.path=='rotation' and mode~='STEP' then
            local dot=0
            for j=1,4 do dot=dot+values[offset1+j]*values[offset2+j]end
            local sign=dot<0 and -1 or 1
            dot=min(1,max(-1,dot*sign))
            local ka,kb=1-a,a
            if dot<0.9995 then
                local theta=acos(dot)
                local st=sin(theta)
                ka=sin((1-a)*theta)/st;kb=sin(a*theta)/st
            end
            for j=1,4 do o[j]=values[offset1+j]*ka+values[offset2+j]*sign*kb end
        else
            for j=1,n do
                local x=values[offset1+j];local y=values[offset2+j]
                o[j]=x*(1-a)+y*a
            end
        end
    end
    if channel.path=='rotation' then return normalize(o)end
    return o
end
local function load(name)
    local cached=MODEL[name]
    if cached then return cached end
    local meta=loadLocalModule('assets/runtime/'..name..'.lua')
    if not meta then return nil end
    local bytes=mod:read('assets/runtime/'..name..'.dat')
    if not bytes or #bytes<4 then
        mod.log:error('Missing animated model binary: %s',name)
        return nil
    end
    local count=u32(bytes,1)
    if count~=meta.verts then
        mod.log:error('Invalid vertex count for %s: %d vs %d',name,count,meta.verts)
        return nil
    end
    local verts=unpackVertices(bytes,count)
    if not verts then
        mod.log:error('Could not decode vertices for %s', name)
        return nil
    end
    local model={metadata=meta,bytes=bytes,vertices=verts,clips={}}
    for _,c in ipairs(meta.animations) do model.clips[c.name]=c end
    -- The appended secondary rig belongs to Red, NOT to a second NPC/model.
    -- The 1023 vertex positions and indices are shared; walk/run skinning
    -- uses the embedded V3 joint hierarchy, leaving original idles untouched.
    if name == "red" and meta.motionRig then
        local motionBytes = bytes:sub(5+count*36)
        local motionCount = u32(motionBytes,1)
        if motionCount == meta.motionRig.verts and motionCount == count then
            local motionVertices = unpackVertices(motionBytes, motionCount)
            if motionVertices then
                local motionModel = {metadata=meta.motionRig,bytes=motionBytes,vertices=motionVertices,clips={}}
                for _,c in ipairs(meta.motionRig.animations) do motionModel.clips[c.name]=c end
                model.motionRig=motionModel
            end
        end
        if not model.motionRig then
            mod.log:error('Embedded Red walk/run rig missing or invalid')
        end
    end
    MODEL[name]=model
    return model
end
-- The player is present on every map; all other rigged models can be
-- reloaded when first visible after a map transition.
function M.releaseMapModels()
    local released = 0
    for name in pairs(MODEL) do
        local playerModel = name == "red" or name == "green"
            or name:sub(1,4) == "red_" or name:sub(1,6) == "green_"
        if not playerModel then
            MODEL[name] = nil
            released = released + 1
        end
    end
    return released
end
M.hasRuntime=true
function M.evaluate(name,clipName,time)
    -- Red keeps its original model for idle/special clips; the V3 motion rig
    -- has been integrated into the primary Red resource for walking/running.
    if name == "red" then
        if clipName == "Walking" then clipName = "Walk"
        elseif clipName == "Running" then clipName = "Run" end
    end
    local model=load(name)
    if not model then return nil end
    if name == "red" and (clipName == "Walk" or clipName == "Run") then
        if not model.motionRig then return nil end
        model=model.motionRig
    end
    local g=model.metadata
    local clip=model.clips[clipName]
    local localTime=0
    if clip and clip.duration and clip.duration>0 then localTime=(time or 0)%clip.duration end
    local poses={}
    if clip then
        for _,ch in ipairs(clip.channels) do
            local value=interp(ch,localTime)
            if value then
                poses[ch.node]=poses[ch.node] or {}
                poses[ch.node][ch.path]=value
            end
        end
    end
    local world={}
    local function worldFor(i)
        if world[i] then return world[i] end
        local node=g.nodes[i]; local sample=poses[i] or {}
        local localmat
        if node.matrix and not sample.translation and not sample.rotation and not sample.scale then
            localmat=node.matrix
        else
            localmat=compose(sample.translation or node.translation,sample.rotation or node.rotation,sample.scale or node.scale)
        end
        if node.parent>0 then localmat=mul(worldFor(node.parent),localmat) end
        world[i]=localmat
        return localmat
    end
    for i=1,#g.nodes do worldFor(i)end
    local jointMats={}
    for i,skin in ipairs(g.skins)do
        local mm={}
        for j,nodeId in ipairs(skin.joints) do
            mm[j]=mul(world[nodeId],skin.inverse[j])
        end
        jointMats[i]=mm
    end
    local vertices=model.vertices
    local result={}
    local scale=g.scale
    local foot=g.feet
    for _,seg in ipairs(g.segments)do
        local morph=seg.morph
        local pose=poses[seg.node]
        local mw=(pose and pose.weights) or seg.weights
        local skin=seg.skin>0 and jointMats[seg.skin] or nil
        local baseWorld=world[seg.node]
        local morphStart=morph>0 and (seg.morphOffset+1) or nil
        for k=0,seg.count-1 do
            local idx=seg.start+k
            local v=vertices[idx]
            local x,y,z=v.p[1],v.p[2],v.p[3]
            if morphStart then
                for mt=0,morph-1 do
                    local w=mw[mt+1] or 0
                    if w~=0 then
                        local d=(mt*seg.count+k)*3
                        x=x+w*f32(model.bytes,morphStart+d*4)
                        y=y+w*f32(model.bytes,morphStart+(d+1)*4)
                        z=z+w*f32(model.bytes,morphStart+(d+2)*4)
                    end
                end
            end
            local ox,oy,oz
            if skin then
                ox,oy,oz=0,0,0
                local weightsum=0
                for j=1,4 do weightsum=weightsum+v.weights[j] end
                if weightsum<=1e-9 then weightsum=1 end
                for j=1,4 do
                    local w=v.weights[j]/weightsum
                    if w>1e-8 then
                        local m=skin[v.joints[j]+1]
                        if m then
                            ox=ox+w*(m[1]*x+m[5]*y+m[9]*z+m[13])
                            oy=oy+w*(m[2]*x+m[6]*y+m[10]*z+m[14])
                            oz=oz+w*(m[3]*x+m[7]*y+m[11]*z+m[15])
                        end
                    end
                end
            else
                local m=baseWorld
                ox=m[1]*x+m[5]*y+m[9]*z+m[13]
                oy=m[2]*x+m[6]*y+m[10]*z+m[14]
                oz=m[3]*x+m[7]*y+m[11]*z+m[15]
            end
            result[idx]={ox*scale,(oy-foot)*scale,oz*scale}
        end
    end
    return result
end
return M

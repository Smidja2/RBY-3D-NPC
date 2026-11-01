-- V44: Exact Red/Blue and Yellow chair-object whitelist from the original
-- map block/tile audit.  These are NOT inferred from STAY movement.
-- This module is data-only; it does not place, teleport, or create NPCs.
local Seated={}
local seats={RB={},Y={}}
local names={RB={},Y={}}
local function add(version,map,x,y,object,sprite,base,facing,category,clip)
    local row={map=map,x=x,y=y,objectId=object,spriteId=sprite,
        base=base,facing=facing,category=category,clip=clip,
        identity=version..":"..map..":"..object}
    seats[version][map..":"..x..":"..y]=row
    names[version][map..":"..object]=row
end
add("RB","blueshouse",2,3,"BLUESHOUSE_DAISY_SITTING","SPRITE_DAISY","blue_sis","right","house","Sit")
add("RB","ceruleantradehouse",5,4,"CERULEANTRADEHOUSE_GRANNY","SPRITE_GRANNY","old_woman","left","house","Sit")
add("RB","copycatshouse1f",5,4,"COPYCATSHOUSE1F_MIDDLE_AGED_MAN","SPRITE_MIDDLE_AGED_MAN","gentleman","left","house","Sit")
add("RB","daycare",2,3,"DAYCARE_GENTLEMAN","SPRITE_GENTLEMAN","gentleman","right","house","Sit")
add("RB","fuchsiabillsgrandpashouse",2,3,"FUCHSIABILLSGRANDPASHOUSE_MIDDLE_AGED_WOMAN","SPRITE_MIDDLE_AGED_WOMAN","middle_age_woman_new","right","house","Sit")
add("RB","lavendercubonehouse",2,4,"LAVENDERCUBONEHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","lass","right","house","Sit")
add("RB","mrpsychicshouse",5,3,"MRPSYCHICSHOUSE_MR_PSYCHIC","SPRITE_FISHING_GURU","fisherman","left","house","Sit")
add("RB","nameratershouse",5,3,"NAMERATERSHOUSE_NAME_RATER","SPRITE_SILPH_PRESIDENT","old_guy2","left","house","Sit")
add("RB","pewterspeechhouse",2,3,"PEWTERSPEECHHOUSE_GAMBLER","SPRITE_GAMBLER","gambler","right","house","Sit")
add("RB","pokemonfanclub",1,3,"POKEMONFANCLUB_SEEL_FAN","SPRITE_GIRL","beauty","right","fan_human","Sit")
add("RB","pokemonfanclub",6,3,"POKEMONFANCLUB_PIKACHU_FAN","SPRITE_FISHER","fisherman","left","fan_human","Sit")
add("RB","pokemonfanclub",1,4,"POKEMONFANCLUB_SEEL","SPRITE_SEEL","pokemon_seel","right","fan_pet","")
add("RB","pokemonfanclub",6,4,"POKEMONFANCLUB_PIKACHU","SPRITE_FAIRY","pokemon_pikachu","left","fan_pet","")
add("RB","redshouse1f",5,4,"REDSHOUSE1F_MOM","SPRITE_MOM","red_mom","left","house","Sit")
add("RB","route12superrodhouse",2,4,"ROUTE12SUPERRODHOUSE_FISHING_GURU","SPRITE_FISHING_GURU","fisherman","right","house","Sit")
add("RB","route16flyhouse",2,3,"ROUTE16FLYHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","beauty","right","house","Sit")
add("RB","route2tradehouse",2,4,"ROUTE2TRADEHOUSE_SCIENTIST","SPRITE_SCIENTIST","scientist_m","right","house","Sit")
add("RB","saffronpidgeyhouse",2,3,"SAFFRONPIDGEYHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","lass","right","house","Sit")
add("RB","vermilionoldrodhouse",2,4,"VERMILIONOLDRODHOUSE_FISHING_GURU","SPRITE_FISHING_GURU","fisherman","right","house","Sit")
add("RB","vermilionpidgeyhouse",5,3,"VERMILIONPIDGEYHOUSE_YOUNGSTER","SPRITE_YOUNGSTER","youngster","left","house","Sit")
add("RB","viridiannicknamehouse",5,3,"VIRIDIANNICKNAMEHOUSE_BALDING_GUY","SPRITE_BALDING_GUY","boy","none","house","Sit")
add("RB","viridianschoolhouse",3,5,"VIRIDIANSCHOOLHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","little_girl_new","up","house","Sit")
add("Y","blueshouse",2,3,"BLUESHOUSE_DAISY_SITTING","SPRITE_DAISY","blue_sis","right","house","Sit")
add("Y","copycatshouse1f",5,4,"COPYCATSHOUSE1F_MIDDLE_AGED_MAN","SPRITE_MIDDLE_AGED_MAN","gentleman","left","house","Sit")
add("Y","daycare",2,3,"DAYCARE_GENTLEMAN","SPRITE_GENTLEMAN","gentleman","right","house","Sit")
add("Y","fuchsiabillsgrandpashouse",2,3,"FUCHSIABILLSGRANDPASHOUSE_MIDDLE_AGED_WOMAN","SPRITE_MIDDLE_AGED_WOMAN","middle_age_woman_new","right","house","Sit")
add("Y","lavendercubonehouse",2,4,"LAVENDERCUBONEHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","lass","right","house","Sit")
add("Y","mrpsychicshouse",5,3,"MRPSYCHICSHOUSE_MR_PSYCHIC","SPRITE_FISHING_GURU","fisherman","left","house","Sit")
add("Y","nameratershouse",5,3,"NAMERATERSHOUSE_NAME_RATER","SPRITE_SILPH_PRESIDENT","old_guy2","left","house","Sit")
add("Y","pewterspeechhouse",2,3,"PEWTERSPEECHHOUSE_GAMBLER","SPRITE_GAMBLER","gambler","right","house","Sit")
add("Y","pokemonfanclub",1,3,"POKEMONFANCLUB_SEEL_FAN","SPRITE_GIRL","beauty","right","fan_human","Sit")
add("Y","pokemonfanclub",6,3,"POKEMONFANCLUB_CLEFAIRY_FAN","SPRITE_FISHER","fisherman","left","fan_human","Sit")
add("Y","pokemonfanclub",1,4,"POKEMONFANCLUB_SEEL","SPRITE_SEEL","pokemon_seel","right","fan_pet","")
add("Y","pokemonfanclub",6,4,"POKEMONFANCLUB_CLEFAIRY","SPRITE_CLEFAIRY","pokemon_clefairy","left","fan_pet","")
add("Y","redshouse1f",5,4,"REDSHOUSE1F_MOM","SPRITE_MOM","red_mom","left","house","Sit")
add("Y","route12superrodhouse",2,4,"ROUTE12SUPERRODHOUSE_FISHING_GURU","SPRITE_FISHING_GURU","fisherman","right","house","Sit")
add("Y","route16flyhouse",2,3,"ROUTE16FLYHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","beauty","right","house","Sit")
add("Y","route2tradehouse",2,4,"ROUTE2TRADEHOUSE_SCIENTIST","SPRITE_SCIENTIST","scientist_m","right","house","Sit")
add("Y","saffronpidgeyhouse",2,3,"SAFFRONPIDGEYHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","lass","right","house","Sit")
add("Y","vermilionoldrodhouse",2,4,"VERMILIONOLDRODHOUSE_FISHING_GURU","SPRITE_FISHING_GURU","fisherman","right","house","Sit")
add("Y","vermilionpidgeyhouse",5,3,"VERMILIONPIDGEYHOUSE_YOUNGSTER","SPRITE_YOUNGSTER","youngster","left","house","Sit")
add("Y","viridiannicknamehouse",5,3,"VIRIDIANNICKNAMEHOUSE_BALDING_GUY","SPRITE_BALDING_GUY","boy","none","house","Sit")
add("Y","viridianschoolhouse",3,5,"VIRIDIANSCHOOLHOUSE_BRUNETTE_GIRL","SPRITE_BRUNETTE_GIRL","little_girl_new","up","house","Sit")

local function slug(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
local function hasValidSprite(row, sprite)
    return row and (sprite==nil or sprite=="" or tostring(sprite)==row.spriteId)
end
-- Both a map identity AND a matching source object/coordinate are required.
-- Sprite identity is also checked when available to prevent other entities
-- on a temporarily reused coordinate from being seated.
function Seated.resolve(isYellow,mapId,cellX,cellY,spriteId,objectId)
    local version=isYellow and "Y" or "RB"
    local map=slug(mapId)
    if map=="" then return nil end
    local obj=tostring(objectId or ""):upper()
    if obj~="" then
        local byName=names[version][map..":"..obj]
        if hasValidSprite(byName,spriteId) then
            -- Valid named objects retain their authored identity even when
            -- the renderer momentarily omits their position.
            if type(cellX)~="number" or type(cellY)~="number" or
                (math.floor(cellX)==byName.x and math.floor(cellY)==byName.y) then
                return byName
            end
        end
    end
    if type(cellX)~="number" or type(cellY)~="number" then return nil end
    local row=seats[version][map..":"..math.floor(cellX)..":"..math.floor(cellY)]
    if hasValidSprite(row,spriteId) then return row end
    return nil
end
function Seated.count(version)
    local n=0
    for _ in pairs(seats[version] or {}) do n=n+1 end
    return n
end
return Seated

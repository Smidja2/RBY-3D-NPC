-- RBY 3D NPC: optional species-true HM Fly mount bridge.
-- This module does NOT provide a second trajectory. fly_choreography.lua
-- remains the sole source of position, facing and timing.
-- All providers are optional; the original Pidgeot is always available.
local M={version=5}
local speciesNames={
  [1]='bulbasaur',[2]='ivysaur',[3]='venusaur',[4]='charmander',[5]='charmeleon',[6]='charizard',[7]='squirtle',
  [8]='wartortle',[9]='blastoise',[10]='caterpie',[11]='metapod',[12]='butterfree',[13]='weedle',[14]='kakuna',
  [15]='beedrill',[16]='pidgey',[17]='pidgeotto',[18]='pidgeot',[19]='rattata',[20]='raticate',[21]='spearow',
  [22]='fearow',[23]='ekans',[24]='arbok',[25]='pikachu',[26]='raichu',[27]='sandshrew',[28]='sandslash',
  [29]='nidoranf',[30]='nidorina',[31]='nidoqueen',[32]='nidoranm',[33]='nidorino',[34]='nidoking',[35]='clefairy',
  [36]='clefable',[37]='vulpix',[38]='ninetales',[39]='jigglypuff',[40]='wigglytuff',[41]='zubat',[42]='golbat',
  [43]='oddish',[44]='gloom',[45]='vileplume',[46]='paras',[47]='parasect',[48]='venonat',[49]='venomoth',
  [50]='diglett',[51]='dugtrio',[52]='meowth',[53]='persian',[54]='psyduck',[55]='golduck',[56]='mankey',
  [57]='primeape',[58]='growlithe',[59]='arcanine',[60]='poliwag',[61]='poliwhirl',[62]='poliwrath',[63]='abra',
  [64]='kadabra',[65]='alakazam',[66]='machop',[67]='machoke',[68]='machamp',[69]='bellsprout',[70]='weepinbell',
  [71]='victreebel',[72]='tentacool',[73]='tentacruel',[74]='geodude',[75]='graveler',[76]='golem',[77]='ponyta',
  [78]='rapidash',[79]='slowpoke',[80]='slowbro',[81]='magnemite',[82]='magneton',[83]='farfetchd',[84]='doduo',
  [85]='dodrio',[86]='seel',[87]='dewgong',[88]='grimer',[89]='muk',[90]='shellder',[91]='cloyster',
  [92]='gastly',[93]='haunter',[94]='gengar',[95]='onix',[96]='drowzee',[97]='hypno',[98]='krabby',
  [99]='kingler',[100]='voltorb',[101]='electrode',[102]='exeggcute',[103]='exeggutor',[104]='cubone',[105]='marowak',
  [106]='hitmonlee',[107]='hitmonchan',[108]='lickitung',[109]='koffing',[110]='weezing',[111]='rhyhorn',[112]='rhydon',
  [113]='chansey',[114]='tangela',[115]='kangaskhan',[116]='horsea',[117]='seadra',[118]='goldeen',[119]='seaking',
  [120]='staryu',[121]='starmie',[122]='mrmime',[123]='scyther',[124]='jynx',[125]='electabuzz',[126]='magmar',
  [127]='pinsir',[128]='tauros',[129]='magikarp',[130]='gyarados',[131]='lapras',[132]='ditto',[133]='eevee',
  [134]='vaporeon',[135]='jolteon',[136]='flareon',[137]='porygon',[138]='omanyte',[139]='omastar',[140]='kabuto',
  [141]='kabutops',[142]='aerodactyl',[143]='snorlax',[144]='articuno',[145]='zapdos',[146]='moltres',[147]='dratini',
  [148]='dragonair',[149]='dragonite',[150]='mewtwo',[151]='mew',[152]='chikorita',[153]='bayleef',[154]='meganium',
  [155]='cyndaquil',[156]='quilava',[157]='typhlosion',[158]='totodile',[159]='croconaw',[160]='feraligatr',[161]='sentret',
  [162]='furret',[163]='hoothoot',[164]='noctowl',[165]='ledyba',[166]='ledian',[167]='spinarak',[168]='ariados',
  [169]='crobat',[170]='chinchou',[171]='lanturn',[172]='pichu',[173]='cleffa',[174]='igglybuff',[175]='togepi',
  [176]='togetic',[177]='natu',[178]='xatu',[179]='mareep',[180]='flaaffy',[181]='ampharos',[182]='bellossom',
  [183]='marill',[184]='azumarill',[185]='sudowoodo',[186]='politoed',[187]='hoppip',[188]='skiploom',[189]='jumpluff',
  [190]='aipom',[191]='sunkern',[192]='sunflora',[193]='yanma',[194]='wooper',[195]='quagsire',[196]='espeon',
  [197]='umbreon',[198]='murkrow',[199]='slowking',[200]='misdreavus',[201]='unown',[202]='wobbuffet',[203]='girafarig',
  [204]='pineco',[205]='forretress',[206]='dunsparce',[207]='gligar',[208]='steelix',[209]='snubbull',[210]='granbull',
  [211]='qwilfish',[212]='scizor',[213]='shuckle',[214]='heracross',[215]='sneasel',[216]='teddiursa',[217]='ursaring',
  [218]='slugma',[219]='magcargo',[220]='swinub',[221]='piloswine',[222]='corsola',[223]='remoraid',[224]='octillery',
  [225]='delibird',[226]='mantine',[227]='skarmory',[228]='houndour',[229]='houndoom',[230]='kingdra',[231]='phanpy',
  [232]='donphan',[233]='porygon2',[234]='stantler',[235]='smeargle',[236]='tyrogue',[237]='hitmontop',[238]='smoochum',
  [239]='elekid',[240]='magby',[241]='miltank',[242]='blissey',[243]='raikou',[244]='entei',[245]='suicune',
  [246]='larvitar',[247]='pupitar',[248]='tyranitar',[249]='lugia',[250]='hooh',[251]='celebi',[252]='treecko',
  [253]='grovyle',[254]='sceptile',[255]='torchic',[256]='combusken',[257]='blaziken',[258]='mudkip',[259]='marshtomp',
  [260]='swampert',[261]='poochyena',[262]='mightyena',[263]='zigzagoon',[264]='linoone',[265]='wurmple',[266]='silcoon',
  [267]='beautifly',[268]='cascoon',[269]='dustox',[270]='lotad',[271]='lombre',[272]='ludicolo',[273]='seedot',
  [274]='nuzleaf',[275]='shiftry',[276]='taillow',[277]='swellow',[278]='wingull',[279]='pelipper',[280]='ralts',
  [281]='kirlia',[282]='gardevoir',[283]='surskit',[284]='masquerain',[285]='shroomish',[286]='breloom',[287]='slakoth',
  [288]='vigoroth',[289]='slaking',[290]='nincada',[291]='ninjask',[292]='shedinja',[293]='whismur',[294]='loudred',
  [295]='exploud',[296]='makuhita',[297]='hariyama',[298]='azurill',[299]='nosepass',[300]='skitty',[301]='delcatty',
  [302]='sableye',[303]='mawile',[304]='aron',[305]='lairon',[306]='aggron',[307]='meditite',[308]='medicham',
  [309]='electrike',[310]='manectric',[311]='plusle',[312]='minun',[313]='volbeat',[314]='illumise',[315]='roselia',
  [316]='gulpin',[317]='swalot',[318]='carvanha',[319]='sharpedo',[320]='wailmer',[321]='wailord',[322]='numel',
  [323]='camerupt',[324]='torkoal',[325]='spoink',[326]='grumpig',[327]='spinda',[328]='trapinch',[329]='vibrava',
  [330]='flygon',[331]='cacnea',[332]='cacturne',[333]='swablu',[334]='altaria',[335]='zangoose',[336]='seviper',
  [337]='lunatone',[338]='solrock',[339]='barboach',[340]='whiscash',[341]='corphish',[342]='crawdaunt',[343]='baltoy',
  [344]='claydol',[345]='lileep',[346]='cradily',[347]='anorith',[348]='armaldo',[349]='feebas',[350]='milotic',
  [351]='castform',[352]='kecleon',[353]='shuppet',[354]='banette',[355]='duskull',[356]='dusclops',[357]='tropius',
  [358]='chimecho',[359]='absol',[360]='wynaut',[361]='snorunt',[362]='glalie',[363]='spheal',[364]='sealeo',
  [365]='walrein',[366]='clamperl',[367]='huntail',[368]='gorebyss',[369]='relicanth',[370]='luvdisc',[371]='bagon',
  [372]='shelgon',[373]='salamence',[374]='beldum',[375]='metang',[376]='metagross',[377]='regirock',[378]='regice',
  [379]='registeel',[380]='latias',[381]='latios',[382]='kyogre',[383]='groudon',[384]='rayquaza',[385]='jirachi',
  [386]='deoxys'
}
local speciesId={}
for id,name in pairs(speciesNames) do speciesId[name]=id end
local function normalize(v)
  if type(v)=='table' then
    return normalize(v.dex or v.dexNo or v.dexId or v.nationalDex or
      v.speciesId or v.species or v.pokemon or v.mon or v.name)
  end
  if type(v)=='number' then
    if v>=1 and v<=386 then return math.floor(v) end
    return nil
  end
  if type(v)~='string' then return nil end
  local s=v:lower():gsub('^pokemon_',''):gsub('[^%w]','')
  return tonumber(s) or speciesId[s]
end
M.normalize=normalize
local function gameFor(mod)
  -- Ranch's own follower integration gets party species from
  -- require("src.core.Game").save.party.  mod.game alone does not always
  -- reference that singleton at the moment an HM is activated.
  local ok,Game=pcall(require,"src.core.Game")
  if ok and type(Game)=="table" then return Game end
  return mod and mod.game
end
local function partyFor(mod,world)
  local Game=gameFor(mod)
  local save=Game and Game.save
  if type(save)=="table" and type(save.party)=="table" then return save.party end
  if mod and mod.world and type(mod.world.party)=='function' then
    local ok,p=pcall(mod.world.party,mod.world)
    if ok and type(p)=='table' then return p end
  end
  return (world and (world.party or (world.game and world.game.party)))
    or (save and (save.pokemon and save.pokemon.party))
    or (Game and Game.party)
end
local function dexFor(mod,mon)
  local id=normalize(mon)
  if id then return id end
  local Game=gameFor(mod)
  local pokemon=Game and Game.data and Game.data.pokemon
  local name=type(mon)=="table" and mon.species or mon
  if type(pokemon)=="table" and name~=nil then
    local def=pokemon[name] or pokemon[tostring(name):upper()]
    if type(def)=="table" then return normalize(def.dex or def.nationalDex or def.id) end
  end
  return nil
end
local function partyMember(party,slot)
  if type(party)~='table' then return nil end
  if type(party.pokemon)=='table' then party=party.pokemon end
  if type(party.members)=='table' then party=party.members end
  if type(slot)=='number' then
    if party[slot] then return party[slot] end
    if slot>=0 and slot<=5 then return party[slot+1] end
  end
  return nil
end
-- Gen1Recomp's PartyMenu owns the selected mon (`party[self.index]`),
-- but sends ONLY mapId to OverworldState.flyTo. The vanilla flyAnim state
-- consequently does not know who was picked. Capture at the TownMap onFly
-- callback boundary, after flyTo has actually armed a departure.
local selectedFlight=nil
-- The vanilla PartyMenu.update selects Fly before opening TownMap.
-- It clears self.submenu before Screens.push, so wrapping Screens.push is
-- not enough to reliably identify the actual selected party member across
-- different UI wrappers. Observe the genuine party-menu UPDATE instead.
local selectedFlight=nil

local function activeWorld(world)
  local ok,Game=pcall(require,'src.core.Game')
  local live=ok and type(Game)=='table' and Game.overworld or nil
  if type(live)=='table' then return live end
  return type(world)=='table' and (world.overworld or world) or nil
end

function M.captureSelection(mod,world,mon,slot)
  local live=activeWorld(world)
  if not (live and (live.flyDest or live.flyFade or live.flyAnim)) then
    return false -- cancelled / rejected / still in destination picker
  end
  if type(mon)~='table' then return false end
  local party=partyFor(mod,live)
  if type(party)=='table' then
    local p=party.pokemon or party.members or party
    if type(slot)~='number' or p[slot]~=mon then
      if mod and mod.log and mod.log.warn then
        mod.log:warn('NPC HM Fly: chosen party member changed before confirmation; using Pidgeot')
      end
      return false
    end
  end
  local dex=dexFor(mod,mon)
  selectedFlight={world=live,mon=mon,slot=slot,species=dex}
  if mod and mod.log and mod.log.info then
    mod.log:info('NPC HM Fly: confirmed party slot %d species %s dex %s',slot,
      tostring(mon.species),tostring(dex))
  end
  return true
end

function M.installSelectionHook(mod)
  local ok,PartyMenu=pcall(require,'src.ui.PartyMenu')
  if not (ok and type(PartyMenu)=='table' and type(PartyMenu.update)=='function') then
    if mod and mod.log and mod.log.warn then
      mod.log:warn('NPC HM Fly: PartyMenu.update unavailable; exact-selection hook NOT installed')
    end
    return false
  end
  local existing=PartyMenu._rbyHmFlyExactUserHook
  if type(existing)=='table' and existing.wrapper==PartyMenu.update then
    existing.provider=M
    existing.mod=mod
    return true -- hot reload: refresh without nesting wrappers
  end
  local nativeUpdate=PartyMenu.update
  local hook={provider=M,mod=mod}
  hook.wrapper=function(self,...)
    local game=self and self.game
    local stack=game and game.stack
    local topBefore=stack and type(stack.top)=='function' and stack:top() or nil
    local entry=self and self.submenu and self.subItems
      and self.subItems[self.subIndex] or nil
    local eligible=topBefore==self and type(entry)=='table' and entry.action=='fly'
      and not self.battle and type(self.index)=='number'
    local slot=eligible and self.index or nil
    local party=eligible and (self.party or (game.save and game.save.party)) or nil
    local mon=type(party)=='table' and party[slot] or nil
    -- Let the game perform ALL its native badge/outdoor checks and build the
    -- destination picker. Do not duplicate / consume input:wasPressed('a').
    local results={nativeUpdate(self,...)}
    if eligible and mon and stack and type(stack.top)=='function' then
      local town=stack:top()
      if town~=topBefore and type(town)=='table' and town.screenId=='TownMap'
          and town.fly==true and type(town.onFly)=='function'
          and not town._rbyExactFlyWrapped then
        local nativeOnFly=town.onFly
        town._rbyExactFlyWrapped=true
        -- Capture only on CONFIRMED destination, after vanilla flyTo has
        -- actually armed the HM animation. B/cancel never captures a slot.
        town.onFly=function(mapId,...)
          local out={nativeOnFly(mapId,...)}
          if hook.provider then
            hook.provider.captureSelection(hook.mod,
              game and game.overworld,mon,slot)
          end
          return (unpack or table.unpack)(out)
        end
        if hook.mod and hook.mod.log and hook.mod.log.info then
          hook.mod.log:info('NPC HM Fly: bound TownMap to party slot %d (%s)',
            slot,tostring(mon.species))
        end
      end
    end
    return (unpack or table.unpack)(results)
  end
  PartyMenu.update=hook.wrapper
  PartyMenu._rbyHmFlyExactUserHook=hook
  if mod and mod.log and mod.log.info then
    mod.log:info('NPC HM Fly: PartyMenu.update exact-user capture installed')
  end
  return true
end

local function explicitMonOrSlot(mod,world,anim)
  -- Third-party Fly actions may explicitly expose the user even when the
  -- vanilla PartyMenu is bypassed. Honour only explicit user/slot fields.
  if type(anim)~='table' then return nil,nil end
  local party=partyFor(mod,world)
  local slot=anim.partySlot or anim.sourceSlot or anim.userSlot
    or anim.monSlot or anim.pokemonSlot
  if type(slot)=='number' and slot==math.floor(slot) and slot>=1 and slot<=6 then
    local p=partyMember(party,slot)
    return p,'native-user-slot-'..slot
  end
  for _,field in ipairs({'userPokemon','flyPokemon','selectedPokemon',
      'userMon','flyMon','sourceMon','user','source'}) do
    local mon=anim[field]
    if mon~=nil then
      return mon,'native-'..field
    end
  end
  return nil,nil
end

function M.speciesFromFly(mod,world,anim)
  local pending=selectedFlight
  selectedFlight=nil -- consume once; stale menu selections never bleed into new Fly
  local live=activeWorld(world)
  if pending and live and pending.world==live then
    local party=partyFor(mod,live)
    local p=type(party)=='table' and (party.pokemon or party.members or party) or nil
    if not p or p[pending.slot]==pending.mon then
      return pending.species,'chosen-party-menu-slot-'..pending.slot
    end
    return nil,'selected-member-no-longer-in-party'
  end
  local explicit,source=explicitMonOrSlot(mod,world,anim)
  if explicit then return dexFor(mod,explicit),source end
  return nil,'no-explicit-fly-user' -- Pidgeot, not first party Fly-knower
end

local function isActorApi(api)
  return type(api)=="table" and type(api.createActor)=="function"
end
local function handleExport(mod,modId,keys)
  if not(mod and type(mod.find)=="function") then return nil end
  local ok,handle=pcall(mod.find,modId)
  local exports=ok and handle and handle.exports
  if type(exports)~="table" then return nil end
  for _,key in ipairs(keys) do
    local api=exports[key]
    if isActorApi(api) then return api end
  end
  return nil
end
local function findApi(mod)
  -- Ranch must be detected by its actual API, not its DX compatibility
  -- aliases. Prefer Ranch explicitly when both Ranch and DX are installed.
  local ranch=rawget(_G,'POKEMON_RANCH_API')
  if isActorApi(ranch) then return ranch,'Ranch' end
  ranch=handleExport(mod,'POKEMON_RANCH_GEN1',{
      'ranch_models','cobblemon_main','cobblemon_151','pokemon_xd_386'})
  if isActorApi(ranch) then return ranch,'Ranch' end
  -- Existing Rumble/DX providers still work when Ranch isn't installed.
  local globals={
    {'Rumble','POKEMON_RUMBLE_API'}, {'Rumble','RUMBLE_API'},
    {'DX','POKEMON_XD_386_API'}, {'DX','POKEMON_XD_API'},
    {'DX','COBBLEMON_API'}
  }
  for _,pair in ipairs(globals) do
    local api=rawget(_G,pair[2])
    if isActorApi(api) then return api,pair[1] end
  end
  if mod and type(mod.find)=='function' then
    for _,id in ipairs({'RUMBLE_IMPORTER','POKEMON_RUMBLE',
      '368ImporterDXGen1','POKEMON_XD_386'}) do
      local api=handleExport(mod,id,{
        'pokemon_fly_actor','rumble_151','pokemon_rumble',
        'pokemon_xd_386','cobblemon_main','cobblemon_importer'})
      if isActorApi(api) then
        return api,(id=='RUMBLE_IMPORTER' or id=='POKEMON_RUMBLE') and 'Rumble' or 'DX'
      end
    end
  end
  return nil,nil
end
local current=nil
function M.begin(mod,world,anim)
  M.clear()
  local id,source=M.speciesFromFly(mod,world,anim)
  local api,kind=findApi(mod)
  current={species=id,source=source,api=api,kind=kind,
    actor=nil,failed=false,lastTime=nil,reason=nil,logger=mod and mod.log}
  if mod and mod.log then
    if not id then
      mod.log:warn("NPC HM Fly: selected Fly user not available; using Pidgeot")
    elseif not api then
      mod.log:info("NPC HM Fly: species %d selected, Ranch/DX/Rumble actor unavailable; using Pidgeot",id)
    else
      mod.log:info("NPC HM Fly: species %d selected via %s; provider %s",id,source,tostring(kind))
    end
  end
  return id,kind,source
end
function M.clear()
  if current and current.actor then
    local a=current.actor
    if a.destroy then pcall(a.destroy,a)
    elseif current.api and type(current.api.destroyActor)=='function' then
      pcall(current.api.destroyActor,a)
    end
  end
  current=nil
end
function M.selected() return current and current.species or nil end
local function fail(c,reason)
  c.reason=tostring(reason or 'unknown error')
  c.failed=true
  local log=c.logger
  if log and type(log.warn)=='function' then
    pcall(log.warn,log,"NPC HM Fly: %s species %d unavailable (%s); fallback Pidgeot",
      tostring(c.kind or 'importer'),c.species or 0,c.reason)
  end
  return false
end
function M.status()
  return current and {species=current.species,provider=current.kind,source=current.source,
    actor=current.actor~=nil,failed=current.failed,reason=current.reason} or {species=nil}
end
-- The common renderer receives Voxel3D.draw, not a different animation API.
-- It returns false BEFORE any draw when the requested model is unavailable.
-- Existing Pidgeot then takes over that same frame.
function M.draw(drawMesh,actorWorld,now)
  local c=current
  if not (c and c.species and c.api and type(drawMesh)=='function' and actorWorld) then return false end
  if c.failed then return false end
  if not c.actor then
    local ok,a,why=pcall(c.api.createActor,c.species,{manual=true,visible=false,worldShadow=false})
    if not(ok and type(a)=='table' and a.rig and type(a.rig.drawPackets)=='function') then
      if ok and type(a)=='table' and type(a.destroy)=='function' then pcall(a.destroy,a) end
      return fail(c,ok and (why or 'importer actor lacks rig.drawPackets') or tostring(a))
    end
    c.actor=a
  end
  local actor=c.actor
  local ok,packets=pcall(function()
    local x,y,z=actorWorld.x,actorWorld.y,actorWorld.z
    if type(actor.setPosition)=='function' then actor:setPosition(x,y,z)
    else actor.x=x;actor.y=y;actor.z=z end
    if type(actor.setYaw)=='function' then actor:setYaw(actorWorld.yaw or 0) else actor.yaw=actorWorld.yaw or 0 end
    if type(actor.setPitch)=='function' then actor:setPitch(actorWorld.pitch or 0) end
    if type(actor.setRoll)=='function' then actor:setRoll(actorWorld.roll or 0) end
    if not c.didAnimate and type(actor.setAnimation)=='function' then actor:setAnimation('fly');c.didAnimate=true end
    if type(actor.update)=='function' then
      local dt=c.lastTime and math.max(0,math.min(.1,(now or 0)-c.lastTime)) or 1/60
      actor:update(dt)
    end
    c.lastTime=now or c.lastTime
    return actor.rig:drawPackets(actor:matrix(), 'opaque', 'rby.fly.mount', 1)
  end)
  if not ok or type(packets)~='table' or #packets==0 then return fail(c,ok and 'no mesh packets' or tostring(packets)) end
  -- Make sure all packets are renderable BEFORE replacing the fallback.
  for _,packet in ipairs(packets) do
    local mesh=packet.mesh
    if not(mesh and type(mesh.getTexture)=='function' and packet.model) then
      return fail(c,'invalid mesh packet')
    end
  end
  local success=pcall(function()
    for _,packet in ipairs(packets) do
      local texture=packet.mesh:getTexture()
      drawMesh(packet.mesh,texture,packet.model)
    end
  end)
  if not success then return fail(c,'renderer draw failed') end
  return true
end
-- Reuse the imported actor's animated mesh in renderer shadow passes after
-- its first visible frame. ShadowMap remains owned by the selected renderer.
function M.shadow(drawShadow)
  local c=current
  if not(c and c.actor and not c.failed and type(drawShadow)=='function') then return false end
  local a=c.actor
  local ok,packets=pcall(a.rig.drawPackets,a.rig,a:matrix(), 'shadow', 'rby.fly.mount.shadow', 1)
  if not ok or type(packets)~='table' or #packets==0 then return false end
  local success=pcall(function()
    for _,packet in ipairs(packets) do
      if not(packet.mesh and packet.model and type(packet.mesh.getTexture)=='function') then error('no shadow mesh') end
      drawShadow(packet.mesh,packet.mesh:getTexture(),packet.model)
    end
  end)
  return success
end
return M

local conf = {}

conf.FUEL_THRESHOLD = 10
local garbage = { "minecraft:water", "minecraft:lava", "minecraft:dirt", "minecraft:grass_block", "minecraft:stone",
    "minecraft:cobblestone", "minecraft:diorite", "twigs:pebble", "minecraft:granite", "minecraft:gravel",
    "minecraft:sand", "byg:soapstone", "minecraft:flint", "upgrade_aquatic:embedded_ammonite", "minecraft:torch",
    "minecraft:deepslate", "minecraft:cobbled_deepslate", "twigs:rhyolite", "forbidden_arcanus:darkstone", "tetra:geode",
    "silentgear:bort", "minecraft:tuff" }
local fallingEntities = { "minecraft:sand", "minecraft:gravel" }
local authorizedFuelSource = { "minecraft:coal", "minecraft:charcoal", "minecraft:lava_bucket" }

-- Constant loading
-- Falling entities
conf.isFallingEntity = {}
for _, v in ipairs(fallingEntities) do
    conf.isFallingEntity[v] = true
end
-- fuel entities
conf.isFuel = {}
for _, v in ipairs(authorizedFuelSource) do
    conf.isFuel[v] = true
end
-- trash
conf.isTrash = {}
for _, g in ipairs(garbage) do
    conf.isTrash[g] = true
end

return conf

fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

name 'dante_fuel'
author 'Dante Fuel contributors'
version '1.7.0'
repository 'https://github.com/DI-Devlopment/dante_fuel'
description 'Fuel management with native pump displays and sd-interact support'

dependencies {
    'ox_lib',
    'ox_inventory',
    'sd-interact',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    'server.lua',
    'server/live_fueling.lua',
    'server/nozzle.lua',
}

client_script 'client/init.lua'

data_file 'DLC_ITYP_REQUEST' 'stream/hose/whip_hose_seg.ytyp'

files {
    'html/pump3d/*.html',
    'stream/hose/*.ydr',
    'stream/hose/*.ytd',
    'stream/hose/*.ytyp',
    'locales/*.json',
    'data/stations.lua',
    'client/*.lua',
}

ox_libs {
    'math',
    'locale',
}

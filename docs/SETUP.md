# Setup

## Basic
The keyless standalone is dist/UltraBoost-Basic.lua. Its public release mirror is UltraBoost.lua in kawanzyn/Ultra-boost-2.0-Release.

## Premium development
The modular visual source is under src/. Server Finder modules are under src/ServerFinder/. They are development modules and have not yet been bundled into a final standalone Premium script.

## Keys and monetization
Basic remains keyless. Premium key validation must be server-side. Do not embed administrator tokens, signing secrets or provider credentials in the client script. The monetized acquisition website depends on selecting a provider and implementing its verification callback.


## Internal Premium DEV preview
Use dist/UltraBoost-Premium-DEV.lua only for private runtime tests. It includes Server Finder but has no key verification, activation website or monetized key flow. Do not distribute it as a paid build.

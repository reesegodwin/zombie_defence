# Nightfall Outpost (Godot 4.7)

An isometric zombie defence roguelite. Hold out five nights until the rescue
convoy comes. The dead never stop coming. At first they
come out of the sewer pipe at the end of the lane in front of your wall. The
lanes through the woods to the west and east have pipes too, quiet for now.
They open up later (the west on the morning of day 3, the east on day 5,
with a 40-second warning, and then a minute's grace before the dead start
coming out of them), and then you have three walls to hold. Each wall has its own health. If one breaks, it gives way in one
place: a gap a few metres wide, which the dead from that lane crowd along
the wall to and squeeze through (a choke point worth covering). Once in, they
hunt: most go for whoever or whatever is nearest,
person or turret, finding their way round the buildings, while some go after
someone else, so they spread out. Keep shooting, and repair the wall to
a quarter of its strength to close the gap. Nobody snaps onto a target: the
crew and the turrets swing round onto each new one before they fire. Everyone has health (bars show
over anyone hurt) and recovers when no zombie is close. If you fall, the crew
fights on; when nobody in the base is left alive, the run is over and the
camp opens.

Days and nights take turns. By day (2:30) the dead only drift in, and every
so often there's a lull when just a straggler comes every few seconds: time
to repair, build, rearrange and send someone out. When the sun goes down
(you're warned 20 seconds before) the horde comes, a second wave follows at
midnight, and the dead keep coming hard until dawn (1:40 later).

You start alone with a pistol on the walkway behind the wall, with the
mountains at your back. Thirty seconds in, a survivor comes down the mountain
pass to join you; after that, strangers only come down the pass if you've lost
all your survivors. Send one at a time back out
through the pass to scavenge: pick a place on the hand-drawn map by how long
they'll be gone and how much scrap it holds (each place can only be looted
once; it's crossed out afterwards). They come back with scrap, and
with luck a gun, food, molotovs, pipe bombs or another survivor.

Scrap goes on **research** first (T): a tree of projects in six branches
(guns, gear, traps, defences, turrets, provisions). Each one costs scrap up front,
takes a while, and only one runs at a time. Research unlocks things in the
**workshop**, where you spend more scrap to build them: guns, gear, traps,
wire, molotovs and pipe bombs, more shelving, crew drills, and base
buildings. The walls start as flimsy fences; carpentry lets you put up wooden
walls, and masonry stone ones. Auto-turrets are bought in the workshop and
then placed wherever you click in the base (up to four). They shoot on their
own; heavy rounds, belt feed and optics upgrade them. But the dead can tear
them down: a turret standing close behind a wall gets clawed at by the
zombies at that wall, and any that get into the base go for whatever's
nearest, turret or person. A health bar shows once one's been hit; pick a
survivor and click the turret to send them to repair it (for scrap, like the
walls). At nothing it collapses, and you can build another. Research Radio and
build a radio station, and now and then (about every three minutes) a
survivor hears it and walks in through the pass on their own. Food comes from
scavenging, and the provisions research makes it go further: Foraging (more
food found, never empty-handed), Rationing (the crew eats 25% less),
Smokehouse (food from trips goes 50% further) and Field kitchen (hunger hurts
half as much, and a hot meal at sundown speeds up everyone's shooting). Molotovs and pipe bombs are used once:
throw one where you click. Anything you don't need can be torn down for
scrap in the storage panel. Every survivor eats all the time
(half a food a minute each); the food bar shows your stock, how fast it's
going and how long it will last. If it runs out the crew goes hungry and
shoots slower.

Every survivor who joins you turns up with one to three random skills, each
at level I, II or III: **Handy** (repairs faster), **Thrifty** (less scrap per
repair), **Sharpshooter** (more damage, tighter spread), **Quick hands**
(shoots faster), **Cook** (while they're at the base, everyone eats less),
**Scrounger** (more scrap, guns and bombs), **Forager** (more food on trips), **Fleet-footed**
(shorter trips) and **Careful** (less likely to die out there). You start
with none: your own skills come from the camp. Scavenging is risky: there
is a slight chance, higher on longer trips, that whoever you send never comes
back, and their gun and gear are lost with them. The map shows the odds for
the survivor you've picked; the storage panel lists everyone's skills (hover
for details). It is one continuous run; each day and night is
harder than the last, and the hordes keep growing.

## Levels

Pick the level on the title screen (or at the camp, next to Heat):

1. **The Road**: one way in. The dead only come down the lane in front of
   your wall; the pipes at the end of the side lanes are bricked up.
2. **The Crossroads**: three walls to hold. The west lane opens on the morning
   of day 3 and the east on day 5. Pays 25% more Grit.
3. **The Siege**: all three lanes from the first morning, and the dead come
   thicker and tougher. The mountain pass at your back stays safe. Pays 50%
   more Grit.
4. **Last Stand**: endless. No truck comes; all three lanes and waves that
   never stop growing. Hold out 5 nights there and the run counts as won
   (the win's Grit and the next Heat), then keep going for Grit for every
   night until they get in. Pays 75% more Grit.

A run is a campaign through the levels from the one you pick. At the dawn
after night 5 (day 6) an army truck comes down the mountain pass into the
yard; the crew climb on and are driven to the next level's base, starting
again on day 1 there. They keep the survivors (healed), their guns, gear and
skills, scrap, food, storage, research and the camp's upgrades; the walls,
turrets, traps, wire and radio stay behind. The campaign ends on the endless
Last Stand. Nights held add up across the levels, for
Grit.

Levels are set up in `scripts/defs.gd` (`LEVELS`): which lanes open and when,
and the Grit bonus. Your wins on each are counted.

## Runs and the camp

Win or lose, every run pays **Grit**: 5 just for playing, 10 for each night you held, 1 per 20
kills, 1 per research project finished, 2 per survivor still with you, and 50
for a win (more at higher Heat). Spend it at the **camp** (C, or the Camp
button) on upgrades that last: from the title or game-over screen, or in the
middle of a run (the run waits while you're there). Bought mid-run, your
skills take hold at once; the starting kit, blueprints and base wait for
your next run.

- **Your skills:** Salvager (scrap for every kill: 1 per level, 2 per level for
  brutes), Handy, Thrifty, Sharpshooter and Quick hands for your own
  character (up to III), Commander (the crew hits harder), Tough (every wall
  tougher), Quartermaster (cheaper workshop) and Scavenger's eye (whoever
  goes scavenging finds more: survivors, guns, food and molotovs or pipe
  bombs turn up 20% more often per level, and 10% more scrap).
- **Starting kit:** extra scrap, an SMG, spike strips, extra food, or a
  survivor beside you from the start.
- **Blueprints:** research that's already done when a run starts (they follow
  the research tree: Auto-turrets needs SMG and Carpentry first).
- **Base:** start with wooden walls, more shelving, a pantry (more food, eaten
  slower) or a turret.

Winning at your highest **Heat** unlocks the next (up to 5): each level brings
more and tougher zombies and pays more Grit. Progress is saved in
`user://progress.cfg`, and the camp has a button to wipe it.

The game is 3D with a fixed isometric camera, so it gets real lighting:
moonlight and shadows that change as night deepens, lanterns, a bunker
floodlight, muzzle flashes, burning fuel, explosions and blood on the ground.

## Open and play

1. Open Godot 4.7 (the standard edition is fine).
2. In the Project Manager click **Import**, choose `project.godot` in this folder,
   then **Import & Edit**.
3. The first import takes a moment while Godot processes textures and the font.
4. Press **F5** (or ▶ at the top right) to play.

## Controls

| Action | Input |
|---|---|
| Shoot | Hold left mouse button (aim snaps to the zombie under the cursor) |
| Reload | R (everyone also reloads by themselves when the magazine runs dry, and tops up when there's nothing to shoot) |
| Move a survivor | Click them (you included) to pick them, then click a spot on any walkway or anywhere in the base; they walk there. Right-click or Esc to cancel |
| Repair a wall | Pick a survivor on a walkway, then click them again; click once more to stop. They repair the wall they're on. Costs scrap, takes time, and they don't shoot while repairing |
| Build a turret | Buy it in the workshop, then click in the base where it should go (green means clear) |
| Throw a molotov or pipe bomb | Double-click it in storage (or select it and press Throw), then click where it should land |
| Tear an item down for scrap | Select it in storage or a gear slot and press Tear down |
| Display options (window mode, size, interface size) | O. The game starts maximised to fit your screen |
| Scavenging map (pauses the game) | M |
| Research tree (pauses the game) | T |
| Workshop | B |
| Base storage and crew loadouts | I (or Tab) |
| Move items | Drag between slots; drag traps onto the ground in front of the wall |
| Use a supply (wire) | Double-click it, or select it and press Use |
| Pause | P or Space |
| Walk | WASD or the arrow keys: you walk anywhere in the yard or along the walkways, and the camera follows you. The cursor hides while you walk and comes back when you move the mouse |
| Zoom | Mouse wheel |
| Sound on/off | N |
| Move several of the crew at once | Left-drag a box over them, starting inside the base (a drag out in the lanes still shoots), then click a walkway or a spot in the base |
| The camp (spend Grit, any time) | C or the Camp button |
| Save / load a run | Pause (P), then Save game or Load game; F5 quick save, F9 quick load. It autosaves every dawn and when you quit to the title |
| Pick up where you left off | Continue on the title screen (or Load a saved run) |
| After a run: to the camp, then start the next run | C (or R or Enter) at the end screen, then Enter |

## Where things are (and what to tweak in the editor)

| Path | What it is |
|---|---|
| `scenes/main/main.tscn` | The main scene: environment (sky, fog, glow), moon, camera, effects, HUD |
| `scenes/level/level.tscn` | The compound: ground, lane, walkway, yard, bunker and floodlight, huts, lanterns |
| `scenes/level/palisade.gd` | The stake fence round the base, with the gate to the pass |
| `scripts/terrain.gd`, `scenes/level/ground.gd` | The lie of the land: level base and walls, gently rolling lanes, hills beyond. Tune the hills' height and the lanes' roll at the top of `terrain.gd` |
| `scenes/level/wall.tscn` | The wall (fence, wooden wall, stone wall); its materials are in the Inspector |
| `scenes/actors/truck.gd` | The army truck that carries the crew to the next level (or to safety after the last) |
| `scenes/actors/turret.gd` | Auto-turret, built in code: an old water-cooled machine gun on a motorised swivel base, up on a steel tripod so it fires over the wall; research adds a heavier muzzle, an ammo can and belt, and a sensor camera |
| `scenes/level/level.gd` | The level's lights: lamp beams you can see; lamp posts only on walls whose lane brings the dead; the yard's lamps (by the generator, the path and the workbench); each lane's spotlights (on the walkway posts, plus the bunker's floodlight for the front) stay dark until the dead first come down that lane, then flicker on and stay on; the bunker beacon; and it sets up the culverts, fog and base props |
| `scenes/level/ground_fog.gd`, `assets/shaders/fog_puff.gdshader`, `ground_fog.gdshader` | Thick rolling ground fog up to the dead's knees, like a fog machine's: soft cloud puffs standing on the ground that overlap into banks, drift slowly, swell and churn, over a thin layer that fills the gaps. It lies in the lanes (thinner in the yard) and thins up the hills; how thick, how high and how big the puffs are, and how much the yard gets, are constants at the top of `ground_fog.gd` |
| `scenes/level/base_props.gd` | Dresses the base: the bunker (concrete, sandbags, steel door, lookout, ladder), plank huts with rusty tin roofs, slatted crates, oil drums, the canvas tent, the log gate and the plank walkway, drawn in detail where the placeholder boxes in `level.tscn` stand (move those to move them) |
| `tools/bake.gd` | Works out the sounds and the land's height grid once and saves them in `assets/baked/` (not committed); the automatic build runs it before exporting, so released builds start about twice as fast |
| `scenes/level/culvert.gd` | The end of each lane: a concrete headwall in an earth bank with big sewer pipes the dead come out of (where, in `defs.gd`: `PIPES`), ivy, rubble and a burning barrel, built in code |
| `scenes/actors/guns.gd` | The guns (pistol, SMG, pump shotgun, scoped rifle, grenade launcher), built in code from low-poly blocks and tubes, sized by `barrel_length` in their `.tres`; also the kit the turret is built from |
| `scenes/ui/research_tree.gd` | The research tree screen |
| `scenes/level/forest.gd` | The woods; change **Seed Value** or **Density** in the Inspector to re-roll |
| `scenes/level/mountains.gd` | The mountains and the pass behind the base; re-roll with **Seed Value** |
| `scenes/ui/scavenge_map.tscn`, `map_canvas.gd` | The hand-drawn scavenging map |
| `scenes/actors/zombie.tscn`, `zombie.gd` | A zombie: how it moves (its shamble, reach and claw) |
| `scenes/actors/body.gd`, `scenes/actors/skin_rig.gd`, `assets/shaders/body.gdshader` | Everyone's bodies, built in code on a shared skeleton of joints. Zombies: seven models of the shambling dead (`ZOMBIE_MODELS`: a T-shirt and jeans out at the knees, a striped sweater, a buttoned work shirt, a shirt hanging open over a vest, a vest and cut-offs, bare chested with the ribs showing, and one torn open to the ribs with glowing eyes), each a single finely made skin (about 28,000 triangles, drawn in less detail when small on screen) that bends with the joints: a gaunt body with collarbones, ribs, kneecaps and wrist bones, a sculpted face with sunken milky eyes and bared teeth, blood round the mouth and up the arms, boots or bare feet, thin or lank hair or none. Each zombie type lists the models it comes as and its shirt colours (`data/zombies/*.tres`); the horde shares 64 bodies, made ahead of time while you're in the menus. Survivors: a simpler cartoon build, a mesh per joint: hair (short, long or a cap), brows, eyes with irises, a nose, a jacket or T-shirt, trousers, boots, sometimes a beard or a backpack. The shader adds veins, bruises, sores and grime to dead skin, a softer blotchiness to living skin, a weave and creases to cloth, the sweater's stripes and the glow of eyes |
| `scenes/actors/survivor.tscn`, `survivor.gd` | A survivor: aiming with both hands, walking, kneeling to repair, reloading, falling; gun, muzzle flash and name label |
| `scenes/traps/*.tscn` | Spike strip, bear trap, landmine and fuel slick |
| `scenes/fx/fire.tscn`, `explosion.tscn` | Particle effects with lights |
| `scenes/ui/hud.tscn`, `ui_theme.tres` | Interface layout and its look |
| `data/weapons/*.tres` | **Weapon stats**: open one and edit damage, fire rate, range, magazine size, reload time… in the Inspector |
| `data/zombies/*.tres` | **Zombie stats and colours**: health, speed, wall damage, size… |
| `data/sites/*.tres` | **Scavenging sites**: time away, scrap level, odds of guns, food and survivors, map position |
| `scripts/game.gd` | Game rules: difficulty curve, combat, traps, inventory, scavenging, food, workshop |
| `scripts/settings.gd` | Display settings, saved to `user://settings.cfg` |
| `scripts/saves.gd` | Saved runs in `user://saves/`: Autosave (every dawn, and on quitting to the title), Quick save (F5) and three slots. A run is saved by `Game.to_save()` and picked up by `Game.from_save()`; a finished run's autosave is deleted |
| `scripts/progress.gd` | Grit, camp upgrades, Heat and records, saved to `user://progress.cfg` |
| `scripts/defs.gd` | **Camp upgrades, their costs, Grit and Heat** (at the bottom), **the three lanes and when they open**, day and night lengths, lulls, how fast it gets harder, **the research tree** (costs, times, what needs what), wall tiers, turret and farm numbers, workshop prices and what research unlocks them, base size, repair speed and cost, scrap ranges, food per survivor, stranger timings, survivor skills and their odds, the risk of dying while scavenging, items, map layout |
| `scripts/sfx.gd` | Sound effects, generated in code. The zombies' voices come from a small voice synthesiser (glottal pulses with jitter, growl and creaky fry, breath, and vowel formants), modelled on recorded zombie moans: shambling moans, grunts and gurgles for walkers, deeper ones for brutes, raspy ones for runners, snarls when they attack, a choked croak when they die, and a distant chorus before a side opens |

The simulation in `scripts/game.gd` has no nodes; the scenes read its state each
frame. So you can restyle anything in the editor without touching game rules,
and replacing the block models with real art later only means editing the
actor scenes.

## Play it

**In your browser:** https://reesegodwin.github.io/zombie_defence/ (Chrome or
Edge on a computer). Nothing to download or install, so nothing for Windows to
block. Your saves and camp progress stay in that browser. If it runs slowly,
lower Fog in Options (O).

**On Windows:** download `NightfallOutpost-windows.zip` from the **Latest
Windows build** release, unzip it and double-click `NightfallOutpost.exe`.
The exe isn't digitally signed, so Windows may stop it: SmartScreen ("Windows
protected your PC") lets you click More info, then Run anyway, but **Smart App
Control** blocks it outright; play in the browser instead.

**System requirements (aim):** Windows 10 or 11, any graphics from the last
~8 years including built-in laptop graphics (Intel UHD 620 or newer) on the
Low setting. Graphics (Options) is picked for your PC on the first run: High
on a separate graphics card, Low on built-in graphics. If there's no Vulkan
the game falls back to OpenGL on its own. The browser version is slower than
the Windows one by nature (one CPU thread, WebGL); it's for trying the game.

Both are built automatically on every push to `main`
(`.github/workflows/windows-build.yml`): it runs the tests, exports the game
as one `.exe`, zips it with `dist/HOW TO PLAY.txt` onto the release (the
`windows-latest` tag), and exports the browser version (the "Web" preset,
single-threaded so GitHub Pages can host it) and publishes it on Pages. A
build can be started by hand from the Actions tab too (Run workflow).

To build it yourself instead, with Godot 4.7.1's export templates installed:

```bash
godot --headless --path . --export-release "Windows Desktop" export/NightfallOutpost.exe
```

For the browser version: `--export-release "Web" export/web/index.html`, then
serve `export/web` over HTTP.

## Tests

From this folder, with `godot` being your Godot executable:

```bash
godot --headless --path . --script res://tests/sim_test.gd
```

Logic checks plus six simulated games, printing how long each survived.

```bash
godot --path . --script res://tests/model_sheet.gd -- shots
```

Renders character sheets (front, three-quarter, side, back and a close-up of
the face) of each zombie type and of you, a line-up of the crew, every gun
(on its own and in someone's hands) and the turret behind a stretch of wall,
to `shots/`.

```bash
godot --headless --path . --script res://tests/gait_check.gd
```

Walks each zombie type and checks its planted foot stays put on the ground
(the walk cycle follows the distance actually travelled, so the legs match
the speed).

```bash
godot --path . --script res://tests/perf_check.gd
```

Measures where the time goes: the game rules alone at 50, 150 and 300
zombies, then frame times for a night horde at each Graphics preset and with
each feature turned off in turn (anti-aliasing, fog, spotlights, sun shadows,
SSAO, glow). Add `-- --presets-only` for just the presets.

```bash
godot --headless --path . --script res://tests/sound_check.gd -- shots/sounds
```

Writes every sound effect to a WAV file, and all the zombie voices one after
another into `zombie_voices.wav`, to listen to.

```bash
godot --path . --script res://tests/visual_test.gd -- shots
```

Opens the real game, drives it with mouse drags and clicks (equipping,
placing and moving traps, shooting, buying in the workshop, sending someone
scavenging from the map and waiting for them to come back, game over,
restart) and saves screenshots to `shots/`.

## Credits

Oswald font by Vernon Adams and others, and Caveat font by Impallari Type,
both under the SIL Open Font License
(`assets/fonts/LICENSE.txt`). Everything else was made for this project.

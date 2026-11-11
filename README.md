# Nightfall Outpost (Godot 4.7)

An isometric zombie defence game. One wall, one way in, and the dead never stop
coming. You start alone with a pistol on the walkway behind the wall, with the
mountains at your back. Survivors sometimes find their way to you through the
mountain pass (more often while you're alone). Send one at a time back out
through the pass to scavenge: pick a place on the hand-drawn map by how long
they'll be gone and how much scrap it holds. They come back with scrap, and
with luck a gun, food or another survivor. Spend scrap in the workshop on guns,
gear, traps, supplies and a stronger wall. Keep food in store or the crew goes
hungry and shoots slower. It is one continuous run that keeps getting harder as
night falls, with hordes that keep growing.

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
| Auto-fire on/off | F (while on, you turn to face what you're shooting; holding the mouse button takes over) |
| Scavenging map (pauses the game) | M |
| Workshop | B |
| Base storage and crew loadouts | I (or Tab) |
| Move items | Drag between slots; drag traps onto the ground in front of the wall |
| Use a supply (repair kit, wire) | Double-click it, or select it and press Use |
| Pause | P or Space |
| Pan / zoom | Right-drag or WASD / mouse wheel; Home recentres |
| Sound on/off | N |
| Play again after the wall falls | R |

## Where things are (and what to tweak in the editor)

| Path | What it is |
|---|---|
| `scenes/main/main.tscn` | The main scene: environment (sky, fog, glow), moon, camera, effects, HUD |
| `scenes/level/level.tscn` | The compound: ground, lane, walkway, bunker and floodlight, huts, lanterns |
| `scenes/level/wall.tscn` | The wall; its timber, stone and steel materials are in the Inspector |
| `scenes/level/forest.gd` | The woods; change **Seed Value** or **Density** in the Inspector to re-roll |
| `scenes/level/mountains.gd` | The mountains and the pass behind the base; re-roll with **Seed Value** |
| `scenes/ui/scavenge_map.tscn`, `map_canvas.gd` | The hand-drawn scavenging map |
| `scenes/actors/zombie.tscn` | Zombie model (one scene, coloured per type) and its animation script |
| `scenes/actors/survivor.tscn` | Survivor model, gun, muzzle flash light and name label |
| `scenes/traps/*.tscn` | Spike strip, bear trap, landmine and fuel slick |
| `scenes/fx/fire.tscn`, `explosion.tscn` | Particle effects with lights |
| `scenes/ui/hud.tscn`, `ui_theme.tres` | Interface layout and its look |
| `data/weapons/*.tres` | **Weapon stats**: open one and edit damage, fire rate, range… in the Inspector |
| `data/zombies/*.tres` | **Zombie stats and colours**: health, speed, wall damage, size… |
| `data/sites/*.tres` | **Scavenging sites**: time away, scrap level, odds of guns, food and survivors, map position |
| `scripts/game.gd` | Game rules: difficulty curve, combat, traps, inventory, scavenging, food, workshop |
| `scripts/defs.gd` | Workshop prices, scrap ranges, food and stranger timings, items, map layout |
| `scripts/sfx.gd` | Sound effects, generated in code |

The simulation in `scripts/game.gd` has no nodes; the scenes read its state each
frame. So you can restyle anything in the editor without touching game rules,
and replacing the block models with real art later only means editing the
actor scenes.

## Tests

From this folder, with `godot` being your Godot executable:

```bash
godot --headless --path . --script res://tests/sim_test.gd
```

Logic checks plus six simulated games, printing how long each survived.

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

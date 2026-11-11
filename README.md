# Nightfall Outpost (Godot 4)

An isometric zombie defence game. One wall, one way in, and the dead never stop
coming. You start alone with a pistol on the walkway behind the wall. Kills give
experience; every level you pick one of three cards (new guns, gear, traps,
supplies, survivors, or a stronger wall). There are no levels or waves to clear:
it is one continuous run that keeps getting harder, with a horde every 70 seconds.

## Open and play

1. Open Godot (4.3 or newer).
2. In the Project Manager click **Import**, pick the `project.godot` file in this
   folder, and click **Import & Edit**. If Godot asks to upgrade the project to
   your version, click OK.
3. Press **F5** (or the ▶ Play button, top right) to play.

## Controls

| Action | Input |
|---|---|
| Shoot | Hold left mouse button (aim snaps to the zombie under the cursor) |
| Auto-fire on/off | F |
| Base storage and crew loadouts | I (or Tab) |
| Move items | Drag between slots; drag traps onto the ground in front of the wall |
| Use a supply (repair kit, wire) | Double-click it, or select it and press Use |
| Pause | P or Space |
| Pan / zoom | Right-drag or WASD / mouse wheel; Home recentres |
| Pick a level-up card | Click it, or 1 / 2 / 3 |
| Sound on/off | M |
| Play again after the wall falls | R |

## Project layout

| File | What it does |
|---|---|
| `scripts/defs.gd` | All tunable data: zombie types, weapons, items, traps, map layout |
| `scripts/game.gd` | The simulation: director, zombies, crew, combat, traps, inventory, cards |
| `scripts/world.gd` | Isometric drawing (vector shapes; swap in sprites here later) |
| `scripts/hud.gd` | Interface: stats, cards, storage, title, pause and game-over screens |
| `scripts/slot.gd` | One inventory slot with drag and drop |
| `scripts/field.gd` | Mouse input over the battlefield |
| `scripts/sfx.gd` | Sound effects generated in code (no audio files) |
| `scripts/main.gd` | Glue: camera, input, game loop |

The game logic lives in `game.gd` with no nodes, so balance changes are mostly
edits to numbers in `defs.gd` and `game.gd`.

## Tests

From this folder, with `godot` being your Godot executable:

```bash
godot --headless --path . --script res://tests/sim_test.gd
```

Runs logic checks plus six simulated games with auto-fire and random card
picks, and prints how long each survived.

```bash
godot --path . --script res://tests/visual_test.gd -- shots
```

Opens the real game, drives it with simulated mouse drags and clicks
(equipping, placing and moving traps, shooting), and saves screenshots.

# One kind of zombie. Each is a .tres file in data/zombies/ that you can open and
# tune in the Inspector. The file name (without .tres) is the type's key.
@tool
class_name ZombieType
extends Resource

@export var display_name := "Walker"
@export_group("Stats")
@export var health := 40.0               ## At the start of a run; rises over time.
@export var speed := 0.6                 ## Tiles per second.
@export var wall_damage := 8.0           ## Per hit on the wall.
@export var seconds_between_hits := 1.0
@export var radius := 0.2                ## Body size for crowding and bullet hits, in tiles.
@export_group("Look")
@export var model_scale := 1.0
## Which of the models in scenes/actors/body.gd (ZOMBIE_MODELS) this type
## comes as: tee, sweater, shirtless, vest, open_shirt, workshirt, flayed.
@export var models := PackedStringArray(["tee"])
@export var skin_color := Color("b8a58c")
@export var shirt_colors := PackedColorArray([Color("4f5d6b")])
@export var eye_color := Color(0.9, 0.2, 0.1)    ## The eyes of the models whose eyes glow.


func to_dict() -> Dictionary:
	return {
		"name": display_name, "hp": health, "speed": speed, "dmg": wall_damage,
		"rate": seconds_between_hits, "r": radius, "scale": model_scale,
		"models": Array(models),
		"skin": skin_color, "shirts": Array(shirt_colors), "eyes": eye_color,
	}

# One gun. Each weapon is a .tres file in data/weapons/ that you can open and
# tune in the Inspector. The file name (without .tres) is the weapon's key.
@tool
class_name WeaponData
extends Resource

@export var display_name := "Pistol"
@export_multiline var description := ""
@export_group("Damage")
@export var damage := 14.0               ## Per bullet or pellet.
@export var pellets := 1                 ## Bullets per shot (shotguns fire several).
@export var pierce := 1                  ## How many zombies one bullet can pass through.
@export var splash_radius := 0.0         ## Above 0 the weapon lobs grenades that explode.
@export_group("Handling")
@export var seconds_between_shots := 0.34
@export var spread := 0.03               ## Random aim error, in radians.
@export var reach := 13.0                ## Effective range, in tiles. Bullets fly on as far as they go, but past half of this the aim gets worse.
@export var accuracy_falloff := 1.0      ## How quickly aim worsens with distance (0: holds its aim at any distance).
@export var knockback := 0.04            ## How far a hit shoves the zombie back.
@export var bullet_speed := 70.0         ## How fast its bullets fly, metres a second.
@export var magazine := 15               ## Shots before a reload.
@export var reload_seconds := 1.2        ## How long a reload takes.
@export_group("Presentation")
@export var barrel_length := 0.45        ## Length of the gun model, in metres.
@export var muzzle_reach := 0.9          ## How far in front of the shooter the barrel ends (where shots come out), metres. Measured off the model.
@export var muzzle_height := 1.41        ## How high above the shooter's feet the barrel ends: pistols held out at eye level, long guns shouldered lower.
@export var muzzle_side := -0.05         ## How far the barrel end is off the line of aim (negative: to the shooter's right).
@export var sound := "gun"               ## gun, smg, shotgun, rifle or launch.
@export var slot_label := "PST"          ## Short text shown in inventory slots.


func to_dict() -> Dictionary:
	var d := {
		"name": display_name, "desc": description, "dmg": damage, "rate": seconds_between_shots,
		"spread": spread, "range": reach, "pellets": pellets, "pierce": pierce, "knock": knockback,
		"len": barrel_length, "sound": sound, "short": slot_label,
		"mag": magazine, "reload": reload_seconds, "falloff": accuracy_falloff,
		"bullet_speed": bullet_speed, "muzzle": muzzle_reach,
		"muzzle_up": muzzle_height, "muzzle_side": muzzle_side,
	}
	if splash_radius > 0.0:
		d["splash"] = splash_radius
	return d

# Ties the level's lights to the time of night, and blinks the bunker beacon.
extends Node3D

@onready var beacon: OmniLight3D = $Bunker/Beacon
@onready var beacon_bulb: MeshInstance3D = $Bunker/BeaconBulb
@onready var floodlight: SpotLight3D = $Bunker/Floodlight
@onready var lanterns: Node3D = $Lanterns

var _t := 0.0


func _ready() -> void:
	# Aim the floodlight down the lane at the tree line.
	floodlight.look_at(Vector3(11.5, 0.0, 7.0))


## darkness: 0 (dusk) .. 1 (deep night)
func set_darkness(k: float, dt: float) -> void:
	_t += dt
	var on := fmod(_t, 1.6) < 0.18
	beacon.light_energy = 3.0 if on else 0.0
	beacon_bulb.visible = on
	floodlight.light_energy = lerpf(4.0, 12.0, k)
	for l in lanterns.get_children():
		var light: OmniLight3D = l.get_node("Light")
		light.light_energy = lerpf(0.4, 1.8, k) * (0.94 + 0.06 * sin(_t * 9.0 + l.position.x))

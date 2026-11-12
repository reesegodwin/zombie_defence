# A patch of fire: flame and smoke particles, a flickering light, a scorch mark.
@tool
extends Node3D

## Radius of the burning area, in metres.
@export var radius := 1.2:
	set(v):
		radius = v
		if is_inside_tree():
			_apply()
## Leaves a scorch mark on the ground.
@export var scorch := true
@export var light_energy := 2.6

@onready var flames: GPUParticles3D = $Flames
@onready var smoke: GPUParticles3D = $Smoke
@onready var light: OmniLight3D = $Light
@onready var decal: Decal = $Scorch

var fade := 1.0
var _t := 0.0


func _ready() -> void:
	_t = randf() * 10.0
	_apply()


func _apply() -> void:
	var pm: ParticleProcessMaterial = $Flames.process_material.duplicate()
	pm.emission_sphere_radius = radius * 0.75
	$Flames.process_material = pm
	$Flames.amount = clampi(int(20 + radius * 40), 12, 90)
	$Light.omni_range = 2.5 + radius * 3.0
	$Scorch.size = Vector3(radius * 2.6, 1.0, radius * 2.6)
	$Scorch.visible = scorch


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += dt
	var flicker := 0.8 + 0.2 * sin(_t * 23.0) * sin(_t * 7.3 + 1.0)
	light.light_energy = light_energy * flicker * fade


## Stops the flames, lets the light die down, and frees the node.
func burn_out() -> void:
	flames.emitting = false
	smoke.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "fade", 0.0, 0.8)
	tw.tween_interval(1.5)
	tw.tween_callback(queue_free)

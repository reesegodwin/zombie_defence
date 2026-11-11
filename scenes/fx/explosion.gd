# A one-shot blast: a flash of light, sparks, smoke and a scorch mark.
extends Node3D

@export var flash_energy := 14.0

@onready var light: OmniLight3D = $Light
@onready var ball: MeshInstance3D = $Fireball


func _ready() -> void:
	$Sparks.emitting = true
	$Smoke.emitting = true
	$Scorch.rotation.y = randf() * TAU
	light.light_energy = flash_energy
	var tw := create_tween().set_parallel()
	tw.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball, "scale", Vector3.ONE * 2.2, 0.25).from(Vector3.ONE * 0.3)
	tw.tween_property(ball, "transparency", 1.0, 0.3)
	tw.chain().tween_interval(2.0)
	tw.chain().tween_callback(queue_free)

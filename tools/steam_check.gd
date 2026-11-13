# Run by the build after GodotSteam is added: says whether the add-on loaded
# (the Steam singleton and SteamMultiplayerPeer). Steam itself isn't running
# on the build machine, so it doesn't start it.
extends SceneTree

func _initialize() -> void:
	print("STEAM CHECK: singleton=%s multiplayer_peer=%s" % [Engine.has_singleton("Steam"), ClassDB.class_exists("SteamMultiplayerPeer")])
	quit()

# Who the survivors are: the body each is shaped into (the sliders of
# mh.Human.macro, and any finer shape targets), their colouring, and what they
# wear and carry (steps for parts.py, in order: what's underneath first).
# Colours are (red, green, blue), 0 to 1, as seen.
PEOPLE = {
    # A long-haired, bearded drifter in a worn work jacket, with a bat on his back.
    "drifter": {
        "body": {"gender": 1.0, "age": 0.62, "muscle": 0.62, "weight": 0.45, "height": 0.6, "proportions": 0.7},
        "shape": {"head/head-rectangular": 0.4, "nose/nose-hump-incr": 0.4, "eyebrows/eyebrows-angle-down": 0.3},
        "skin": (0.68, 0.51, 0.41),
        "eyes": (0.34, 0.23, 0.13),
        "hair": (0.13, 0.10, 0.08),
        "hair_style": "long",
        "stubble": 1.0,
        "wear": [
            ("trousers", {"color": (0.31, 0.32, 0.25), "fabric": "canvas", "dusty": 0.8, "cargo": 2, "pads": 2, "stack": 0.035}),
            ("boots", {"color": (0.21, 0.18, 0.14), "fabric": "leather", "dusty": 1.0}),
            ("tee", {"color": (0.62, 0.60, 0.55), "sleeve": 0.15, "grime": 0.9, "stains": 0.6}),
            ("jacket", {"color": (0.24, 0.23, 0.20), "fabric": "canvas", "grime": 0.7, "big": True}),
            ("strap", {}),
            ("bat", {}),
            ("hair", {"style": "long"}),
            ("beard", {}),
        ],
    },
    # A young woman in a beanie and a fleece-collared jacket, kitted out to scavenge.
    "scavenger": {
        "body": {"gender": 0.0, "age": 0.5, "muscle": 0.5, "weight": 0.42, "height": 0.5, "proportions": 0.8, "cup": 0.45, "firmness": 0.7},
        "shape": {"head/head-oval": 0.4, "nose/nose-scale-vert-decr": 0.3, "cheek/l-cheek-bones-incr": 0.3, "cheek/r-cheek-bones-incr": 0.3},
        "skin": (0.74, 0.57, 0.48),
        "eyes": (0.33, 0.43, 0.52),
        "skin_look": {"grime": 0.25},
        "hair": (0.40, 0.31, 0.21),
        "hair_style": "bob",
        "wear": [
            ("trousers", {"color": (0.14, 0.14, 0.15), "fabric": "canvas", "dusty": 0.9, "cargo": 2, "cuff": 1.7, "ease": 0.012}),
            ("boots", {"color": (0.1, 0.1, 0.1), "fabric": "leather", "dusty": 0.9, "top": 1.45}),
            ("scarf", {"color": (0.45, 0.45, 0.44), "grime": 0.3}),
            ("jacket", {"color": (0.50, 0.46, 0.40), "fabric": "cotton", "grime": 0.6, "big": True, "open": 0.0, "zip_": True, "neck": "sherpa", "pockets": 0,
                        "hem": -0.045, "ease": 0.01, "stack": 0.035}),
            ("kneepad", {"side": -1.0}),
            ("holster", {"where": "thigh", "side": -1.0}),
            ("pouches", {}),
            ("pack", {}),
            ("hair", {"style": "bob", "lift": 0.004}),
            ("beanie", {"color": (0.16, 0.16, 0.17), "grime": 0.3}),
        ],
    },
    # A wiry man with slicked-back hair, in a shirt with the sleeves rolled, a knife at his hip.
    "clerk": {
        "body": {"gender": 1.0, "age": 0.52, "muscle": 0.6, "weight": 0.4, "height": 0.45, "proportions": 0.7, "asian": 0.45},
        "shape": {"head/head-oval": 0.3, "chin/chin-width-decr": 0.2},
        "skin": (0.71, 0.55, 0.43),
        "eyes": (0.22, 0.14, 0.09),
        "skin_look": {"grime": 0.3},
        "hair": (0.06, 0.055, 0.05),
        "hair_style": "slick",
        "stubble": 0.25,
        "wear": [
            ("trousers", {"color": (0.19, 0.22, 0.27), "fabric": "denim", "dusty": 0.5, "cuff": 1.95, "ease": 0.007, "stack": 0.07, "turnup": True, "stains": 0.4}),
            ("boots", {"color": (0.36, 0.22, 0.14), "fabric": "leather", "dusty": 0.6, "top": 1.84}),
            ("tee", {"color": (0.34, 0.39, 0.44), "sleeve": 0.15, "hem": 0.0}),
            ("jacket", {"name": "Shirt", "color": (0.44, 0.40, 0.39), "fabric": "cotton", "grime": 0.5, "stains": 0.5, "big": True, "open": 0.0, "buttons": 6, "neck": "band",
                        "pockets": 1, "flaps": False, "hem": -0.045, "sleeve": 1.33, "cuffs": True, "ease": 0.008, "grow": 0.014, "stack": 0.03}),
            ("strap", {"high": (0.11, 0.0, -0.03), "low": (-0.16, 0.0, 0.2), "color": (0.24, 0.17, 0.11)}),
            ("holster", {"where": "sheath", "side": 1.0, "color": (0.12, 0.1, 0.08)}),
            ("hair", {"style": "slick"}),
        ],
    },
    # A weathered, bearded man in a fleece-lined leather jacket, a satchel across him.
    "rancher": {
        "body": {"gender": 1.0, "age": 0.7, "muscle": 0.55, "weight": 0.6, "height": 0.55, "proportions": 0.6},
        "shape": {"head/head-square": 0.4, "nose/nose-volume-incr": 0.3, "forehead/forehead-temple-incr": 0.2},
        "skin": (0.69, 0.51, 0.41),
        "eyes": (0.34, 0.36, 0.22),
        "skin_look": {"grime": 0.45},
        "hair": (0.24, 0.19, 0.15),
        "hair_style": "medium",
        "stubble": 1.0,
        "wear": [
            ("trousers", {"color": (0.21, 0.27, 0.36), "fabric": "denim", "dusty": 0.7, "cuff": 1.96, "ease": 0.011, "stack": 0.05, "cargo": 1}),
            ("boots", {"color": (0.45, 0.4, 0.33), "fabric": "leather", "dusty": 0.8, "top": 1.8}),
            ("tee", {"color": (0.60, 0.60, 0.58), "sleeve": 0.15, "grime": 0.6}),
            ("jacket", {"color": (0.31, 0.23, 0.17), "fabric": "leather", "grime": 0.4, "big": True, "neck": "sherpa", "hem": 0.0}),
            ("strap", {"high": (-0.11, 0.0, -0.03), "low": (0.17, 0.0, 0.0), "width": 0.045, "color": (0.3, 0.27, 0.21)}),
            ("bag", {"side": 1.0}),
            ("hair", {"style": "medium"}),
            ("beard", {"style": "short_beard", "length": 0.02}),
        ],
    },
}

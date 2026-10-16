## Data-driven settings for the fullscreen speed effect shader.
##
## Applied by SpeedEffectComponent when a boost, override, or pulse
## carries a profile reference. All values map directly to shader uniforms.
class_name SpeedEffectProfile
extends Resource

@export_group("Color")
## Tint color applied at the screen edges.
@export var effect_color: Color = Color(0.85, 0.92, 1.0, 1.0)
## How strongly the tint blends into the screen edges (0..1).
@export var tint_strength: float = 0.35

@export_group("Blur")
## Radial zoom / blur amount (0..0.2).
@export var zoom_amount: float = 0.05

@export_group("Edges")
## Normalized distance from center where the vignette starts.
@export var edge_start: float = 0.4
## Normalized distance from center where the vignette is at full strength.
@export var edge_end: float = 1.0
## Contrast boost at the vignette edge (0..2).
@export var contrast_boost: float = 0.2

@export_group("Motion")
## Flicker intensity applied at the vignette edge (0..1).
@export var flicker_amount: float = 0.1
## Flicker frequency (Hz-ish).
@export var flicker_speed: float = 10.0

## 🗺️ Roadmap

Legend: ⬜ not started · 🚧 in progress · 🔍 needs review · ⚠️ known issue
Status: [x] done · [~] partial · [ ] not started

> This is a spec list. Each [x] means "tested in Godot and feels right".
> Anything with [~] still needs polish. Update this file after each session.

> Conventions:
> - **(T)** = toggleable at runtime via @export bool
> - **(S)** = scale-driven (parameter scales with a metric)
> - **(style)** = multiple behaviour modes to choose from
> - **(fix)** = existing mechanic needs a bug fixed
> - **(update)** = existing mechanic needs a feature added

---

### Part 1 — Movement

#### Core locomotion

- [x] **Walk / Sprint** — base ground locomotion set
- [x] **Crouch** — collision swap + head drop
      - [x] crouch mode: Hold vs Toggle (T)
      - [x] ceiling-aware uncrouch (stays crouched under low ceilings)
- [x] **Prone / Crawl** — lowest stance, prone collision shape, camera drop
      - [x] prone mode: Hold vs Toggle (T)
      - [x] ceiling-aware unprone and crouch fallback
      - [x] Space stands from prone (with clearance check) (T)
- [x] **Slide** — sprint + crouch, preserves momentum
      - [x] slide end mode: Timer vs Hold (T)
      - [x] slide requires sprint toggle (T)
      - [x] slide requires input toggle (T)
      - [x] slide into prone via double-tap or hold (both modes)
      - [x] post-slide stance resolution by ceiling clearance
- [x] **Crouch-sprint** — sprint speed while crouched (optional) (T)
- [x] **Dash** — horizontal burst with FOV punch + speed effect
      - [x] scope: Both / Ground Only / Air Only (T)
      - [x] directional dash from WASD at trigger (T)
      - [x] directional per-surface (ground / air) (T)
      - [x] prone gate (T)
      - [x] cooldown + duration exports
- [ ] **Stair walk** — dedicated component for stepping up small obstacles
      - physics SeparationRayShape3D handles this for now; component deferred
- [ ] **Ladder climb** — vertical climb on tagged ladder surfaces
- [ ] **Slope walk** — walking on ramps without sliding
- [ ] **Moving platform support** — inherit velocity from elevators / trains

#### Jump + Air

- [x] **Ground jump** — base vertical impulse
- [x] **Double jump** — mid-air second jump
- [x] **Variable jump height** — tap = short, hold = full (T)
- [x] **Coyote time** — grace window after leaving ground (S)
- [x] **Jump buffering** — presses just before landing are remembered (S)
- [x] **Space-stands** — Space exits crouch/prone (with clearance check) (T)
- [x] **Air mouse steer** — mouse turn nudges character laterally (T)
      - [x] low-pass smoothing on the yaw rate
      - [x] max speed cap
- [x] **Bunny hop** — Quake-style air strafe (T) [~]
      - [x] auto-hop on landing window (holding jump) (T)
      - [x] air strafe: WASD + mouse turning (T)
      - [x] camera strafe: mouse yaw rotates neck while body keeps momentum (T)
      - [x] split toggles: master / auto-hop / air-strafe / camera-strafe
      - [ ] needs polish (acceleration curve still not fully CS-like)
- [ ] **Air control curves** — full curve data (accel / decel / turn rate)
      - partial: separate lerp_speed vs air_lerp_speed already present
- [ ] **Wall jump** — kick off walls (comes with WallRunComponent)
- [x] **Q-turn wall jump** — Q rotates player, then Space launches
      - [x] toggle
      - [x] horizontal + vertical degrees
      - [x] turn duration + grace window
      - [x] one turn per wall session
- [ ] **Ground pound** — mid-air slam with radial impulse on impact

#### Vertical + Traversal

- [x] **Wall run (horizontal)** — session-limited, tangent-locked
      - [x] basic run with session timer + off-wall reset
      - [x] sprint multiplier
      - [x] camera FOV + roll + head bob
      - [x] sin wave removed (dead exports may still linger — cleanup later)
      - [ ] **(style)** realistic / stylized modes — future polish
- [x] **Wall slide** — fallback while airborne next to a wall
      - [x] preserves horizontal momentum (only adds stick + downward pull)
      - [x] stick force + optional downward accel
      - [x] camera roll scale, no FOV, no bob
      - [x] head-on wall fallback (front-sensor)
      - [x] persists while looking away (cached normal + own probe)
      - [x] `slide_max_time` (0 = infinite)
- [x] **Vertical wall run** — run UP a wall, slide down when finished
      - [x] climb state (session-limited, tangent = UP)
      - [x] end-slide transition with head bob
      - [x] distance cap (`climb_max_distance`)
      - [x] bug fix: Ctrl+Space no longer launches player up mid-wall-run
- [x] **Wall run — distance caps** — horizontal run now bounded by distance too (`run_max_distance`)
- [x] **Wall slide — lateral control** — A/D adds along-wall speed, soft-capped
- [x] **Wall jump** — Space kicks off walls
      - [x] from horizontal run, slide, and vertical climb
      - [x] look-direction launch with tangent fallback
      - [x] `max_wall_jumps_per_airtime` cap
      - [x] variable jump (hold = high, tap = low), toggleable
- [ ] **Q-turn wall jump** — Q rotates player, then Space launches 🚧
      - [ ] toggle
      - [ ] horizontal + vertical degrees
      - [ ] turn speed + camera lerp speed
- [ ] **Wall run → wall jump chain** — **(style)** chain speed-up, capped (T) 🚧
      - [ ] toggle
      - [ ] max speed cap
      - [ ] reset conditions (grounded / timeout / stance change)
- [x] **Ladder climb** — dedicated component, own collision layer
      - [x] W / Space climbs, S / Ctrl descends
      - [x] two styles: smooth / stepped
      - [x] head bob while climbing up / down
      - [x] mantle at top using W
      - [x] own collision layer (layer 5, bit 16)
      - [x] bonus: jump-off when looking away (Space)
      - [x] bonus: `look_dot_threshold` for facing gate
- [ ] **Ledge grab** — slope-aware, mantle, drop, corner detection
- [ ] **Ledge shimmy** — inner / outer corner circular turn
- [ ] **Ledge climb up/down** — W/S while hanging, auto-mantle
- [ ] **Ledge jump-off / slingshot** — charge Space, launch away
- [ ] **Vault** — auto / manual, Q-turn, side drift, landing safety
- [ ] **Full wall climbing** — arbitrary surfaces, pipes
- [ ] **Zipline mount / dismount**

#### Grappling

- [ ] **Dual hooks** — LMB / RMB, dual-wield, swing, zip
- [ ] **Grapple style — swing** — pendulum on rope
- [ ] **Grapple style — rappel** — fixed point, A/D steer, W/S rope length
- [ ] **Aim assist** — small cone snap (T)
- [ ] **Hook zip** — Shift + click, FOV punch
- [ ] **Grapple stick** — MMB toggle, wall walk
- [ ] **Slingshot** — dynamic charge
- [ ] **Rope visual** — Verlet tube, per-slot color, wall collision

#### Grinding

- [ ] **Grind rails**
- [ ] **Rail switching**
- [ ] **Grind visual** — sparks, low camera, speed effect

#### Gravity

- [ ] **Standard gravity** — default downward pull
- [ ] **Alter gravity** — **(style)** walls / ceiling / both

#### Flight

- [ ] **Fly mode — creative (Minecraft)**
- [ ] **Fly mode — rocket**
- [ ] **Glider** — hold key, reduce terminal velocity (T)

#### Camera + Feel

- [x] **Procedural camera motion** — jump, land, hard land, roll, slap [full]
      - [x] MotionVisualComponent with 5 states
      - [x] Camera accumulator API (no direct eye/cam writes)
      - [x] Hold system for FOV + roll
      - [x] FallBehaviorComponent routes roll / slap / hard landing
      - [x] Dynamic scaling with fall speed (slap intensity, roll duration/thrust)
- [x] **Fall behavior state machine** — soft / hard / slap / roll by input + speed
      - [x] roll on Ctrl tap (fall_speed scaled duration + thrust)
      - [x] hard landing on Ctrl held through fall
      - [x] slap on no input at high speed, with screen pulse
      - [x] movement_lockout during recovery, declared on player.gd
      - [x] mouse curve steering during roll
- [x] **Idle breathing** — subtle pitch/roll while still
- [x] **Head bob** — walk / sprint / crouch / prone (T)
      - [x] per-stance frequency + intensity
      - [x] fade-out on stop
      - [x] auto-suspend while sliding
- [x] **FOV punch** — brief FOV change on impulse events
      - [x] hold_camera_fov API
      - [x] used by dash
- [x] **Camera roll hold** — hold_camera_roll API
- [x] **Speed screen effect** — fullscreen shader with profiles
      - [x] SpeedEffectProfile resource
      - [x] speed_effect.gdshader
      - [x] priority system (10 levels)
      - [x] slap heartbeat pulse
      - [x] boost / suppress / override APIs
- [ ] **Idle actions** — procedural micro-poses (look around, dance)
- [ ] **Lean / peek** — Q/E, camera rolls, wall-aware offset (T)
- [x] **Camera roll** on wall run / slide / grapple (T)
- [ ] **View sway + shake** — weapon sway, screen shake on impacts
- [ ] **Speed FOV** — FOV scales with current speed
- [ ] **Crosshair** — UI dot, orange when grapple available
- [ ] **Fall damage signal** — emits `hard_landed(velocity)`

#### Environment interaction

- [ ] **Swimming / diving** — buoyancy, water exit, oxygen signal
- [ ] **Gravity zones** — areas that override global gravity
- [ ] **Conveyor / current zones**
- [ ] **Surface material system** — friction, bounce, footstep per surface

#### Architecture / Reusability

- [x] **Feature toggles** — every mechanic has `enabled` (T)
- [x] **Runtime-tunable** via @export
- [x] **Component-based split** — Player / SensorHub / Movement / Dash / HeadBob / MotionVisual / SpeedEffect
- [x] **Centralized sensor hub** — one ray cast per sensor per frame
- [x] **Camera accumulator API** — components write through player.add_*
- [x] **Motion helper API** — play_jump / play_landing / play_hard_landing / play_roll / play_slap
- [x] **Null-safe component refs** — scene runs even with missing components
- [x] **Data-driven profile resource** — SpeedEffectProfile
- [ ] **Signal-driven** — no hardcoded anim/audio/UI in components
- [ ] **Hierarchical FSM** — one state per mechanic, clean transitions
- [ ] **Network-ready movement** — client prediction + reconciliation
- [ ] **Performance budget** — explicit N casts / M allocations per frame
- [ ] **Split MovementComponent** — see Future-TODO below

---

### Part 2 — Systems + UI + Audio

#### Player systems

- [ ] **Health component** — `take_damage`, `heal`, `died` signal
- [ ] **Stamina component** — sprint / wall-run / jump / ledge / glide drain (S)
- [ ] **Armor / shield layer**
- [ ] **Invulnerability frames** after hit (S)
- [ ] **Regeneration** — delay + rate (S, T)
- [ ] **Damage direction indicator** — HUD arrow

#### Interaction

- [ ] **Interactable base class** + `interact()` method
- [ ] **Interaction raycast** + prompt UI
- [ ] **Pickups** — health, ammo, collectibles
- [ ] **Doors** — open, close, lock, keyed
- [ ] **Levers / switches / buttons**

#### Inventory & weapons

- [ ] **Inventory data model** — `Array[ItemStack]`
- [ ] **Weapon base class** — fire / reload / aim / holster
- [ ] **Weapon slots** — hotbar, scroll wheel
- [ ] **Pickup drops on death** (T, optional)

#### HUD

- [ ] **Health bar** with damage flash
- [ ] **Stamina bar**
- [ ] **Ammo counter**
- [ ] **Objective / waypoint marker**
- [ ] **Damage vignette** on low HP
- [ ] **Hitmarker** (T)

#### Menus

- [ ] **Pause menu** — Resume / Settings / Quit
      - needs `player.set_mouse_look(false)` on open
      - needs `movement.enable_bunny_hop = false` on open
- [ ] **Settings menu** — sens, FOV, audio, keybinds
- [ ] **Main menu**
- [ ] **Loading screen**

#### Audio

- [ ] **Audio manager autoload** — bus routing, volume persistence
- [ ] **Footsteps** — surface-aware
- [ ] **Jump / land / wall-run whoosh**
- [ ] **Hook fire / rope tension / swing whoosh**
- [ ] **Dash whump**
- [ ] **Grind rail loop**
- [ ] **Ground pound impact**
- [ ] **Glider wind loop**
- [ ] **Ambient city loops**
- [ ] **NPC voice barks**
- [ ] **Music** — menu + gameplay

#### Persistence

- [ ] **Save / load** — position, health, inventory
- [ ] **Settings persistence** — `user://settings.cfg`
- [ ] **Checkpoints + spawn points**

---

### Part 3 — World

#### Three-layer map

- [ ] **-1_Dungeon** — underground, linear, combat-focused
- [ ] **0_Swarm City** — mid-level streets + rooftops, traversal-focused
- [ ] **1_FreeRoam** — upper city, exploration + collectibles

#### Level building kit

- [ ] **Modular building pieces**
- [ ] **Modular road kit**
- [ ] **Modular props**
- [ ] **Interiors module set**
- [ ] **Grapple-friendly high points**

#### Level systems

- [ ] **Trigger volumes** — checkpoint, kill zone, cutscene
- [ ] **Jump pads / launch pads**
- [ ] **Ziplines between rooftops**
- [ ] **Grind rails**
- [ ] **Navigable AI mesh**

#### Environment

- [ ] **Day / night cycle**
- [ ] **Weather** — rain, fog, snow
- [ ] **Post-processing** — SSAO, SDFGI, glow

---

### Part 4 — Multiplayer

- [ ] **Networking foundation** — ENet peer, server-authoritative
- [ ] **MultiplayerSynchronizer** on player + hooks
- [ ] **Movement reconciliation** — client prediction
- [ ] **Lobby system**
- [ ] **Chat + voice** (T, optional)
- [ ] **Scoreboard + teams**
- [ ] **Matchmaking** or server browser

---

### Cross-cutting TODOs

- [ ] **Full doc pass** on every component (`##` on all exports)
- [ ] **Unit tests** for damage / stamina / gravity
- [ ] **Controller support** — deadzones, vibration, glyphs
- [ ] **Accessibility** — FOV slider, bob toggle, colorblind modes
- [ ] **Localization** — `tr()` on every UI string
- [ ] **Build pipeline** — Linux + Windows export presets
- [ ] **Steam / itch.io deployment**

---

### Session log

| # | Feature | Component | Status | Notes |
|---|---|---|---|---|
| 1 | Player skeleton | `player.gd` | ✅ | thin frame owner |
| 2 | Sensor hub | `sensor_hub.gd` | ✅ | single-cast per frame |
| 3 | Walk | `movement_component.gd` | ✅ | |
| 4 | Sprint | `movement_component.gd` | ✅ | |
| 5 | Ground jump | `movement_component.gd` | ✅ | |
| 6 | Double jump | `movement_component.gd` | ✅ | |
| 7 | Variable jump | `movement_component.gd` | ✅ | |
| 8 | Coyote time | `movement_component.gd` | ✅ | |
| 9 | Jump buffer | `movement_component.gd` | ✅ | |
| 10 | Crouch | `movement_component.gd` | ✅ | Hold / Toggle |
| 11 | Prone | `movement_component.gd` | ✅ | Hold / Toggle |
| 12 | Slide | `movement_component.gd` | ✅ | Timer / Hold |
| 13 | Crouch-sprint | `movement_component.gd` | ✅ | optional toggle |
| 14 | Space-stands | `movement_component.gd` | ✅ | |
| 15 | Bunny hop | `movement_component.gd` | ⚠️ | needs polish |
| 16 | Air mouse steer | `movement_component.gd` | ✅ | with smoothing |
| 17 | Mouse look | `player.gd` | ✅ | with menu toggle |
| 18 | Camera accumulators | `player.gd` | ✅ | add_eye_* / add_cam_* |
| 19 | MotionVisual | `motion_visual_component.gd` | ✅ | jump/land/hard/roll/slap |
| 20 | Head bob | `head_bob_component.gd` | ✅ | stance-aware + idle |
| 21 | Landing detection | `movement_component.gd` | ✅ | peak fall speed tracking |
| 22 | Speed effect | `speed_effect_component.gd` | ✅ | priority system |
| 22 | Speed profile | `speed_effect_profile.gd` | ✅ | resource |
| 22 | Speed shader | `speed_effect.gdshader` | ✅ | assumed |
| 23 | Dash | `dash_component.gd` | ✅ | scope / directional / FOV |
| 24 | Priority wiring | `player.gd` | ✅ | movement → dash → visuals → camera |
| 25 | Fall behavior | `fall_behavior_component.gd` | ✅ | roll / hard / slap / soft |
| 25 | Movement lockout | `player.gd` + `movement_component.gd` | ✅ | declared field + tick |
| 26 | Wall run (horizontal) | `wall_run_component.gd` | ✅ | session 1 — sin wave removed |
| 27 | Wall slide | `wall_run_component.gd` | ⚠️ | session 2 — bug: head-on wall + look-away |
| 28 | Wall slide bug fix | `wall_run_component.gd` | ✅ | head-on fallback + look-away lock + slide_max_time |
| 29 | Sin wave cleanup | `wall_run_component.gd` | ✅ | dead exports removed |
| 30 | Ladder climb | `ladder_climb_component.gd` | ✅ | + jump-off + facing check (bonus) |
| 31 | Vertical wall run + end-slide | `wall_run_component.gd` | ✅ | session 5 |
| 32 | Wall run + ladder patches | `wall_run_component.gd`, `ladder_climb_component.gd` | ✅ | Ctrl+Space fix, ladder centering, Ctrl slide down |
| 33 | Wall jump | `wall_run_component.gd` | ✅ | look-direction launch, airtime cap, variable cut |
| 34 | Wall / ladder dash caps | `dash_component.gd` | ✅ | per-contact limits + look-direction dash when mounted |
| 35 | Ladder variable jump | `ladder_climb_component.gd` | ✅ | parallel to wall-jump cut |
| 36 | Q-turn wall jump | `wall_run_component.gd` | ✅ | per-side sign flip, session-gated, grace window |
| 37 | Variable wall jump — forward cut | `wall_run_component.gd` | ✅ | horizontal impulse now scales on tap |

**Next session:** 
**Queued after:** 

**Known issues**

  
**Future-TODO**


Cleaner, easier to tune, easier to debug.

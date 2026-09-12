# Who Am I? — Design & Build Plan (v2, decisions locked 2026-09-12)

Working title: **Who Am I? Party** (repo: `WhoAmISteam`, local folder: `C:\Users\savas\WhoAmISteam`). A 2–8 player online party game for Steam that recreates the living-room game "Who am I?": everyone gets a picture and a name stuck to their forehead and has to guess who they are by asking yes/no questions. Cartoony, sketchy characters. Voice-first, silly on purpose.

This document is the single source of truth for the one-shot implementation. Every decision below was confirmed by the owner in the question catalog and is final unless changed here.

---

## 0. Decisions at a glance

| Area | Decision | Why |
|---|---|---|
| Engine | **Godot 4, latest stable (install via winget, pin version in `docs/STEAM.md`), GDScript** | Text-based scenes/scripts, built-in multiplayer, no build step, best fit for GodotSteam. |
| Steam | **GodotSteam GDExtension** + **GodotSteam MultiplayerPeer**; dev on App ID **480** | Steamworks not started yet; checklist in `docs/STEAM.md`. |
| Networking | **Host-authoritative listen server**; Godot high-level multiplayer | Simplest correct model for ≤8 friends. Host = lobby admin. |
| Transport | **Abstracted**: ENet (dev/LAN) and Steam P2P (release) | Every milestone testable with 2–3 local instances, Steam closed. |
| Game mode | **Classic only** (turn-based, yes/no votes) | Owner decision. No Party mode. |
| Judging a guess | **Everyone votes**, 15 s window, majority of votes cast, tie = wrong, writer's vote counts double | Maximizes engagement; writer breaks ties because they know the answer. |
| Post-it | **Picture and name** (name in marker font under the photo) | Owner decision. Text-only fallback if no picture. |
| Assignment | Right neighbor in seat order, **direction alternates each round** | Matches the real game, pairs change. |
| Round rules | **Configurable in lobby settings** (turn timer, writing time, round end mode, etc.) | Owner decision, see §3.0. |
| Scoring | Solve order (5,4,3,2,1…) + **writer bonus** if target solves within 3 turns | Rewards fair names. |
| Categories | None. Anything goes. | Friends police themselves. |
| Voice | **In-game voice, toggled at lobby creation** (Steam Voice API); push-to-talk or open mic per client | Owner decision. Own milestone (M7). |
| Camera | **First person, third-person toggle (V)**; own post-it renders blank in third person | Owner decision. |
| Extras in v1 | **Emotes** (wave, laugh, facepalm) and **throwable props** (pillows, ball) | Owner decision. |
| Art | **Procedural primitives** + cel shader + wobbly ink outline; **Kenney Furniture Kit (CC0)** for the room | No artist needed; sketchy look hides low fidelity. |
| Players | **2–8** (2 allowed for testing; 3+ recommended in UI) | Owner decision. |
| Testing | **Bots (`--bot`) + gdUnit4 unit tests** | Max one-shot reliability. |
| Platform | **Windows only** for v1 | One preset, one depot. |
| Launch | **Steam Playtest → Early Access** | Playtest catches bugs before reviews count; EA builds hype. |
| Languages | **English only** at launch; strings in CSV for later DE/TR | Owner decision. |
| Disconnect | Round continues, player's turns are skipped, **they can rejoin** and reclaim their slot | Owner decision. |
| Host leaves | Session ends with a clear message; no host migration in v1 | Owner decision. |
| Late join | Spectate (walk, sit, chat, **vote on questions**), play from next round | Owner decision. |
| Duplicates | Host warns the second writer; they may keep it | Owner decision. |
| No name in time | Auto-pick first candidate; else random from a built-in list of 200 famous people | Owner decision. |

---

## 1. Game pillars

1. **It's the living-room game, not a quiz app.** Walk, sit, look at your friends' silly covered faces. Rules live in the room (whiteboard, TV).
2. **Your friends are the content.** Uploading a photo of Kevin from work beats any celebrity. The writing phase must make that effortless.
3. **A doodle that came alive.** Wobbly black outlines, flat cel colors, paper post-its, marker-font UI.
4. **Zero friction with friends.** Steam invite → in the room in 10 seconds. Ready up, admin starts, done.

---

## 2. Player experience (end to end)

1. **Launch** → Main menu (Host game / Join friend / How to play / Customize / Settings / Quit). First launch shows a 4-card "How to play".
2. **Host** opens **Lobby settings** (§3.0), then creates a Steam lobby (friends-only). Players join via Steam overlay invite or friends list "Join game". Joining puts you straight into the **living room**, which *is* the lobby.
3. **In the room** you walk, jump, crouch, sit, chat, emote, throw pillows, and customize your character at the **wardrobe mirror** (E). The **whiteboard** shows the rules; the **TV** shows lobby status and settings, then timers/turns/votes during play.
4. Everyone presses **Ready** (F). The **admin** sees "Start round" when all are ready, or can force start with ≥2 players.
5. **Countdown** (5 s) with a one-line rules recap on the TV.
6. **Writing phase** (default 90 s): each player is assigned a **target** (right neighbor; direction alternates per round). Panel: "Write a name for *Sarah*". Type a name → Wikipedia candidates with thumbnails → pick one, or **Upload** a photo, or **Paste URL**. If the host detects another writer already chose the same person, a warning appears ("Someone already picked this") and the writer may keep it. Preview shows the real post-it (picture + name). **Confirm** locks it. Phase ends when all confirmed or the timer runs out (auto-pick first candidate, else random famous name).
7. **Sticking phase** (3 s): post-its animate onto foreheads with a squeak. Faces covered except the mouth. You see everyone's except your own.
8. **Guessing phase**: turn order = seat order, starting with the player left of the admin, rotating each round. The active guesser asks yes/no questions **out loud** (in-game voice). All other players (including spectators) press **YES / NO / shrug**. The answer resolves when every eligible voter has voted or after 10 s: majority wins; **a tie counts as NO**; shrugs don't count; zero YES and zero NO = "no answer", the guesser re-asks. A NO passes the turn. A YES keeps it. The guesser may press **"I know it!"** and say the name; a **15 s guess vote** opens for everyone else: majority of votes cast decides, tie = wrong, the writer's vote counts double. Wrong passes the turn. Correct = solved; the post-it flips, confetti, the solved player now sees their own picture. Each turn has a **turn timer** (admin-set, default 60 s); expiry passes the turn.
9. **Round end** per lobby setting: all solved, or time limit reached, or every player used their max turns. Unsolved post-its are revealed.
10. **Scoreboard**: solve-order points + writer bonus. Back to the room; admin can start the next round with the same settings.

---

## 3. Systems design

### 3.0 Lobby settings (`LobbySettings` dictionary, host-owned, shown on TV)

| Setting | Range | Default |
|---|---|---|
| `max_players` | 2–8 | 8 |
| `friends_only` | bool | true |
| `voice_enabled` | bool | true |
| `writing_time_s` | 60–180 | 90 |
| `turn_timer_s` | 30–180 | 60 |
| `round_end_mode` | `all_solved` / `time_limit` / `max_turns` | `all_solved` |
| `round_time_min` | 5–30 (when `time_limit`) | 15 |
| `max_turns_per_player` | 3–10 (when `max_turns`) | 5 |
| `answer_vote_window_s` | 5–20 | 10 |
| `guess_vote_window_s` | 10–30 | 15 |

Set before creating the lobby; the admin can change them in the room while in LOBBY state. Each client chooses its own voice input mode in Settings: push-to-talk (default key **T**) or open mic. **V** is the camera toggle.

### 3.1 State machine (host-authoritative, `Game.gd` autoload)

```
LOBBY → COUNTDOWN → WRITING → STICKING → GUESSING → REVEAL → LOBBY
```

- Host owns `state`, `round_index`, `direction`, `assignments`, `timer_end_unix`, `turn_order`, `turn_index`, `turns_used{}`, `solved{}`, `scores{}`, `vote_state`.
- Full snapshot `sync_state(dict)` on every transition and every 1 s during timed phases (late joiners/rejoins recover instantly).
- Clients send **intents** only (`request_ready`, `vote_answer`, `claim_guess`, `vote_guess`, …). Host validates phase and sender.
- **Spectators** (joined mid-round): no post-it, no turn, may vote on answers and guesses.
- **Rejoin**: a peer that disconnects mid-round keeps a **held slot** (Steam ID, or name+token on ENet) until the round ends. Their turns are skipped while away. On rejoin the host restores seat, post-it (image re-sent to all *except them*), turn position, score.
- Host leaves → `HostLeft` dialog, back to menu.

### 3.2 Network layer (`Net.gd` autoload)

- `Net.host(transport, settings)`, `Net.join(transport, address_or_lobby)`; transport = `ENetTransport` or `SteamTransport`, both implementing `create_peer() -> MultiplayerPeer`.
- CLI flags: `--host`, `--join 127.0.0.1`, `--port 7777`, `--name Bob`, `--bot`, `--no-steam`, `--settings path.json`.
- Player spawning via `MultiplayerSpawner`; transform, head look, crouch, emote, prop-held state via `MultiplayerSynchronizer` (unreliable, 20 Hz, interpolated).
- Props: host-simulated `RigidBody3D`, transforms replicated; clients send `request_grab(prop_id)` / `request_throw(dir, force)`.
- **Large payload channel** (`ImageTransfer.gd`): 16 KB chunks, host reassembles, re-encodes (§3.5b), fans out to the allowed recipient set.

### 3.3 Message protocol (all `any_peer` + `call_remote` unless noted)

| Direction | RPC | Notes |
|---|---|---|
| C→H | `request_ready(ready)` | LOBBY |
| C→H | `request_start()` | admin only |
| C→H | `update_settings(dict)` | admin only, LOBBY |
| H→All | `sync_state(state)` | reliable full snapshot |
| C→H | `submit_customization(dict)` | validated ranges |
| H→All | `apply_customization(peer, dict)` | |
| C→H | `check_name(target, normalized_name, wiki_title)` | duplicate warning → `H→C name_warning(is_dup)` |
| C→H | `submit_name(target, name, image_id)` | WRITING, writer must own target |
| C→H / H→C | `image_chunk(id, i, n, bytes)` | 16 KB; host skips the target |
| H→All | `postit_ready(target, id, name)` | name omitted for the target |
| C→H | `vote_answer(answer)` | GUESSING, non-active players and spectators, −1/0/1 |
| H→All | `answer_result(guesser, yes, no, shrug, verdict)` | verdict ∈ YES/NO/NONE |
| C→H | `claim_guess()` | active guesser |
| C→H | `vote_guess(correct)` | everyone except guesser; writer weight 2 |
| H→All | `guess_result(guesser, correct, yes_w, no_w)` | |
| H→All | `solved(peer, rank)` | sends image+name to that peer |
| H→All | `reveal_all()` | REVEAL |
| C→H | `request_sit(chair_id)` / `request_stand()` | host-authoritative occupancy |
| C→H | `request_grab(prop)` / `request_throw(dir, force)` | |
| Any | `emote(id)` | relayed |
| Any | `chat(text)` | ≤ 200 chars, relayed |
| C→H / H→All | `voice_frame(bytes)` | Steam Voice compressed, ≤ 8 KB, only if `voice_enabled` |

### 3.4 Image pipeline (`ImageSearch.gd`, `ImageNormalize.gd`, `ImageTransfer.gd`)

1. **Wikipedia OpenSearch** `https://{lang}.wikipedia.org/w/api.php?action=opensearch&search={q}&limit=5&format=json` → titles (600 ms debounce).
2. **REST summary** per title → `thumbnail.source` / `originalimage.source`, plus description ("American singer"). `User-Agent: WhoAmIParty/1.0 (+github.com/Smoke8832/WhoAmISteam)`.
3. Candidate grid (≤5). Language switch in the panel (EN default).
4. Optional **Google Custom Search JSON API** (`searchType=image`) with the player's own key + CX in Settings; off by default.
5. **Upload** (`FileDialog`, PNG/JPG/WEBP) or **Paste URL**.
6. Normalize: decode → center-crop square → 512 px → JPEG q80 → step down to ≤ 200 KB.
7. Preview renders the real `PostIt` scene (picture + name). **Confirm** sends.
8. Fallback list `assets/data/famous_names.json` (200 entries with Wikipedia titles) for auto-pick.

### 3.5 Secrecy rules (host-enforced)

- The target peer receives no image chunks and no name until `solved` or `reveal_all`. `postit_ready` sent to the target omits the name.
- The target's local `PostIt` renders blank with a "?" (relevant in third-person view and screenshots).
- Spectators receive everything.

### 3.5b Security model ("no file ever crosses the wire")

Threat model: a friend's machine may be compromised, or someone joins with a modified client. Nobody must be able to push a dangerous file, crash other players, or reach into their PCs.

**Pictures are pixels, not files**
- Nothing chosen from disk is transmitted. The writer's client **decodes** the file into an `Image` and **re-encodes** a fresh JPEG (512², ≤ 200 KB). Filenames, EXIF, metadata, container are discarded.
- The **host decodes and re-encodes again** before fanning out. Clients only ever receive host-produced JPEG bytes.
- One wire format: **JPEG**. Receivers check magic bytes (`FF D8 FF`), parse SOF dimensions, reject > 1024² *before* decoding (decompression bombs). Decode failures discard the transfer → blank post-it.
- Received bytes stay in memory as `Texture2D`. Any cache goes to `user://cache/<uuid>.jpg`. Nothing is executed, shell-opened, or written outside `user://`.

**Transfer limits and authorization (host-side)**
- Only the assigned writer, only during WRITING, only for their own target; `get_remote_sender_id()` must match. One active transfer per peer, 2 attempts per round.
- Declared total ≤ 200 KB, chunk ≤ 16 KB, ≤ 13 chunks, unique in-range indices, 20 s timeout. Violation drops the transfer; 3 violations kick.
- Clients accept `image_chunk`, `postit_ready`, `sync_state`, `*_result`, `solved`, `reveal_all` **only from peer 1**.
- All payloads type/range-checked (customization enums, votes ∈ {−1,0,1}, chat ≤ 200, voice frame ≤ 8 KB, settings ranges). Unknown/malformed calls ignored and logged. Godot RPCs only invoke annotated methods: no remote code path.

**Fetching from the internet (writer's own client only)**
- Wikipedia pinned to `*.wikipedia.org` / `upload.wikimedia.org`, HTTPS, cert validation.
- Paste-URL: `https://` only, ≤ 3 redirects, 10 s timeout, `Content-Type: image/*`, abort > 8 MB. Hosts resolving to 127/8, 10/8, 172.16/12, 192.168/16, 169.254/16, ::1, fc00::/7 refused (no SSRF into the player's LAN).
- Google key stored in `user://settings.cfg`, never sent to peers.

**Local file picking**: filter `.png .jpg .jpeg .webp`, 20 MB read cap, extension *and* magic bytes must agree, decode in memory. Never lists, moves, deletes files.

**Voice**: frames are opaque compressed audio passed to Steam's decompressor; size-capped; only accepted when `voice_enabled` and sender is a known peer.

**Text and identity**: chat renders with BBCode off and no clickable links; names 3–16 safe chars. Steam authenticates identity. Friends-only lobbies; host can kick; kicked Steam IDs blocked for the session. No central server stores anything.

### 3.6 Living room (`LivingRoom.tscn`)

~12 × 10 m. Ring of 8 seats (3-seat sofa, 2 armchairs, 3 chairs) around a coffee table; rug; wall TV (SubViewport UI: settings/lobby list → timers, votes, turn, scoreboard); whiteboard with doodled rules; wardrobe mirror (customizer); window with painted sky; plants, lamp, shelf. **Kenney Furniture Kit** (CC0 GLB) through the toon shader; gaps filled with CSG/primitives.
`Chair.tscn`: `Area3D` zone + `Seat` marker; occupancy host-authoritative.
Props: 3 pillows + 1 ball (`RigidBody3D`, host-simulated), E to grab, LMB to throw, gentle bonk sound, no damage.

### 3.7 Player controller (`Player.tscn`)

`CharacterBody3D`. WASD (4 m/s), Shift sprint (6 m/s), Space jump (squash-stretch), C/Ctrl hold crouch (capsule 60 %), E interact, LMB throw, **V camera toggle** (first ↔ third person, third-person camera on a spring arm behind/above; own post-it blank), **T push-to-talk** (or open mic), Tab scoreboard, Enter chat, F ready, **1/2/3 emotes** (wave, laugh, facepalm), Esc menu. Sitting snaps to seat, locks movement, free look ±90°, stand with E/Space. Procedural motion only (idle sway, walk bob, jump squash, emote poses via tweened transforms). Remote players interpolated; head yaw/pitch replicated; mouth opens while speaking (voice level) or chatting.

### 3.8 Character rig & customization (`CharacterRig.tscn`, `Customization.gd`)

Primitives: capsule torso, sphere head (3 shapes via scale), stubby capsule limbs, mitten hands. Face quad with layered textures: eyes (6), brows (4), mouth (4 + open/closed frames), blush toggle. Hair (8) and facial hair (5) from scaled spheres/boxes/cones. Accessories: glasses (3), headset, cap, beanie, bow, earrings. Colors: skin (12), hair (10), shirt (16) + pattern (plain/stripes/dots), pants (8), shoes (6). Name tag (Steam persona default, 3–16 chars). Serialized as a Dictionary of ints; `user://character.cfg`; synced through the host; Randomize button; live rotating preview.

### 3.9 Look: "living doodle"

Cel shader (2-band + rim). Inverted-hull ink outline with time-quantized vertex noise (wobbles at ~8 fps). Subtle paper-grain post-process.
**Post-it** (`PostIt.tscn`): 0.34 m quad, slightly bigger than the head, random tilt ±8°, bottom edge just above the mouth, tape strip on top, photo in a hand-drawn frame, **name in marker font beneath the photo**, spring-hung (flaps on jump/crouch), flips to "GOT IT!" when solved.
UI: marker display font, paper panels, rounded ink borders; YES green / NO red / shrug grey as thick marker buttons; vote tallies drawn as tally marks.

### 3.10 UI screens

Main menu · How to play (4 cards) · Settings (audio, voice input mode + PTT key, mic device, mouse sensitivity, invert Y, Wikipedia language, optional Google key) · Lobby settings (§3.0) · Lobby HUD (player list, ready checks, admin Start, kick) · Customizer · Write panel (name, candidates, duplicate warning, upload, URL, preview, confirm, timer) · Guess HUD (whose turn, turn timer, YES/NO/shrug, "I know it!", guess vote Correct/Wrong with countdown, tallies) · Chat · Scoreboard · Pause menu · Host-left / Disconnected / Rejoining dialogs.

### 3.11 Voice (`Voice.gd`, M7)

Steam Voice API through GodotSteam: `startVoiceRecording`, `getAvailableVoice`, `getVoice` → compressed frames → `voice_frame` RPC via host → receivers `decompressVoice` into an `AudioStreamGenerator` per speaker (positional `AudioStreamPlayer3D` at the speaker's head, mild falloff so the whole room is audible). Speaking indicator on name tag; mouth animation driven by amplitude. Push-to-talk (T) or open mic with a simple gate. Per-player mute in the scoreboard. Disabled entirely when `voice_enabled` is false; on ENet dev builds a stub sends nothing (or optionally raw Opus via a fallback later).

### 3.12 Audio

Squeaky post-it stick, paper flap, marker scribble, jump boing, chair creak, yes/no dings, tally scratch, confetti, pillow bonk, lobby ukulele loop. CC0 or synthesized with `AudioStreamGenerator`.

### 3.13 Steam integration

- Steamworks partner signup + app fee (USD 100) → App ID. Until then **480**. Checklist in `docs/STEAM.md`.
- Init on launch; if Steam isn't running → ENet menu (host by IP / join by IP).
- Lobbies: `createLobby(FriendsOnly, max_players)`, lobby data (version, settings summary), rich presence `connect` string for friends-list "Join game", overlay invite button.
- Steam Cloud for `character.cfg` (auto-cloud config).
- Launch path: **Playtest** app (free, invite-based) → **Early Access** on the main app. Windows depot only.
- Store: capsule art set, ≥5 screenshots, trailer, tags (Party, Multiplayer, Casual, Funny), UGC content descriptor, "in-game voice chat" listed.

---

## 4. Repository layout

```
project.godot
export_presets.cfg
addons/godotsteam/                # GDExtension
addons/godotsteam_multiplayer_peer/
addons/gdUnit4/
src/
  autoload/   Game.gd  Net.gd  Settings.gd  Locale.gd  Audio.gd  Voice.gd
  net/        Transport.gd  ENetTransport.gd  SteamTransport.gd  ImageTransfer.gd  Validation.gd
  round/      RoundManager.gd  Assignment.gd  Scoring.gd  Voting.gd  ImageSearch.gd  ImageNormalize.gd  LobbySettings.gd
  player/     Player.tscn/.gd  CameraRig.gd  CharacterRig.tscn/.gd  Customization.gd  PostIt.tscn/.gd  Emotes.gd
  world/      LivingRoom.tscn  Chair.tscn/.gd  Prop.tscn/.gd  Wardrobe.tscn  TvScreen.tscn  Whiteboard.tscn
  ui/         MainMenu  HowToPlay  SettingsMenu  LobbySettingsPanel  LobbyHud  Customizer  WritePanel  GuessHud  Chat  Scoreboard  PauseMenu  Dialogs
  shaders/    toon.gdshader  outline.gdshader  paper_post.gdshader  postit.gdshader
assets/       models/ (Kenney GLB)  textures/faces/  fonts/  sfx/  music/  data/famous_names.json
locale/       strings.csv
tools/        run_local.ps1 (host + N clients, optional --bot)   bot.gd
tests/        gdUnit4: Assignment, Scoring, Voting, ImageNormalize, Validation, state transitions
docs/         PLAN.md  STEAM.md (partner signup, App ID, depots, playtest, EA checklist)
```

---

## 5. Build order (each milestone independently runnable and verifiable)

| # | Milestone | Done when |
|---|---|---|
| M0 | Install Godot (winget), project skeleton, autoloads, ENet transport, CLI flags, `run_local.ps1`, gdUnit4 | Two instances join and see each other's placeholder capsules moving; tests run. |
| M1 | Living room (Kenney kit), first/third-person controller (V), jump, crouch, sit (host occupancy), chat, emotes, throwable props | Three instances walk, sit, emote, throw pillows, chat; no jitter. |
| M2 | Character rig from primitives, toon + wobbly outline, post-it prototype, customizer at the wardrobe, save + sync | Customization visible to others; survives relaunch. |
| M3 | Lobby settings panel, ready/admin/kick, countdown, state machine + `sync_state`, TV/whiteboard, How-to-play, spectator + rejoin slots | LOBBY→COUNTDOWN→placeholder phases→LOBBY with 3 instances; a client killed and relaunched rejoins its slot. |
| M4 | Writing phase: assignment ring, write panel, Wikipedia search, upload, URL, duplicate warning, normalize, chunked transfer, secrecy, auto-pick fallback | Post-its (picture + name) on everyone; debug overlay proves the target holds no image/name. |
| M5 | Guessing: turn order, turn timer, answer votes (tie = NO), claim + 15 s guess vote (writer ×2, tie = wrong), scoring, round end modes, reveal, scoreboard | Full round with 3 instances + bots under each round-end mode; unit tests for Voting/Scoring pass. |
| M6 | Steam: GodotSteam init, lobbies, invites, rich presence, Steam transport, ENet fallback, Steam Cloud | Two Steam accounts play a round through an invite on App ID 480. |
| M7 | In-game voice: Steam Voice capture/playback, PTT/open mic, speaking indicator, mute, lobby toggle | Two Steam accounts hear each other; mouths animate; toggle off silences everything. |
| M8 | Polish: SFX/music, settings, English strings in CSV, Windows export preset, `STEAM.md`, playtest build to a Steam branch | Shippable Windows build uploaded to the Playtest app. |

**One-shot tactics**
- Each milestone ends with `tools/run_local.ps1 -Clients 2 -Bot` (bots auto-ready, auto-write "Michael Jackson", auto-vote, auto-claim) so the flow runs without a human.
- Host authority + full-snapshot sync removes desync bugs by construction; rejoin is just "receive the snapshot".
- Steam and voice are wired last; everything before runs on ENet with a voice stub.
- No rigged animation, no custom modelling: procedural motion, primitives, CC0 furniture.
- Pure logic (assignment ring incl. 2-player case and direction flip, scoring, vote resolution incl. ties/weights/no-votes, normalize, validation) has unit tests.

---

## 6. Edge-case rulebook (decided)

| Situation | Rule |
|---|---|
| 2 players | They write for each other. All votes come from the single other player (weight 2 as writer, so a tie is impossible). |
| Player disconnects mid-round | Slot held until round end; turns skipped; post-it stays visible to others; on rejoin (same Steam ID / ENet name+token) seat, post-it, turn position and score are restored. Not back by round end → revealed with the rest, no points. |
| Host disconnects | Session ends, "Host left" dialog, back to menu. |
| Late joiner | Spectator: walks, sits, chats, votes on answers and guesses; gets a post-it from the next round. |
| Writer doesn't confirm | Auto-pick first candidate; if nothing typed, random entry from the 200-name list. |
| Same person picked twice | Second writer warned (normalized name or Wikipedia title match), may keep. |
| Answer vote tie | NO; turn passes. Shrugs don't count. No YES/NO at all → "no answer", guesser asks again (turn timer keeps running). |
| Guess vote tie | Wrong; turn passes. Writer's vote counts double. No votes at all → wrong. |
| Turn timer expires | Turn passes; any open vote is cancelled. |
| Round time limit / max turns reached | Round ends; unsolved revealed; solved keep their points. |
| Guesser is the only non-spectator left unsolved | Their turns continue until round-end rule triggers; others vote as normal. |
| Image transfer fails | Text-only post-it (name in marker font). |
| Voice disabled in lobby | No capture, no `voice_frame` RPCs accepted, PTT key does nothing. |

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Wrong/no search result | Candidate grid with descriptions; upload + URL; text-only fallback; auto-pick list. |
| Inappropriate images | Friends-only lobbies; Wikipedia curated; host kick; UGC descriptor on store. |
| Wikimedia rate limits | Proper User-Agent, per-session cache, ≤5 candidates. |
| Steam P2P NAT failures | Steam relay handles NAT; ENet host-by-IP fallback. |
| GodotSteam/Godot version mismatch | Versions pinned in `docs/STEAM.md`; addon files committed. |
| Steam Voice latency/quality | Steam's codec is tuned for this; positional playback with mild falloff; mute per player; toggle off at lobby creation. |
| Third-person leaks own post-it | Own post-it renders blank locally by construction; target never has the bytes anyway. |
| Rejoin identity spoofing on ENet | Rejoin token issued at first join; Steam builds use Steam ID. |
| Art looks cheap | Wobbly outline is the brand; tight palette; post-it physics carries the humor. |
| Early Access reviews | Playtest first with friends; fix before EA. |

---

## 8. Out of scope for v1 (parked)

Party mode (no turns), host migration, public matchmaking, controller support, Linux/macOS builds, Steam Deck verification, achievements, Workshop parts, proximity-only voice, additional languages (CSV ready).

---

## 9. Next actions when the owner says "build"

1. Install latest stable Godot 4 via winget; record the version.
2. Clone `github.com/Smoke8832/WhoAmISteam` to `C:\Users\savas\WhoAmISteam`; commit `docs/PLAN.md`.
3. Execute M0 → M8 in order, running `run_local.ps1 -Bot` and unit tests at each milestone.
4. Owner tasks in parallel: Steamworks partner signup, app fee, App ID, Playtest app; capsule art review.

---

## 10. Build status (2026-09-12, overnight build)

| Milestone | Status | Verified by |
|---|---|---|
| M0 skeleton, ENet, lobby loop | done | bots, tests |
| M1 living room, seats, props, emotes, third person | done | bots + screenshots |
| M2 toon/ink look, characters, post-it, wardrobe | done | CharacterViewer, bots |
| M3 lobby settings, kick, spectators, rejoin, TV, whiteboard, how-to-play | done | bots, `tools/test_rejoin.ps1` |
| M4 writing phase, image pipeline, chunked transfer, secrecy | done | bots (3 paths), secrecy log, tests |
| M5 guessing: turns, votes, claims, scoring, round-end modes | done | bots (full rounds), tests |
| M6 Steam lobbies, invites, rich presence, P2P peer | code complete | live: init, lobby create/join, presence, timeout. **Not verified: P2P handshake between two accounts** |
| M7 in-game voice (Steam Voice + PCM fallback), mute, indicators | code complete | bots exercise the PCM relay; **not verified: real microphones / Steam Voice codec** |
| M8 sounds, options, export, upload script | done | `exports/windows/WhoAmIParty.exe` smoke-tested |

Deviations from the plan: unit tests use an in-house runner (`tests/TestMain.tscn`) instead of gdUnit4;
the Steam transport is an in-house `SteamPeer` (the official MultiplayerPeer only ships as a custom Godot
4.5 editor); voice also works over LAN with raw PCM so it could be tested without Steam.

Known follow-ups: Windows .ico for the executable, Steam Cloud config, store assets, a two-account Steam
test, a real-microphone voice test, and tuning the ink post-process on the far wall.

# Steam setup and release checklist

## Pinned versions

| Component | Version | Source |
|---|---|---|
| Godot | 4.7.2 stable (`winget install GodotEngine.GodotEngine --version 4.7.2`) | winget |
| GodotSteam GDExtension | 4.22.1 (Steamworks SDK 1.65, `compatibility_minimum 4.4`) | https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.22.1-gde |
| Steam transport | in-house `SteamPeer.gd` (MultiplayerPeerExtension over Steam Networking Messages) | `src/net/` |
| Kenney Furniture Kit | 1.0 (CC0) | https://kenney.nl/assets/furniture-kit |

Only `addons/godotsteam/win64/` is committed (Windows-only v1). Re-download the plugin zip and copy other platform folders if Linux/macOS builds are ever added.

Why in-house transport: the official GodotSteam MultiplayerPeer ships only as a custom Godot editor build (latest for Godot 4.5.1), not as a GDExtension for 4.7.

## App IDs

- Development: **480** (Spacewar). A `steam_appid.txt` containing `480` next to the executable/editor makes the Steam client attach without a real App ID.
- Production: set in `src/autoload/SteamInit.gd` once the Steamworks App ID exists.

## Owner checklist (outside the code)

1. Steamworks partner signup: https://partner.steamgames.com — company/individual details, tax interview, bank details, app fee (USD 100 per app, recoupable).
2. Create the app → note the **App ID**. Create a **Playtest** sub-app from the main app's page (free, invite-based).
3. Store page drafts: title, short description, about, tags (Party, Multiplayer, Casual, Funny, Co-op), content descriptor for user-generated content (players upload images), note in-game voice chat.
4. Assets: header capsule 920×430, small capsule 462×174, main capsule 1232×706, vertical capsule 748×896, library capsule 600×900, library hero 3840×1240, library logo 1280×720, page background 1438×810, ≥5 screenshots 1920×1080, trailer.
5. Build upload: SteamPipe via `steamcmd` (`tools/steam_upload.ps1` will be generated at M8) → set the build live on the Playtest app's default branch.
6. Playtest with friends → fix → Early Access on the main app.

## Steam transport (implemented in M6)

- `SteamService` (autoload) wraps the GodotSteam singleton dynamically (`Engine.get_singleton("Steam")`),
  so the game still compiles and runs LAN-only if the extension is missing. It skips init when
  `--no-steam`, `--bot`, `--host` or `--join` is used.
- `SteamTransport` creates a friends-only lobby (host) or joins one (client). `SteamPeer` is a GDScript
  `MultiplayerPeerExtension` over ISteamNetworking P2P: channel 0 data (`[channel][mode][godot packet]`),
  channel 1 control (HELLO / WELCOME / BYE). Star topology, Godot server relay on. Only lobby members
  get their P2P sessions accepted.
- Rich presence `connect` = `+connect_lobby <id>` (friends-list "Join game"), `steam_player_group`.
  Overlay invites arrive via `join_requested`. Pause menu → "Invite Steam friends".
- Invites: the pause menu opens an in-game friends list (`src/ui/InvitePanel.gd`) that calls `inviteUserToLobby`
  directly, because `activateGameOverlayInviteDialog` needs the Steam overlay and the overlay only injects
  when the game is launched through Steam (not from the editor or a bare exe). The panel also shows the
  lobby id; a friend can paste it into the main menu Join field (a 12+ digit number is treated as a lobby id).
  When the overlay is available an "Open Steam overlay" button appears too. Verified live: friends list
  populated from the real Steam client on 2026-09-12.
- Dev flags: `--steam-host`, `--steam-join <lobby_id>`.

### Verified on 2026-09-12 with the live Steam client (App ID 480)

- init, persona, lobby create, lobby join, rich presence, client timeout when the host does not answer.
- NOT yet verified: the P2P handshake and gameplay between two different Steam accounts. Steam does not
  deliver P2P packets from an account to itself, so this needs two PCs / two accounts:
  1. PC A: start the game, **Host a room (Steam friends)**.
  2. PC B (friend of A): Steam friends list → Join game (or accept the overlay invite from A's pause menu).
  3. Both should appear in the room; run a round. Check `%APPDATA%\Godot\app_userdata\Who Am I? Party\logs`
     or the console for `[steampeer] HELLO` / `WELCOME` lines.

## Building and uploading (M8)

1. Export templates: Godot 4.7.2 `Godot_v4.7.2-stable_export_templates.tpz` → extract
   `windows_release_x86_64.exe`, `windows_debug_x86_64.exe` (+ `_console` variants, `version.txt`) into
   `%APPDATA%\Godot\export_templates\4.7.2.stable\` (already done on the dev PC).
2. `.\tools\export_windows.ps1` → `exports\windows\WhoAmIParty.exe` + `.pck` + `libgodotsteam...dll` +
   `steam_api64.dll`. The script also launches the exe once as a LAN host to smoke-test it.
3. Steamworks: create the app and a Windows depot; set the launch option to `WhoAmIParty.exe`.
4. `.\tools\steam_upload.ps1 -AppId <id> -DepotId <depot> -Username <login> -Branch playtest`
   (writes `exports\steam\app_build.vdf`, runs `steamcmd +run_app_build`). `steam_appid.txt` is excluded
   from the depot on purpose: on Steam the client provides the App ID.
5. In Steamworks set the build live on the Playtest app's default branch; invite testers.

Before the first real upload: replace `APP_ID := 480` in `src/autoload/SteamService.gd` and the
`steam_appid.txt` (dev only) with the real App ID, and bump `application/config/version` in `project.godot`.

## In-game Steam features (M6/M7)

- Lobbies: `Steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, max_players)`, lobby data `version`, `settings`.
- Invites: `Steam.activateGameOverlayInviteDialog(lobby_id)`; rich presence `connect` = `+connect_lobby <id>`; command line `+connect_lobby` is honored on launch.
- Transport: Steam Networking Messages, channel 0 reliable / channel 1 unreliable; host = lobby owner.
- Voice: `startVoiceRecording` / `getVoice` / `decompressVoice` into `AudioStreamGenerator` per speaker.
- Cloud: enable Steam Cloud auto-config for `%LOCALAPPDATA%/Godot/app_userdata/Who Am I? Party/character.cfg` and `settings.cfg`.

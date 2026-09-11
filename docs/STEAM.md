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

## In-game Steam features (M6/M7)

- Lobbies: `Steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, max_players)`, lobby data `version`, `settings`.
- Invites: `Steam.activateGameOverlayInviteDialog(lobby_id)`; rich presence `connect` = `+connect_lobby <id>`; command line `+connect_lobby` is honored on launch.
- Transport: Steam Networking Messages, channel 0 reliable / channel 1 unreliable; host = lobby owner.
- Voice: `startVoiceRecording` / `getVoice` / `decompressVoice` into `AudioStreamGenerator` per speaker.
- Cloud: enable Steam Cloud auto-config for `%LOCALAPPDATA%/Godot/app_userdata/Who Am I? Party/character.cfg` and `settings.cfg`.

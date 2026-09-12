# Who Am I? Party

The living-room guessing game, online. 2–8 friends walk around a cartoon living room, sit in a circle, stick a picture and a name on the next person's forehead, and ask yes/no questions until everyone knows who they are.

Built with **Godot 4.7.2** (GDScript) and **GodotSteam 4.22.1**. Windows first. Design doc: [docs/PLAN.md](docs/PLAN.md). Steam setup and release: [docs/STEAM.md](docs/STEAM.md).

## Play it

- **Steam friends**: start the game with Steam running → *Host a room (Steam friends)* → Esc → *Invite Steam friends* (or friends use *Join game* in their friends list).
- **LAN / no Steam**: *Host a room (LAN)* on one PC, *Join* with the host's `ip:port` on the others (shown in the host's Esc menu).

Controls: WASD move · Space jump · C crouch · E sit / pick up / wardrobe · click throw · V third person · T talk · F ready · Tab players · Enter chat · Esc menu. During guessing: Q ask, G "I know it!", Y / N / U vote.

## Develop

```powershell
# one host + two bot clients over ENet, fast phases, screenshots into screenshots\<stamp>\
.\tools\run_local.ps1 -Clients 2 -Bot -Fast -Duration 70

# unit tests (63)
.\tools\run_tests.ps1

# rejoin test (kills a client mid-round and relaunches it with the same token)
.\tools\test_rejoin.ps1

# Windows build -> exports\windows\ (needs the 4.7.2 export templates)
.\tools\export_windows.ps1

# character / UI / model previews
godot_console --path . tools/CharacterViewer.tscn -- --closeup --out screenshots/chars.png
godot_console --path . tools/UiViewer.tscn -- --scene res://src/ui/Customizer.tscn --out screenshots/ui.png
```

Command-line flags (after `--`): `--host`, `--join <ip>`, `--port`, `--name`, `--bot`, `--fast`, `--no-steam`, `--steam-host`, `--steam-join <lobby>`, `--rejoin-token <t>`, `--screenshot-dir <dir>`, `--quit-after <s>`.

## Layout

- `docs/` – plan and Steam notes
- `src/autoload/` – `Settings`, `Locale`, `Audio`, `SteamService`, `Net`, `Game`, `Voice`
- `src/net/` – ENet and Steam transports, `SteamPeer`
- `src/round/` – `RoundManager` (phases, writing, votes, scoring), image search/normalize, famous names
- `src/player/` – controller, `CharacterRig`, `FacePainter`, `PostIt`, customization
- `src/world/` – `RoomBuilder`, living room, chairs, props, TV
- `src/ui/` – menus, HUD, write panel, guess HUD, wardrobe, options, scoreboard
- `src/shaders/` – toon shader, ink post-process
- `tools/` – launchers, bot, generators, export/upload scripts
- `tests/` – unit tests run by `tests/TestMain.tscn`

## Credits

- Furniture: [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit) (CC0)
- Fonts: Patrick Hand, Nunito (OFL, via Google Fonts)
- Steam integration: [GodotSteam](https://godotsteam.com) (MIT)
- Pictures: Wikipedia / Wikimedia Commons thumbnails, fetched by each player at play time

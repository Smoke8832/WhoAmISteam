# Who Am I? Party

The living-room guessing game, online. 2–8 friends walk around a cartoon living room, sit in a circle, stick a picture and a name on the next person's forehead, and ask yes/no questions until everyone knows who they are.

Built with **Godot 4.7.2** (GDScript) and **GodotSteam 4.22.1**. Windows first.

## Run it

```powershell
# one host + two clients over ENet (no Steam needed), 40 seconds, bots play and save screenshots
.\tools\run_local.ps1 -Clients 2 -Bot -Duration 40

# unit tests
.\tools\run_tests.ps1
```

Open the project in the Godot editor (`godot --path .`) to play by hand: **Host a room (LAN)** in one window, **Join** with `127.0.0.1` in another.

## Layout

- `docs/PLAN.md` – the design and build plan (source of truth)
- `docs/STEAM.md` – Steamworks setup, pinned versions, release checklist
- `src/autoload/` – `Settings`, `Locale`, `Audio`, `Net`, `Game`, `Voice`
- `src/net/` – transports (ENet / Steam), image transfer
- `src/round/` – round rules, voting, scoring, image search
- `src/player/` – controller, character rig, customization, post-it
- `src/world/` – the living room, chairs, props
- `src/ui/` – menus, HUD, panels
- `tools/` – local launcher, test runner, bot
- `tests/` – unit tests (`test_*.gd`, run by `tests/TestMain.tscn`)

## Credits

- Furniture: [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit) (CC0)
- Fonts: Patrick Hand, Nunito (OFL, via Google Fonts)
- Steam integration: [GodotSteam](https://godotsteam.com) (MIT)

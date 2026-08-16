# MoleUX

Native **SwiftUI** front-end for [Mole](https://github.com/tw93/mole) — deep clean
and system maintenance for macOS.

MoleUX does **not** reimplement cleanup logic. It runs the Mole CLI (`mo` /
`mole`) and its Go helpers (`status-go`, `analyze-go`) as subprocesses, so path
protection, dry-run semantics, and Trash routing stay identical to the terminal
tool. Two sections do their own work — see
[Where the GUI does its own work](#where-the-gui-does-its-own-work).

Independent project, not affiliated with or endorsed by the Mole authors.

## Requirements

- macOS 14+
- Swift 5.9+ (Xcode CLT or full Xcode)
- The Mole CLI, via Homebrew or a local checkout

```bash
brew install mole
```

## Run (dev)

```bash
git clone https://github.com/AleCyriaco/MoleUX.git
cd MoleUX
./Scripts/run.sh
```

Or:

```bash
export MOLE_PATH=/path/to/mole   # optional override
swift run
```

## Package `.app`

```bash
./Scripts/package_app.sh
open dist/MoleUX.app
```

When a workspace clone is present the packager copies the whole CLI tree
(`mole`, `bin/`, `lib/`) into `MoleUX.app/Contents/Resources/mole` and smoke-tests
it. The entry script resolves `bin/` and `lib/` relative to itself, so the tree
has to travel together — shipping the entry script alone produces a copy that
fails on every subcommand.

The bundled copy is only a **fallback**. The app prefers, in order: the path set
in Settings, `$MOLE_PATH`, a Homebrew or `~/.local` install, a workspace
checkout, then the bundle. Each candidate is probed with `mole help` before it is
accepted, so a broken install is skipped instead of breaking every command.

## Features

| Section | Behavior |
|--------|----------|
| **Dashboard** | Health ring, CPU/RAM/disk/battery cards, quick actions, recent sessions |
| **Clean** | Dry-run preview + confirmed clean, streamed live from the CLI |
| **Optimize** | Dry-run / run optimize |
| **Uninstall** | Multi-select table, dry-run preview, confirmed removal via `mo uninstall` |
| **Purge** | Dry-run / run purge of project build artifacts |
| **Installers** | Native scan for leftover .dmg/.pkg/.mpkg/.iso/.xip, removal through Trash |
| **Analyze** | Disk cards, path picker, drill-down, or launch the TUI |
| **Live Status** | Polls `status --json` (per-core, top processes, network) |
| **History** | Sessions + deletions from `history --json` |
| **Settings** | CLI path override, admin access, refresh interval, version |

## Architecture

```
MoleGUI (SwiftUI)
   │
   ├─ MoleCLI.swift  ──►  mo status --json / bin/status-go --json
   │                 ──►  mo history --json, mo uninstall --list
   │                 ──►  mo clean|optimize|uninstall|analyze …
   │
   ├─ InstalledAppScanner  ──►  /Applications inventory (list only)
   ├─ InstallerScanner     ──►  leftover installer images → Trash
   ├─ AdminAccess          ──►  sudo/Touch ID readiness
   │
   └─ AppState       ──►  live timer, navigation, per-section activities
```

### Long-running work

Runs belong to the section, not to the view. SwiftUI tears the detail view down
whenever the sidebar selection changes, so anything kept in `@State` — streamed
output, a half-built selection, an analyze result — would die with it.

`AppState.activities` holds one `Activity` per section: label, streamed output,
exit code, elapsed time, and a cancellation token. Consequences:

- **Switching tabs never interrupts anything.** Come back and the output is still
  filling in; a finished run keeps its result and timing until you clear it.
- **Sections run in parallel.** `MoleCLI` uses a concurrent queue, and each run
  carries its own token, so a 50-second clean and an analyze scan proceed at the
  same time. Measured: two concurrent cleans finish in 1.00× the time of one.
  A section still refuses to start a second copy of its own command.
- **Cancel is per-section.** `cancel(token)` terminates only that run.
- **A spinner marks every busy tab** — in the sidebar, on the Dashboard quick
  cards, and in the section's own output header next to the elapsed time.

### Where the GUI does its own work

Two sections cannot go through the CLI, because the CLI paths they would use are
interactive terminal screens with no non-interactive mode:

- **Installers** — `mo installer` is a keyboard selector. Piped into a window app
  it draws its menu, reads EOF, and exits having removed nothing. The GUI scans
  the same directories and extensions itself and removes through the Trash, which
  is the CLI's own default. `.zip` is skipped: the CLI only accepts a zip after
  looking inside for an app payload, and a wrong guess would offer up an archive.
- **App inventory** — `mo uninstall --list` stays the source of truth (it knows
  Homebrew cask names). Some CLI builds abort partway through that scan, so a
  native `/Applications` scan is merged in to fill the gaps. The uninstall itself
  is always `mo uninstall`.

## Administrator access

System caches and a few optimize tasks need root. A window app has no controlling
terminal, so `sudo` has no way to prompt for a password and those steps are
skipped. Two supported ways out, both surfaced in Clean, Optimize, and Settings:

- **Touch ID for sudo** (preferred) — the button runs Mole's own `mo touchid`,
  which adds `pam_tid` to the sudo PAM stack. After that, sudo authenticates
  through the system's biometric sheet, no terminal involved.
- **Run in Terminal** — hands the command to Terminal, where the CLI asks for the
  password natively.

The app never collects or stores a password.

## Safety

- Destructive actions default to **preview first**.
- Clean, Purge, Installers, and Uninstall each require an explicit confirmation.
- Uninstall answers the CLI's `[y/N]` prompt only after the GUI dialog is
  confirmed — that dialog is the real gate.
- Path protection and Trash routing are owned by the upstream CLI.

## Troubleshooting

**Uninstall lists fewer apps than `mo` does in the terminal.** Some 1.50.0 builds
exit non-zero partway through `uninstall --list`; an app with an unknown size
aborts the loop. The GUI salvages the partial payload and merges in a native
scan, so the list stays complete. Running `mo update` fixes it at the source.

**Buttons that open Terminal do nothing.** macOS gates Apple Events. Allow MoleUX
under System Settings › Privacy & Security › Automation. The app surfaces the
denial in its error banner.

**Clean skips system caches.** That is the admin access case above.

## Layout

```
Package.swift
Scripts/run.sh              dev build + launch
Scripts/package_app.sh      builds dist/MoleUX.app
Sources/MoleGUI/
  MoleGUIApp.swift
  AppState.swift            navigation + per-section activities
  ContentView.swift
  Models/                   CLI JSON payloads, Activity
  Services/
    MoleCLI.swift           subprocess bridge to mo/mole
    InstalledAppScanner.swift
    InstallerScanner.swift
    AdminAccess.swift
  Views/
```

## License

GPL-3.0, matching upstream Mole. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)
— the latter covers what the packaged `.app` bundles and what that means if you
redistribute it.

## Credits

[Mole](https://github.com/tw93/mole) by [tw93](https://github.com/tw93) does all
the real work. MoleUX only gives it a window.

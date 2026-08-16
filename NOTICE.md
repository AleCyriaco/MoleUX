# Notice

MoleUX is a native macOS front-end for [Mole](https://github.com/tw93/mole) by
[tw93](https://github.com/tw93). It is an independent project and is not
affiliated with or endorsed by the Mole authors.

## Licensing

MoleUX is licensed under the **GNU General Public License v3.0** — the same
license as Mole. See [LICENSE](LICENSE).

MoleUX does not reimplement Mole's cleanup logic. It runs the `mole` CLI as a
subprocess, so path protection, dry-run semantics, and Trash routing stay owned
by upstream.

`Scripts/package_app.sh` copies the Mole CLI tree into
`Mole.app/Contents/Resources/mole` when a workspace checkout is present. The
resulting `.app` therefore contains GPL-3 licensed code from Mole. If you
distribute that bundle, GPL-3 obligations apply to it: ship the license and make
the corresponding source available. Building it for your own machine carries no
such obligation.

## Trademarks

"Mole" is used to identify the upstream project this front-end drives. See
Mole's [TRADEMARK.md](https://github.com/tw93/mole/blob/main/TRADEMARK.md) for
the upstream position on its name and marks.

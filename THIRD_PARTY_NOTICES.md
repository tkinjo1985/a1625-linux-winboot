# Third-party source and artifact policy

This repository contains original host-side glue and documentation. It does
not vendor the following upstream repositories or redistribute their built
artifacts. `windows-native/Get-PinnedSources.ps1` fetches public source into an
ignored `third_party` directory and checks out these exact revisions:

| Project | Source | Revision | Upstream license information |
|---|---|---|---|
| openra1n | <https://github.com/mineek/openra1n> | `4595a5333e4134ade77b43fb2259e880b85801ee` | No top-level license file was found at the pinned revision; inspect upstream before redistributing or modifying its source. |
| Palera1nWin | <https://github.com/pwnapplehat/Palera1nWin> | `b62a087839048e4bc9a496519ccd7aca1df3246f` | MIT; see the upstream `LICENSE`. Its vendored components may have separate terms. |
| Hoolock Linux docs | <https://github.com/HoolockLinux/docs> | `ac579429c2bf842afb9b4aea8ed944a9afbe067e` | MIT for the repository files, with a separate license noted for `binaries/Pongo.bin`. This project does not redistribute that binary. |
| Hoolock Linux kernel | <https://github.com/HoolockLinux/linux> | `958481f87fee0949ff6a9a4af77f7eb6dac8a149` | Linux kernel licensing; see upstream `COPYING` and `LICENSES`. |

Other runtime inputs—including PongoOS/Pongo binaries, m1n1, Apple firmware or
IPSW content, Linux packages, Codex CLI releases, and CA bundles—must be
obtained by each user from their legitimate upstream source and reviewed under
their respective terms. They must not be committed to this repository.

The Rust uploader's dependencies and resolved versions are listed in
`windows-native/pongo-uploader/Cargo.toml` and `Cargo.lock`; their own licenses
continue to apply.

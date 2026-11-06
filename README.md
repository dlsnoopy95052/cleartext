# ClearText

A small macOS app that turns messy plain-text files into a clean, collapsible, navigable document.

- Detects headings (numbered `1)` / `1.` / `1.2`, Roman, lettered, `Chapter 3`, ALL CAPS, Markdown, underlined) and nests them.
- Joins hard-wrapped lines into paragraphs; keeps list numbering; shows page breaks.
- Alternating row colors, font and heading style options, selection highlight color.
- Temporary reading bookmark (never modifies the original file).
- Export as Markdown.

## Install

Download `ClearText-Installer.pkg` from the [latest release](../../releases/latest) and run it; it installs ClearText into `/Applications`.

- Requires macOS 14 or newer. The published build is for **Intel (x86_64)** Macs; on Apple silicon, build from source (below).
- The installer and app are **not signed or notarized**. If macOS blocks it, right-click the `.pkg` and choose **Open**, or use *System Settings → Privacy & Security → Open Anyway*.

## Build

Requires macOS 14+ and the Xcode command line tools.

```sh
./build_app.sh        # builds ClearText.app next to the script
./make_icon.sh        # regenerates Resources/ClearText.icns
./make_installer.sh   # builds dist/ClearText-Installer.pkg
```

The app is built for the architecture of the Mac you build on and is not signed or notarized.

## License

MIT — see [LICENSE](LICENSE).

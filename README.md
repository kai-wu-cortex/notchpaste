# NotchPaste

A macOS clipboard history app that lives in your notch and gracefully steps aside when other notch apps run.

**Status:** v0.1 MVP under development.

## Requirements

- macOS 14 Sonoma or later
- A MacBook with a notch (Pro/Air 14"/16" 2021+)
- Xcode 15+ for development

## Development

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate `NotchPaste.xcodeproj` from `project.yml`. The generated project is git-ignored.

```bash
brew install xcodegen
xcodegen generate
open NotchPaste.xcodeproj
```

Build from CLI:

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test
```

## License

MIT — see [LICENSE](LICENSE).

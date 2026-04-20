# Webtoon Lens iOS

Webtoon Lens is an iOS 18+ prototype for fast webtoon image translation that stays inside App Store rules:

- Safari Web Extension for one-tap overlays while reading webtoons in Safari.
- App Intent/Shortcuts handoff for screenshots from other apps.
- Local OCR with Vision.
- Text-only translation calls to a configurable backend.
- Series glossary memory for stable names, powers, places, and concepts.

## Generate the Xcode project

This repository uses XcodeGen so the project file can be generated reproducibly on macOS:

```sh
brew install xcodegen
cd webtoon-lens-ios
xcodegen generate
open WebtoonLens.xcodeproj
```

No Mac? Use [WINDOWS_NO_MAC.md](WINDOWS_NO_MAC.md). The repository includes GitHub Actions workflows that run on macOS cloud runners.

Before running on a real device, replace the sample bundle identifiers and App Group in:

- `project.yml`
- `App/Resources/WebtoonLens.entitlements`
- `SafariExtension/Native/WebtoonLensSafariExtension.entitlements`
- `Core/Sources/SharedAppGroupStore.swift`

The placeholder App Group is `group.com.example.webtoonlens`.

## Backend contract

Configure the backend URL in the Settings tab. The app posts text-only payloads to:

```http
POST /v1/webtoon/translate
```

The payload includes source language `auto`, target language `fr`, OCR segments, reading boxes, series id, style prompt, and locked glossary terms. The response returns translated segments and optional glossary updates.

If no backend URL is configured, the app uses a local preview client that echoes detected text with a `[fr]` prefix. That keeps OCR, overlays, Safari messaging, and Shortcuts testable before the server exists.

## What is intentionally not implemented

iOS does not allow a third-party App Store app to continuously read and draw over other apps. Outside Safari, the supported flow is: user triggers a Shortcut that captures a screenshot, Webtoon Lens receives the image, then opens the app with the translated result.

## Suggested validation on macOS

```sh
xcodegen generate
xcodebuild test -scheme WebtoonLens -destination 'platform=iOS Simulator,name=iPhone 16'
```

Safari Web Extension and Shortcut behavior must also be tested on a physical iPhone.

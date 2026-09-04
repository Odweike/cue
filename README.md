# VideoPlayer

Native macOS video player built with SwiftUI and AppKit.

## Current milestone

- Open a local video from the welcome screen or with `Command-O`.
- Play, pause, seek, change volume, and enter full screen with native controls.
- Playback is isolated behind `PlaybackEngine` so AVFoundation can be replaced by libmpv.
- Subtitle and transcription domain boundaries are present, but recognition is not implemented yet.

## Run

```sh
tuist generate
open VideoPlayer.xcworkspace
```


# VideoPlayer

Native macOS video player built with SwiftUI and AppKit.

## Current milestone

- Open a local video from the welcome screen or with `Command-O`.
- Use the draggable floating panel to play, pause, seek, skip, and change volume.
- The floating panel remembers its position between launches.
- Playback is isolated behind `PlaybackEngine` so AVFoundation can be replaced by libmpv.
- Subtitle and transcription domain boundaries are present, but recognition is not implemented yet.

## Run

```sh
tuist generate
open VideoPlayer.xcworkspace
```

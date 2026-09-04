# Cue

Native macOS video player built with SwiftUI and AppKit.

## Current milestone

- Open a local video from the welcome screen or with `Command-O`.
- Use the draggable floating panel to play, pause, seek, skip, and change volume.
- The in-player floating panel can be moved and resized from its corner, and remembers its layout.
- Playback is isolated behind `PlaybackEngine` so AVFoundation can be replaced by libmpv.
- Subtitle and transcription domain boundaries are present, but recognition is not implemented yet.

## Run

```sh
tuist generate
open VideoPlayer.xcworkspace
```

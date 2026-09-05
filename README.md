# Cue

Native macOS video player built with SwiftUI and AppKit.

## Current milestone

- Open a local video from the welcome screen or with `Command-O`.
- Use the draggable floating panel to play, pause, seek, skip, and change volume.
- The in-player floating panel can be moved and resized from its corner, and remembers its layout.
- Play MKV, MP4, MOV, and other common formats through the embedded LGPL build of libmpv.
- Playback stays isolated behind `PlaybackEngine`, with the native AVFoundation engine retained as a fallback implementation.
- Import and display up to two SRT, VTT, or ASS subtitle tracks at once.
- Customize and persist independent subtitle styles for the first and second visible tracks.
- Generate time-coded subtitles locally with Apple Speech and save them beside the video as SRT.

## Run

```sh
tuist generate
open VideoPlayer.xcworkspace
```

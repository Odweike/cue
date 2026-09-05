# Cue

Native macOS video player built with SwiftUI and AppKit.

## Current milestone

- Open a local video from the welcome screen, with `Command-O`, or by dropping it into the window.
- Use the draggable floating panel to play, pause, seek, skip, and change volume.
- The in-player floating panel can be moved and resized from its corner, and remembers its layout.
- Play MKV, MP4, MOV, and other common formats through the embedded LGPL build of libmpv.
- Playback stays isolated behind `PlaybackEngine`, with the native AVFoundation engine retained as a fallback implementation.
- Import and display up to two SRT, VTT, or ASS subtitle tracks at once.
- Export any imported or generated subtitle track as SRT.
- Customize and persist independent subtitle styles for the first and second visible tracks.
- Generate time-coded subtitles locally with Apple Speech and save them beside the video as SRT.
- Recognize subtitles progressively while watching, including restart after seeking.
- Review bundled open-source notices and LGPL terms from the Help menu.

## Run

```sh
tuist generate
open VideoPlayer.xcworkspace
```

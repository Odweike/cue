# Cue

Native macOS video player built with SwiftUI and AppKit.

## Current milestone

- Open a local video from the welcome screen, with `Command-O`, or by dropping it into the window.
- Use the draggable floating panel to play, pause, seek, skip, and change volume.
- The in-player floating panel can be moved and resized from its corner, and remembers its layout.
- Play MKV, MP4, MOV, and other common formats through the embedded LGPL build of libmpv.
- Playback stays isolated behind `PlaybackEngine`, with the native AVFoundation engine retained as a fallback implementation.
- Choose embedded audio tracks and adjust audio/video synchronization.
- Adjust scaling, aspect ratio, crop, rotation, playback speed, hardware decoding, deinterlacing, and picture color controls.
- Import and display up to two SRT, VTT, or ASS subtitle tracks at once.
- Export any imported or generated subtitle track as SRT.
- Customize and persist independent subtitle styles for the first and second visible tracks.
- Save, apply, and delete named style profiles containing both subtitle track styles.
- Extract audio from supported video containers, including MKV, then generate time-coded subtitles locally with Apple Speech and save them beside the video as SRT.
- Show download progress when macOS needs to prepare an on-device language package.
- Recognize subtitles progressively while watching, including restart after seeking.
- Review bundled open-source notices and LGPL terms from the Help menu.

## Run

```sh
tuist generate
open VideoPlayer.xcworkspace
```

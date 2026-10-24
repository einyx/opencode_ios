# Focus Mode and Voice-First Input

Status: under implementation and validation. The two features go into the same PR, are configured independently, and keep the existing interaction by default.

## Product Decisions

**Large-screen Focus mode**: allows the user to switch to a compact single-content-area experience on their own, reusing the existing narrow-screen Chat / Files / Settings tabs, as well as the behavior where opening Markdown in the chat replaces the body while keeping the bottom input area. The layout preference is Auto / Focus, with Auto as the default. Rotating the device to landscape does not automatically exit Focus mode.

**Voice-first input**: a new device-local switch, off by default. Once enabled, the draft is readable and scrollable, supports tapping to place the caret and long-pressing to select text, but the software keyboard does not pop up automatically. The system keyboard is summoned only when the user taps the keyboard button; tapping to dismiss it, a successful send, or switching sessions returns to the keyboard-free state. The existing microphone interaction and the recording/sending policies continue to apply; toggling the setting itself neither starts recording nor sends a message.

**System paste entry point**: when voice-first is enabled, a paste button with a blue icon is provided, whose background blends into the voice bar, replacing the large rounded blue box with a white icon; at the same time, a tap target of no less than 44 × 44 pt is preserved. The native `UIPasteControl` continues to be used, without shrinking the native control in a way that would break the actual paste tap. The first version receives text; images keep using the existing photo library entry point. Pasting only updates the draft — it does not auto-send, and it does not summon the keyboard when the keyboard has not been requested.

Not included: side-by-side multiple sessions, quoting selected passages of the body, orientation lock, hinge-specific interactions, or custom system keyboard extensions.

## User Interface

The Settings screen provides the layout mode and voice-first input. The main interface toolbar provides a quick layout entry point; Focus mode still has an explicit entry point back to Auto.

```text
┌─────────────────────────────────────────┐
│ Session / Back   Current session  Layout│
├─────────────────────────────────────────┤
│                                         │
│    Chat messages or Markdown preview    │
│                                         │
├─────────────────────────────────────────┤
│ Draft: speech transcript, pasted text   │
│ Mic     Waveform        Paste   Keyboard│
│ Photos     Draft              Send      │
└─────────────────────────────────────────┘
```

When voice-first is off, the existing input habits are preserved with no additional keyboard entry point. When it is on, the paste and explicit-edit entry points go into the existing voice bar and the waveform is shortened without taking an extra row; on narrow screens, crowding is not solved by shrinking the tap target. The microphone and send keep their existing slots, and the arrangement of the temporary recording, retry, and stop buttons continues to follow the existing [Composer specification](../../design.md#composer).

## Technical Design

### Local Preferences and Effective Layout

The layout preference and the voice-first switch are stored on the device, persist across restarts, and are not configured separately per server host.

| Available system space | Auto | Focus |
| --- | --- | --- |
| compact | existing single-content layout | single-content layout |
| regular | existing three-column layout | single-content layout |

Keep the system `horizontalSizeClass` as-is and derive the app's own effective layout state. The root navigation, preview placement, message card layout, session entry points, and edge gestures all read the effective layout uniformly; system sheets / popovers and the like continue to follow the real device environment.

The orientation declaration uses the general `UISupportedInterfaceOrientations` (portrait plus both landscape orientations); iPad keeps the four-state override and does not rely on the generated key that only has `~iphone`. Whether the rotation actually happens is still determined by the running window size and the UI tests.

Switching the layout should preserve the current session, the text draft, the current file preview, pending images, and any in-progress recording. Prefer keeping the identity of the chat and input views, and avoid introducing a generic workspace refactor for these two features. Map the in-chat preview and the center-column preview in both directions, and do not misread a disappearing view as the user switching sessions.

### Input Focus and Paste

The `UITextView` bridge separates caret focus from the software keyboard request. When voice-first is on and the keyboard has not been requested, a custom zero-height `inputView` replaces the software keyboard, so a tap can still obtain input focus and show the caret; only an explicit tap on the keyboard button restores the system keyboard. The caret is not focused automatically when unfocused, and the Chinese `markedTextRange` protection still applies. The keyboard request state is not persisted, to avoid the keyboard being summoned automatically on the next launch.

Use Apple's `PasteButton` or `UIPasteControl`, and do not read `UIPasteboard.general.string` directly from an ordinary button. The system control handles clipboard access and the pasteable state.

When unfocused, an empty draft is written directly and an existing draft is appended at the end with a newline; after the caret has been positioned by a tap, the text is inserted at the current caret or selection, and the insertion position is not determined by whether the software keyboard is visible. Multiple text blocks keep their order; while Chinese input is still being composed, the not-yet-committed content must not be replaced. Async paste and voice results must be merged into the latest draft, preserving the original host / session ownership, and must not overwrite everything with an old snapshot.

When the send fails and the host, session, and selection are still the same, the sent text is restored while keeping the content added during the wait; deduplication applies only to the complete original text, or to text prefixed by the original plus a newline, and must not rely on arbitrary substrings. Sent and newly added images are deduplicated and merged by attachment ID, so images are not lost when the text revision changes.

## Implementation and Acceptance Order Within a Single PR

1. Preference storage and effective layout resolution, covering Auto / Focus × compact / regular.
2. The layout entry point, two-way preview migration, and chat/recording lifecycle continuity.
3. Voice-first focus control, the system paste control, and draft merging.
4. Targeted unit tests and iPhone / iPad simulator UI regression.
5. Independent code review and privacy review; after fixes, rerun the affected checks.
6. Submit a single PR without merging; the real iPhone / iPad are accepted by the user after deployment.

The acceptance focus is: default behavior regression; switching between Auto / Focus in iPad landscape and portrait; tapping the draft in chat and in Markdown does not pop up the keyboard; explicit editing, dismissal, and sending; the real system paste path does not request extra authorization, summon the keyboard, or send; existing drafts are not lost when running concurrently with a transcript; Chinese composition input; the setting persists across restarts.

## Verification Boundary

Duo verification requires Xcode 27.1 and the iOS 27.1 runtime; the tests must cover the real inner and outer screens as well as rotation, and an ordinary iPad simulator cannot substitute for Duo posture acceptance. If opening/closing control or screenshots are limited by the simulator interface, the scenarios already executed and the ones still pending must be listed explicitly.

The simulator is used for interface and state behavior verification. Real microphone capture, cross-app pasting, and the feel of tap targets in the hand are confirmed by the user on a real device.

References: [Apple layout preparation guide](https://developer.apple.com/iphone-duo/prepare/), [PasteButton](https://developer.apple.com/documentation/swiftui/pastebutton), [UIPasteControl](https://developer.apple.com/documentation/uikit/uipastecontrol).

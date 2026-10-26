# Artwork placement

Where each hand-drawn scene belongs in OpenCodex, and why — grounded in Apple's
HIG patterns (Loading, Onboarding, Feedback, Entering data).

## The rules

1. **Placeholder in the content region, never chrome.** HIG *Loading*: "consider
   showing placeholder text, graphics, or animations as content loads". The art
   goes where the content would have been — centred in the empty area, above or
   beside the message. Never in the tab bar, never behind the composer.
2. **Art means "nothing here yet", not "coming".** A real load gets a progress
   indicator (HIG *Loading*: "you can use system-provided components… to show
   that loading is ongoing"). Artwork is for the *absent* state.
3. **Every artwork surface keeps its action next to it.** HIG *Onboarding*:
   "Teach through interactivity… provide an interactive onboarding experience
   where people can safely test an action". The drawing is the invitation; the
   button is the point.
4. **Show it where the work happens, not in a separate tour.** HIG *Onboarding*:
   "consider providing a collection of context-specific tips… display these
   instructions near that area". So the art sits on the surface that needs the
   host / the permission / the voice engine — not in a carousel.
5. **Ask for permission where the feature is used.** HIG *Onboarding*:
   "present a permission request when people first access the specific function
   that relies on private data". The Health consent sheet is the artwork's
   home, and it already follows this rule.
6. **One idea per surface.** A drawing that means three things means nothing.
   Don't reuse a scene across unrelated empty states.
7. **Small.** 120–160 pt, ink on paper, never a full-bleed hero in a
   utility surface. The scene reads at a glance and stays out of the way.

## The map

| Scene | Surface | Why there |
|---|---|---|
| **EmptyChatArt** (hand reaching) | Chat, no session selected | The content region is empty and the next action (pick a session) is right below it. Already wired. |
| **NoSessionsArt** (ruled lines) | Session list for a connected host with no sessions | Distinguishes "the host has nothing" from "you're not connected". |
| **PairingArt** (phone + code) | Host setup / "connect to your server" | Interactive onboarding: the drawing accompanies the Scan / Paste action. No separate tour. |
| **PermissionArt** (key) | Capability consent sheet (Health export) | Permission is requested where the capability is used; the key says "you are being asked for access". |
| **HealthArt** (pulse) | Settings → Health capability row | Inline illustration for the section, small, next to the engine name. |
| **VoiceArt** (microphone) | Settings → Speech recognition | Speaking about voice, show voice. Inline in the card, beside the engine picker. |
| **OfflineArt** (unplugged plug) | Host unreachable / connection lost | Passive state in the content region with a Retry action — never a blocking alert. |
| **SearchArt** (magnifier) | Files search with no results | "No results" is a search outcome; the magnifier explains what was searched. |
| **FilesArt** (folder) | Files browser, empty workspace | Content-region placeholder for an empty workspace. |
| **ToolsArt** (gear) | Tool/activity area before the agent runs anything | The agent's instruments; shows where tool output will appear. |
| **HistoryArt** (clock) | Session history / timeline, empty | Time with nothing in it yet. |
| **NavigationArt** (map pin) | Ambient-mode navigation action card | The one action the agent can drive on the phone. |
| **AgentArt** (spark) | Settings → About | The app's identity; decorative and rare. |
| **TerminalArt** (terminal) | Settings → About, or the code-related empty state | The product's other identity (it runs code). Use once. |

## Not artwork

- **Loading** — use `ProgressView` / the system progress indicators.
- **Errors** — text plus a clear action (HIG *Feedback*). The artwork is for
  absence, not failure.
- **The composer** — the reference composer has no illustration; the field and
  the action cluster are the interface.

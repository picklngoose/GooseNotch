# Goosenotch 🪿🏝️

A sleek, native Dynamic Island experience for macOS, crafted specifically for the MacBook camera notch (with full support for external and non-notch displays).

Built with **SwiftUI**, **AppKit**, and **Liquid Glass** styling, Goosenotch transforms the notch from unused bezel into a functional, fluid hub for your music, timers, voice memos, calendar agenda, and a local AI assistant.

---

## ✨ Features

### 🎛️ Dynamic Island & Ambient Wings
* **Fluid Notch Integration**: Curves naturally out of your MacBook's camera notch using bezier curvature matching macOS hardware.
* **Ambient Wings**: When closed, subtle activity wings display live status for background tasks—running timers, active recordings, playing music, or imminent calendar meetings.
* **Hover & Right-Click**: Expands seamlessly on cursor hover. Right-click the notch at any time for quick access to appearance settings, voice memo files, or app controls.
* **Universal Display Support**: Works on MacBook notches or projects a virtual island on external and non-notch monitors.

### ⏱️ Timer & Stopwatch
* **Countdown & Presets**: Quick-select presets (1m, 3m, 5m, 10m, 15m, 25m Pomodoro, 30m, 45m, 60m) or enter custom hours, minutes, and seconds.
* **Stopwatch Mode**: Millisecond-accurate stopwatch.
* **Ambient Progress Bar**: Visual progress indicator and audio alert when time is up.

### 🎵 Apple Music Controller
* **Now Playing**: Displays track title, artist, album name, and high-resolution album artwork.
* **Dynamic Color Accent**: Automatically samples the dominant color from current album art to tint controls and scrub bars.
* **Interactive Controls**: Play, pause, skip, previous, and smooth scrubbing bar.

### 🎙️ Voice Memos & Live Transcription
* **Instant Dictation**: Record voice notes directly from the notch.
* **Real-Time Audio Waveform**: 20-band live frequency and level visualizer.
* **On-Device Speech-to-Text**: Real-time live transcription powered by Apple's `Speech` framework.
* **Automatic Storage**: Audio recordings and transcripts saved directly to `~/Documents/Notch Memos` with one-click Finder access.

### 📅 Calendar & Meeting Countdown
* **7-Day Agenda**: Clean agenda view synced with macOS Calendar (`EventKit`).
* **Meeting Quick-Join**: Detects conference links (Zoom, Google Meet, Microsoft Teams, FaceTime, Webex, etc.) with a direct one-click join button.
* **10-Minute Countdown Wing**: Displays a countdown wing in the notch when an event is about to start within 10 minutes.

### 🤖 Local AI Assistant (Ollama)
* **Private & Local**: Powered by your local [Ollama](https://ollama.ai) instance—no cloud subscriptions, API keys, or data tracking required.
* **Dynamic Model Picker**: Automatically detects installed models (`llama3`, `mistral`, `qwen`, `deepseek-r1`, etc.) or pulls custom models on demand.
* **System Tool Calling**: The assistant can invoke safe macOS actions:
  * `set_timer`: Set and start countdown timers.
  * `timer_control`: Start, pause, or reset timers.
  * `recording_control`: Start or stop voice recordings.
  * `get_current_time`: Check local date and time.
  * `copy_to_clipboard`: Copy generated text or responses to your Mac clipboard.
  * `open_url`: Open links in your default browser.
  * `open_application`: Launch Mac apps by name.

### 🎨 Liquid Glass & Appearance Customization
* **Liquid Glass vs Solid Black**: Choose between deep black blending into frosted glass or pure solid black matching the notch bezel.
* **Granular Glass Controls**: Configure blur intensity (*Clear*, *Subtle*, *Balanced*, *Strong*, *Maximum*), glass density, fade gradient, opacity, corner radius, wing width, and rim light strength.
* **Launch at Login**: Optional setting to automatically launch Goosenotch on startup.

---

## 🛠️ System Requirements

* **macOS 14.0 (Sonoma)** or later
* **Apple Silicon or Intel Mac** (Notch hardware supported; virtual notch rendered on other screens)
* **Xcode 15+ / Swift 5.9+** (command-line tools)
* *(Optional)* **[Ollama](https://ollama.ai)** running locally for the AI Assistant tab (`http://127.0.0.1:11434`)

---

## 🚀 Quick Start & Building

The project includes an automated build script that compiles the release binary, packages the macOS `.app` bundle, applies entitlements, ad-hoc codesigns (so macOS preserves microphone, speech recognition, and calendar permissions), and launches the app.

### Build and Launch

1. Clone or download the repository:
   ```bash
   git clone https://github.com/your-username/GooseNotch.git
   cd GooseNotch/NotchIsland
   ```

2. Run the build script:
   ```bash
   ./build.sh
   ```

### Manual Build via Swift Package Manager

To build a release binary directly:
```bash
swift build -c release
```
The compiled executable will be located in `.build/release/NotchIsland`.

> **Note**: For microphone, calendar, and speech recognition permissions to persist across app relaunches, it is recommended to package and ad-hoc sign the `.app` bundle via `./build.sh`.

---

## ⌨️ Permissions & Setup

When using specific tabs for the first time, macOS will request access:

| Feature | Required Permission | Description |
| :--- | :--- | :--- |
| **Voice Memos** | Microphone (`AVAudioApplication`) | Captures audio input for voice notes. |
| **Transcription** | Speech Recognition (`SFSpeechRecognizer`) | On-device live voice transcription. |
| **Calendar** | Calendars (`EventKit`) | Reads upcoming events and agenda. |
| **Apple Music** | Apple Events (`ScriptingBridge`) | Reads playback state and controls track navigation. |

*(All permissions are requested on-demand only when activating the corresponding feature).*

---

## ⚙️ Configuration & Options

* **Notch Settings**: Right-click on the notch and choose **Notch Appearance…** to open the live inspector.
* **AI Model Selection**: Select or switch active Ollama models directly from the Chat tab dropdown.
* **Quit App**: Right-click the notch and select **Quit Goosenotch**, or press `⌘Q` while Goosenotch is active.

---

## 📂 Project Architecture

```
NotchIsland/
├── Package.swift                    # Swift Package Manager manifest (macOS 14+)
├── build.sh                         # Release packaging & ad-hoc signing script
├── Info.plist                       # App bundle metadata and permission descriptions
├── NotchIsland.entitlements         # Sandbox & permission entitlements
└── Sources/NotchIsland/
    ├── NotchIslandApp.swift         # App entry point & global menu shortcuts
    ├── IslandController.swift       # State management, session lifecycle, and hover coordination
    ├── IslandView.swift             # Main Dynamic Island view & tab router
    ├── ConnectedIslandShape.swift   # Smooth notch bezier geometry and animation masks
    ├── NotchGeometry.swift          # Display detection (physical notch vs virtual)
    ├── NotchPanel.swift             # Floating NSPanel window configuration
    ├── NotchHoverMonitor.swift      # Cursor tracking and hover/click event monitor
    ├── GlassStyle.swift             # Liquid Glass visual effects and materials
    ├── AppearanceSettingsView.swift # Live appearance customization sheet
    ├── LaunchAtLogin.swift          # ServiceManagement login item helper
    ├── TimerController.swift        # Countdown timer & stopwatch logic
    ├── TimerAlert.swift             # Audio chimes and completion alerts
    ├── MusicController.swift        # Apple Music AppleScript integration
    ├── MusicPanel.swift             # Now playing UI and scrubber
    ├── ArtworkAccent.swift          # Dynamic color extraction from album artwork
    ├── AudioCapture.swift           # Low-level audio recording & live speech transcription
    ├── RecorderController.swift     # Voice memo state and file manager
    ├── CalendarController.swift     # EventKit calendar integration and 10m countdown
    ├── CalendarPanel.swift          # 7-day agenda list & video call link launcher
    ├── OllamaClient.swift           # Streaming Ollama API client
    ├── ChatController.swift         # Chat conversation engine & system tool dispatcher
    └── ChatPanel.swift              # Assistant conversation UI & model selector
```

---

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

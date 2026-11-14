# AI Subtitle Studio (Open Source Edition)

<p align="center">
  <img src="assets/images/app_logo.png" width="120" height="120" alt="AI Subtitle Studio Logo" />
</p>

**AI Subtitle Studio** is a 100% on-device, private, cross-platform application for creating, synchronizing, translating, and styling video & audio subtitles. Powered by **whisper.cpp**, **ONNX Runtime Mobile**, and **FFmpeg**, it provides offline speech-to-text inference and sequence-to-sequence neural translation directly on your local CPU / ARM hardware without uploading private movies or voice data to any cloud service.

---

## 🔒 100% On-Device Privacy Guarantee

- **Zero Cloud Uploads**: Speech recognition, neural translation, subtitle timing, and media processing run strictly on your local device.
- **Offline First**: All database records and subtitle cues are stored locally in SQLite (`ai_subtitle_studio.db`).
- **Hardware Acceleration**: Optimized with ARM NEON SIMD vectorization and multi-threaded CPU execution.

---

## ✨ Features

### 1. 🎙️ On-Device AI Speech Recognition (Whisper)
- Integrated with `whisper.cpp` high-performance C++ neural inference.
- Multi-model catalog with automatic Hugging Face direct downloads:
  - **Whisper Tiny (Multilingual)** (~75 MB) — Ultra-fast drafting with minimal RAM (~390 MB).
  - **Whisper Base (Multilingual)** (~142 MB) — Recommended standard for accuracy and speed (~500 MB RAM).
  - **Whisper Small (Multilingual)** (~466 MB) — High precision for accents and multi-speaker dialogues (~1.0 GB RAM).
  - **Whisper Medium (Multilingual)** (~1.5 GB) — Near-human transcription accuracy (~2.6 GB RAM).
- Automatic timestamp alignment and speaker segment identification.

### 2. 🌐 Offline Neural Translation (ONNX Runtime)
- Sequence-to-Sequence neural translation via quantized Marian / OPUS-MT & NLLB models:
  - **Japanese → English** (`opus-mt-ja-en`)
  - **Korean → English** (`opus-mt-ko-en`)
  - **Hindi → English** (`opus-mt-hi-en`)
  - **English → Hindi** (`opus-mt-en-hi`)
  - **Tamil / Multilingual → English** (`nllb-200-distilled-600M`)
- SentencePiece tokenization via `unigram_tokenizer.dart` with rule-based fallback synthesis.

### 3. 🎬 Synchronized Subtitle Editor
- Integrated video player with live subtitle overlay preview.
- Frame-accurate playhead tracking and scrub slider.
- Inline text editing, cue addition, deletion, splitting, and merging.
- **Batch Time Shifting**: Shift all or selected cues forward/backward by millisecond precision (`+/- ms`).
- **Search & Replace**: Real-time query search and replace across all subtitle cues.

### 4. 🎨 Subtitle Styling & Formatting
- Interactive visual customization:
  - Font size, font family, bold, italic.
  - Text fill color, background pill color, outline stroke color and width.
  - Positioning and alignment (Bottom-Center, Bottom-Left, Bottom-Right, Top-Center).
- **Broadcast-compliant Splitting**: Smart text splitting by max characters per line (e.g., 42 chars) and natural punctuation boundaries (`.`, `?`, `!`, `,`).

### 5. 🛡️ Content Masking & Profanity Policy
- Four selectable dialogue masking policies:
  - **Authentic Dialogue (Default)**: Preserves original spoken words without alteration.
  - **Partial Masking**: Partially censors detected words (`f**k`, `b***h`).
  - **Full Masking**: Complete asterisk replacement (`****`).
  - **Placeholder**: Replaces words with custom tag (`[censored]`).

### 6. 📤 Multi-Format Subtitle Export
- **SubRip Subtitles (`.srt`)**
- **WebVTT (`.vtt`)**
- **Advanced SubStation Alpha (`.ass`)** with full styling and position coordinates.
- Direct export to public `Downloads/AI Subtitles/` directory for instant sharing.

### 7. ⚡ Batch Processing Queue
- Background pipeline executing:
  1. `Extracting Audio` (16kHz 16-bit mono PCM via FFmpeg)
  2. `Transcribing` (Whisper model inference)
  3. `Translating` (ONNX neural translation)
  4. `Formatting` (Splitting and masking)
- Real-time progress bars, retry logic, error diagnostics, and battery/thermal safety checks.

---

## 🏛️ Project Architecture

```
lib/
├── app/
│   ├── app.dart                                # Root MaterialApp with Riverpod & Theme
│   ├── router.dart                             # Declarative GoRouter configuration
│   └── theme/app_theme.dart                    # Material 3 Dark & Light theme
├── core/
│   ├── errors/failures.dart                    # Typed domain failures
│   ├── platform/device_info_service.dart       # CPU, RAM, Battery, NEON diagnostics
│   └── utilities/timestamp_utils.dart          # SRT, VTT, ASS timestamp math
├── data/
│   ├── database/app_database.dart              # SQLite database (ai_subtitle_studio.db)
│   └── serializers/
│       ├── ass_serializer.dart                 # Advanced SSA (.ass) parser & serializer
│       ├── srt_serializer.dart                 # SubRip (.srt) parser & serializer
│       └── vtt_serializer.dart                 # WebVTT (.vtt) parser & serializer
├── domain/
│   ├── entities/
│   │   ├── processing_job.dart                 # Background job lifecycle entity
│   │   ├── project.dart                        # Subtitle project entity
│   │   ├── subtitle_cue.dart                   # Timed cue entity
│   │   ├── subtitle_style.dart                 # Visual styling entity
│   │   ├── translation_pack_info.dart          # Neural translation pack entity
│   │   ├── user_settings.dart                  # User settings & masking policy
│   │   └── whisper_model_info.dart             # Whisper model catalog entity
│   └── services/
│       ├── job_scheduler.dart                  # Pipeline orchestrator
│       ├── offline_translation_engine.dart     # Translation coordinator
│       ├── profanity_filter_service.dart       # 4-mode word censor
│       ├── subtitle_export_service.dart        # File exporter
│       ├── subtitle_splitting_service.dart     # Broadcast-standard cue splitter
│       └── translation_pack_manager.dart       # ONNX model installer
├── features/
│   ├── about/presentation/about_screen.dart
│   ├── batch_queue/presentation/
│   │   ├── batch_queue_screen.dart
│   │   └── job_details_sheet.dart
│   ├── diagnostics/presentation/diagnostics_screen.dart
│   ├── home/presentation/home_screen.dart
│   ├── language_packs/presentation/language_packs_screen.dart
│   ├── media_import/presentation/new_project_screen.dart
│   ├── model_library/presentation/model_library_screen.dart
│   ├── providers.dart                          # Riverpod state notifiers
│   ├── settings/presentation/settings_screen.dart
│   ├── splash/presentation/splash_screen.dart
│   ├── subtitle_editor/presentation/subtitle_editor_screen.dart
│   └── translation/presentation/translate_screen.dart
└── native/
    ├── media/
    │   ├── audio_extractor.dart                # 16kHz mono audio extraction
    │   └── media_inspector.dart                # Media stream probe
    ├── translation/
    │   ├── onnx_translation_engine.dart        # Seq2Seq ONNX engine
    │   └── unigram_tokenizer.dart              # SentencePiece tokenizer
    └── whisper/
        ├── whisper_engine.dart                 # Speech-to-text runner
        └── whisper_model_manager.dart          # GGML model installer
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/) (>= 3.24.0)
- [Dart SDK](https://dart.dev/) (>= 3.5.0)

### Setup & Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-org/ai_subtitle_studio.git
   cd ai_subtitle_studio
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run Unit & Widget Tests:**
   ```bash
   flutter test
   ```

4. **Launch the application:**
   ```bash
   # Run on connected device or emulator
   flutter run
   ```

---

## 📄 License

This open-source project is distributed under the **MIT License**.
Included models and third-party tools (`whisper.cpp`, `ffmpeg`, `OPUS-MT`, `NLLB-200`) remain subject to their respective upstream licenses.

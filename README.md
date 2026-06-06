# JosType

**Smart system-wide autocomplete for Mac.** A privacy-first, on-device
alternative to Cotypist. Powered by **Gemma** (via llama.cpp), JosType predicts
the rest of your sentence, completes the word you're typing, and fixes typos
inline — in (almost) any Mac app. Everything runs on your Mac. No account,
no cloud, no API key.

> Status: early but functional. Builds on macOS 14+ with Apple Silicon or Intel.

## Features

- **LLM-powered predictions.** Uses Gemma 3 1B, Gemma 4 E2B, or Gemma 3 4B
  running locally via llama.cpp. Switch models from the menu bar.
- **Inline ghost-text suggestions.** A gray "ghost" of the predicted
  completion appears right after your caret. Press **Tab** or **Right Arrow**
  to accept, **Esc** to dismiss.
- **Instant fallback.** While the LLM loads (or for single-word completions),
  a fast n-gram engine provides instant suggestions.
- **Word completion.** Finishes the word you're typing from a frequency-ranked
  dictionary plus your own learned vocabulary.
- **Next-word / sentence prediction.** The LLM predicts natural continuations
  of your text, not just the next word.
- **Inline typo correction.** If the word you just typed isn't recognized,
  JosType offers the closest correction (Damerau–Levenshtein distance) without
  red squiggles or popups.
- **Personalization.** When enabled, JosType learns from the text you type so
  suggestions sound like *you*. All learning stays on your Mac in
  `~/Library/Application Support/JosType`.
- **Menu-bar app.** Lives quietly in the menu bar (no Dock icon). Toggle on/off,
  switch models, pause learning, or quit from there.
- **Works across apps** that expose standard macOS accessibility text APIs
  (Notes, Mail, TextEdit, Safari fields, many native apps).

## How it works

JosType uses three macOS technologies:

1. **Accessibility API (`AXUIElement`)** to read the focused text field's
   contents and caret position, and to insert/replace text.
2. **A `CGEventTap`** (with `NSEvent` global monitor fallback) to intercept
   **Tab/Right Arrow** and **Esc** keys only while a suggestion is visible.
3. **A borderless overlay window** positioned at the caret to draw the gray
   ghost text.

The prediction engine has two tiers:

- **LLM tier** — Gemma models in GGUF format, run on-device via
  [LocalLLMClient](https://github.com/tattn/LocalLLMClient) (a Swift wrapper
  around llama.cpp). The model is downloaded from HuggingFace on first launch
  and cached locally. Inference runs after a 400ms typing pause so it doesn't
  slow down keystroke-by-keystroke typing.
- **N-gram tier** — `Trie` prefix-completion + bigram/trigram counts for
  instant word-level suggestions while the LLM loads or for simple completions.
  Also powers the `TypoCorrector` (Damerau–Levenshtein nearest-word lookup).

## Available models

| Model | Size | Best for |
|---|---|---|
| **Gemma 3 1B** (default) | ~700 MB | Fast suggestions, lower memory |
| **Gemma 4 E2B** | ~1.5 GB | Better quality, still quick |
| **Gemma 3 4B** | ~2.5 GB | Best quality, needs more RAM |

Switch models from the menu bar ✦ → **Model** submenu.

## Requirements & permissions

- **macOS 14+** (Ventura or later)
- **Xcode command-line tools** (Swift 5.9+) to build
- ~1–3 GB disk for the model (downloaded on first launch)

JosType needs two permissions (macOS will prompt on first run):

- **Accessibility** — to read text fields and insert completions.
  System Settings → Privacy & Security → Accessibility → enable **JosType**.
- **Input Monitoring** — for the Tab/Esc event tap (optional — a fallback
  monitor works without this, but Tab may also insert a tab character).
  System Settings → Privacy & Security → Input Monitoring → enable **JosType**.

## Build & run

```bash
git clone https://github.com/joskedemax/The-first-one.git
cd The-first-one
./scripts/make_app.sh
open ./build/JosType.app
```

Or for quick iteration during development:

```bash
swift run JosType
```

On first launch, JosType downloads the selected Gemma model (~700 MB for 1B).
The menu bar shows download/loading progress.

## Usage

1. Launch JosType. Grant Accessibility + Input Monitoring when prompted.
2. Click the menu-bar ✦ icon to confirm it's **Enabled** and the model loaded.
3. Start typing in any supported app. A gray ghost completion appears — press
   **Tab** or **Right Arrow** to accept it, keep typing to ignore it, or
   **Esc** to dismiss.
4. Switch models from ✦ → **Model** if you want higher quality (bigger model)
   or faster suggestions (smaller model).

## Limitations

- Apps that don't expose standard AX text attributes (some Electron apps,
  certain custom editors, secure fields) won't get suggestions.
- First launch requires an internet connection to download the model.
- LLM predictions take ~200–500ms; the n-gram engine fills in instantly while
  you wait.

## Roadmap

- [ ] Mid-line / full-sentence completions
- [ ] Emoji shortcodes (`:tada:` → 🎉)
- [ ] Per-app enable/disable
- [ ] Settings window (thresholds, dictionary management)
- [ ] MLX backend for faster Apple Silicon inference
- [ ] Model fine-tuning on your writing style

## License

MIT — see `LICENSE`.

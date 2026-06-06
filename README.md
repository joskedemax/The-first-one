# Glide

**Smart system-wide autocomplete for Mac.** A privacy-first, on-device
alternative to Cotypist. Glide predicts the rest of your sentence, completes
the word you're typing, and fixes typos inline — in (almost) any Mac app —
and it learns your writing style locally. No account, no network, no API key.

> Status: early but functional foundation. Builds on macOS 13+ with Apple
> Silicon or Intel. See [Limitations](#limitations).

## Features

- **Inline ghost-text suggestions.** A gray "ghost" of the predicted
  completion appears right after your caret. Press **Tab** to accept, **Esc**
  to dismiss.
- **Word completion.** Finishes the word you're typing from a frequency-ranked
  dictionary plus your own learned vocabulary.
- **Next-word prediction.** Suggests the next word from an on-device n-gram
  model trained on your typing.
- **Inline typo correction.** If the word you just typed isn't recognized,
  Glide offers the closest correction (Damerau–Levenshtein distance) without
  red squiggles or popups.
- **Personalization.** When enabled, Glide learns from the text you type so
  suggestions sound like *you*. All learning stays on your Mac in
  `~/Library/Application Support/Glide`.
- **Menu-bar app.** Lives quietly in the menu bar (no Dock icon). Toggle on/off,
  pause learning, or quit from there.
- **Works across apps** that expose standard macOS accessibility text APIs
  (Notes, Mail, TextEdit, Safari fields, many native apps).

## How it works

Glide uses three macOS technologies:

1. **Accessibility API (`AXUIElement`)** to read the focused text field's
   contents and caret position, and to insert/replace text.
2. **A `CGEventTap`** to intercept the **Tab** and **Esc** keys *only* while a
   suggestion is visible, so Tab accepts the suggestion instead of inserting a
   tab character.
3. **A borderless overlay window** positioned at the caret to draw the gray
   ghost text.

The prediction engine is 100% local:

- `Trie` — prefix-completion over a frequency-weighted word list.
- `LanguageModel` — unigram/bigram/trigram counts, seeded from a bundled word
  list and continuously updated from your typing (persisted to disk).
- `TypoCorrector` — Damerau–Levenshtein nearest-word lookup over known words.

## Requirements & permissions

Glide needs two permissions (macOS will prompt on first run):

- **Accessibility** — to read text fields and insert completions.
  System Settings → Privacy & Security → Accessibility → enable **Glide**.
- **Input Monitoring** — for the Tab/Esc event tap.
  System Settings → Privacy & Security → Input Monitoring → enable **Glide**.

## Build & run

You need Xcode command-line tools (Swift 5.9+) on macOS.

```bash
# Build the binary and assemble Glide.app
./scripts/make_app.sh

# Launch it
open ./build/Glide.app
```

Or for quick iteration during development:

```bash
swift run Glide
```

> Note: accessibility permissions are tied to the app's code signature/path.
> When running via `swift run`, you must grant permission to the resulting
> debug binary; using `make_app.sh` and granting permission to `Glide.app` is
> the smoother path.

## Usage

1. Launch Glide. Grant Accessibility + Input Monitoring when prompted.
2. Click the menu-bar ✦ icon to confirm it's **Enabled**.
3. Start typing in any supported app. A gray ghost completion appears — press
   **Tab** to accept it, keep typing to ignore it, or **Esc** to dismiss.
4. Leave **Learn from my typing** on to personalize over time.

## Limitations

- Apps that don't expose standard AX text attributes (some Electron apps,
  certain custom editors, secure fields) won't get suggestions. This is the
  same constraint every system-wide text tool faces.
- Caret-rect lookup falls back gracefully: if Glide can't locate the caret on
  screen, it shows the suggestion in a small HUD near the field instead.
- This is a foundation, not a finished product — see the roadmap below.

## Roadmap

- [ ] Mid-line / full-sentence completions
- [ ] Emoji shortcodes (`:tada:` → 🎉)
- [ ] Per-app enable/disable
- [ ] Settings window (thresholds, dictionary management)
- [ ] Optional larger on-device neural model
- [ ] iCloud-free encrypted sync of your personal model between Macs

## License

MIT — see `LICENSE`.

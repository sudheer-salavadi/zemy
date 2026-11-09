# Zemy roadmap: AI features

Two planned AI features. Both keep Zemy's promise that **nothing leaves your Mac by default**.

## Principles

- **On-device first.** Use Apple's Foundation Models framework (on-device model on Apple Intelligence Macs), the Translation framework and Vision. They are free, private and offline.
- **Cloud is opt-in only.** An optional bring-your-own API key (e.g. Claude) for stronger screenshot understanding and copywriting. It is off by default and clearly labelled as sending data to that provider.
- **Graceful fallback.** Zemy supports macOS 15+. AI features appear only where they're supported, and every tool keeps working without them.
- **Verify first.** Before building, confirm what the on-device model supports on the target macOS, especially image input. If it's text-only, Vision's text recognition (fast mode; accurate mode hung on macOS 27.0.1) describes each screenshot to the model.

---

## 1. App Store copy and translation, plus Showcase headline suggestions

One copywriting engine, used in two tools.

### App Store tool
- **Write captions.** Input: each page's screenshot, plus a one-line app description and a tone (e.g. friendly, premium, playful). Output: 3–5 headline and subheadline options per page, one click to apply.
- **Tell a story across pages.** Put the strongest benefits on pages 1–3 (most shoppers don't swipe further) and avoid repeating the same benefit.
- **Translate and fit.** Localize captions into the selected languages, shortening anything that would overflow the caption area at the current font and size, rather than translating word for word. Respect right-to-left languages.
- **Pre-flight review.** Flag wording App Review tends to reject: prices or "free" claims, "#1" or other ranking claims, names of other platforms, and placeholder text.

### Showcase
- **Headline suggestions** for the text layers, from the screenshots and an optional one-line description.
- **Fit to layout.** Prefer shorter copy for Split, and longer for Hero or caption styles.

### UI sketch
- A **"Suggest"** (✨) button next to the headline and subheadline fields.
- A **"Translate all"** action in the Languages panel. Untranslated pages stay flagged until reviewed.
- Fields for the app description and tone are stored with the project, so suggestions stay consistent.

### Done when
- Captions can be generated for all pages and translated into at least 5 locales on-device.
- Overflowing text is detected and shortened.
- Nothing is applied without the user choosing an option.
- Everything works offline on a supported Mac, with a clear message on unsupported Macs.

---

## 4. Command bar, agent CLI and MCP server

A natural-language command bar inside the app, and the same capability exposed to external AI agents. All of it is built on one shared **design spec**.

### Design spec (JSON)
Describes what to make: the tool, devices or canvas size, style or layout, background, frames, pages with screenshots, text per locale, and the output folder.

```json
{
  "tool": "appstore",
  "devices": ["iphone69", "iphone63", "ipad13"],
  "style": "captionTop",
  "frames": true,
  "background": { "mesh": "calm" },
  "pages": [
    { "screenshot": "shots/home.png",
      "text": { "en-US": { "headline": "Plan your day in seconds", "sub": "Smart lists" },
                "de-DE": { "headline": "Plane deinen Tag in Sekunden" } } }
  ],
  "output": "./store-screens"
}
```

### Rendering core
- Separate rendering from the app's screens, so the app, the command line and MCP share **one engine** with no duplicated code.

### Command-line interface
- `zemy render spec.json`
- `zemy showcase --layout hero --headline "…" shot1.png shot2.png -o hero.png`
- `zemy compress --smart *.png`, `zemy convert …`
- The same app binary runs in headless mode, with an optional `zemy` command on the PATH.

### MCP server (`Zemy mcp`, stdio)
- Tools: `showcase_render`, `appstore_render_set`, `list_options` (layouts, styles, schemes, sizes, languages, fonts), then `compress`, `convert`, `remove_background`, `favicon_pack`, `extract_palette`.
- **Returns a small preview image** (or a contact sheet for sets) with every render, so agents can look at their output and iterate.
- **Safety:** tools read only the files they're given and write only into the chosen output folder. No network access.
- Setup is documented in the README, e.g. `claude mcp add zemy -- /Applications/Zemy.app/Contents/MacOS/Zemy mcp`, plus the Cursor and Claude Desktop equivalents.

### In-app command bar
- ⌘K opens a prompt, e.g. "Make App Store screens from these 5 shots in German and Japanese, Calm background."
- The on-device model turns the request into a design spec, Zemy renders it, and the user refines the result by hand.

### Hand-off
- Every render can save its spec next to the images, and **Open spec in Zemy** loads it for manual fine-tuning. The agent drafts and the designer finishes.

### Phases
1. Rendering core, design spec and CLI for Showcase and App Store.
2. MCP server with previews and `list_options`, plus a README section on connecting agents.
3. Command bar (⌘K) and "Open spec in Zemy".
4. Batch tools as agent tools, and optionally macOS Shortcuts actions.

### Open questions
- Which agents to document first (Claude Desktop/Code, Cursor, others)?
- How unsigned builds behave when launched from a CLI or agent; it may need one manual first launch.

---

## Later (not planned yet)
- Smart Rename from image content (name screenshots by what they show).
- SVG from text, and SVG edits by instruction.
- Palettes from a prompt, color and token naming, accessible-shade suggestions.
- Alt text for exported images.

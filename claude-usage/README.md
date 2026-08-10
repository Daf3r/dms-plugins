# claude-usage

Your Claude subscription usage, in the DankMaterialShell bar.

The pill shows **two** windows side by side: the 5-hour session limit first, and
the weekly limit second, dimmed.

```
⏳ 44  ·  📅 84
```

Both slots are fixed. The session window is the one you can act on — it comes
back by waiting — but the weekly window is the one that decides whether you can
work for the rest of the week, and showing only the most critical of the two hid
it for as long as it stayed below the warning threshold. A small warning dot
appears next to the pill when any limit that is *not* the session one crosses the
threshold, which is the only hint that a per-model sublimit is in trouble without
opening the popout.

Clicking the pill opens a popout with the full breakdown: every window with its
progress bar and reset time, the per-model sublimits, extra credit spend, and a
footer saying where the number came from and how old it is, with a refresh
button.

## Where the data comes from, and the two things you should know first

The plugin calls `https://api.anthropic.com/api/oauth/usage` — the same endpoint
Claude Code itself uses — with the OAuth token Claude Code already stored on
this machine.

**1. That endpoint is not documented by Anthropic.** It is not a public API and
carries no contract: it can change shape, start refusing this client, or
disappear entirely, without notice and without it being a bug in anything. The
plugin is written to survive that (see *When something fails* below), but there
is no version of this that is guaranteed to keep working.

**2. It reads `~/.claude/.credentials.json`, and only reads it.** The file is
never written and never copied. The OAuth token travels in exactly one place —
the `Authorization` header of the usage request — and nowhere else: not to a
log, not into an error message, not into the UI, and not into the state object
the daemon publishes for the pill to paint. That is a design property, enforced
in `Daemon.qml`, and the manual checklist has a grep over the journal as a
release gate.

There is one other file, and it is also read-only: `~/.claude.json`, Claude
Code's own state file, which happens to keep the last usage payload it saw. The
plugin parses it **only** when the API call fails and there is no good value in
memory, so that a shell restart during an outage still shows something rather
than nothing. It never notifies from cached data.

There is nothing to configure. If Claude Code works on this machine, so does
this.

## When something fails

A meter that lies is worse than a missing one. The rule is that **no failure
leaves a number on screen without marking where it came from**:

| State | What it means |
|---|---|
| Normal | Freshly fetched. Full brightness. |
| Dimmed | The API is not answering. The number is the last good one, and the popout says whether it came from memory (*Offline · 8 min ago*) or from disk (*Local cache · 4 days ago*). With no value anywhere — an outage on a cold start — there is no number at all, just a `cloud_off` glyph. |
| Expired session | The OAuth token expired. The pill collapses to a `key_off` glyph with no number. Open Claude Code to renew it. |
| Loading | First poll after startup. A `monitoring` glyph, no number. |
| Hidden | No credentials to read, or the file is unparseable. The widget **hides itself entirely** rather than take up space to say nothing — and logs nothing, because what is unparseable is a credentials file. |

Dimming is opacity over the same colour role, not a different role. That keeps
hue free for severity, so "this number is old" and "you are near the limit" stay
legible at the same time.

Repeated failures back off: the poll interval doubles per consecutive failure,
capped at 30 min, and never drops below your configured interval. An HTTP
`Retry-After` header wins over that — both the `delta-seconds` and the HTTP-date
form — clamped to the same 15 s … 30 min range.

Notifications go out as DMS toasts when a window crosses the warning threshold,
debounced to **once per window**: the window's identity is its reset time, so
restarting the shell does not re-notify, and the alert re-arms by itself when the
window rolls over.

## Architecture: why `composite` and not `widget`

The plugin declares `type: "composite"` with two surfaces, `Daemon.qml` and
`Widget.qml`. That is not ceremony — it is what keeps the alerts working.

DMS instantiates a `widget` when you place it in a bar section and destroys it
when you take it out. A pure `widget` plugin would therefore stop polling the
moment you removed the pill from the bar, and the limit notifications would go
with it. The daemon starts with the shell and runs **once**, regardless of
whether the pill is on the bar at all.

The split matters in the other direction too: **the pill is instantiated once per
screen.** This machine has two, and during the HTTP spike two pills polling
independently earned a `429` from the endpoint. So all I/O — the network, the
files, the timer, the toasts — lives in the daemon, which publishes an
already-computed state object; the pill and the popout only paint it. Neither
`Widget.qml` nor `Settings.qml` makes a single request.

```
Daemon.qml   HTTPS (XMLHttpRequest) · credentials + cache (FileView) · timer · toasts
   │         publishes the global var `usage`, fully computed and already translated
   ├──→ Widget.qml     pill (once per screen) + popout
   └──→ Settings.qml   the seven settings (once, inside the settings modal)

logic.js     pure logic, zero host API: normalise, order, format, cadence, notifications
i18n.js      resolves descriptors against translations/{en,es}.json
```

`logic.js` and `i18n.js` import nothing from the host — no QML, no Quickshell, no
DMS. That is what keeps the test suite runnable without bringing up a shell.
Neither of them formats user-facing text either: they return descriptors, and
every string a human reads comes out of a catalogue.

## Settings

| Setting | Default | Range | What it does |
|---|---|---|---|
| Warning threshold | 90 % | 50–99 | At or above this, a window counts as warning: it tints, it notifies, and polling switches to the alert interval. |
| Idle interval | 300 s | 60–3600 | How often to poll when nothing is in warning. |
| Alert interval | 60 s | 15–600 | How often to poll when something is. |
| Show per-model sublimits | on | — | The `Opus · weekly` rows in the popout. It filters *only* those; the weekly window itself never hides. |
| Show extra credits | on | — | The additional-spend block in the popout. |
| Show remaining | off | — | Show what is left instead of what is spent. |
| Language | Auto | Auto / English / Español | Auto follows the session locale, falling back to English. |

The numeric defaults are bound to the constants in `logic.js`, which is the only
definition of each — the panel cannot drift from what the plugin actually does,
and a test asserts it. The ranges belong to the panel, not to the logic:
`logic.js` still accepts any value and clamps it to 15 s … 30 min, so a
hand-edited setting outside the slider range does not break anything.

## Installing

### Development (mutable, what this repo is set up for)

```bash
ln -s /home/daf3r/Projects/dms-plugins/claude-usage \
      ~/.config/DankMaterialShell/plugins/claude-usage
```

Edit a file in the repo and reload DMS; no rebuild in the loop.

### NixOS

DMS exposes plugins as a first-class home-manager option, and `src` takes a local
path:

```nix
programs.dank-material-shell.plugins.claude-usage = {
  enable = true;
  src = /home/daf3r/Projects/dms-plugins/claude-usage;
};
```

The attribute name is the **directory** name that gets created under
`~/.config/DankMaterialShell/plugins/`, so it is `claude-usage` with a hyphen.
Do not confuse it with the plugin's `id`, which is `claudeUsage` in camelCase
because DMS's plugin schema requires it.

Declaring this **replaces the development symlink** at that same path with a
read-only link into the Nix store. From then on every code change needs an
`nh os switch`, so keep the symlink while the plugin is still moving.

> **Do not set `settings` on this submodule.** The option exists, and it is a
> trap. The home-manager module turns on `managePluginSettings` as soon as *any*
> declared plugin carries a non-empty `settings`, and that makes DMS write
> `plugin_settings.json` as a read-only symlink into the store — at which point
> the settings panel above can no longer save, for this plugin *and* every other
> one. Declare `src` and `enable`, and leave `settings` out.
>
> It is the same one-or-the-other that `dms.nix` already documents for the
> shell's own `settings = { }`: whoever writes the file owns it. Starting on the
> GUI side is the right default here, because the settings are sliders you tune
> by watching the pill.

## Languages

English and Spanish, following the shell's language unless you pin one in the
settings. No user-facing string is written in the code, so adding a language is
one file in `translations/`. The suite checks that both catalogues have exactly
the same keys and that every key the logic can produce exists in both.

The manifest and these READMEs are in English on purpose — that is what the rest
of the DMS plugin ecosystem reads, and `description` in `plugin.json` never goes
through the catalogue, so it would be stuck in one language whatever we chose.

## Development

```bash
fish claude-usage/tests/run-js.fish
```

Needs `node` from the `dms-plugins` devshell (direnv activates it on entering the
project); outside direnv,
`nix develop ~/nixos-config#dms-plugins -c fish claude-usage/tests/run-js.fish`.
187 cases, and no shell required to run them.

What the tests *cannot* see — everything that only exists when the environment
breaks — is walked by hand in [`tests/MANUAL.md`](tests/MANUAL.md).

This plugin is a port of a Noctalia plugin written in Luau. Comments across the
QML and JS still name their source file (`service.luau`, `panel.luau`, …) as
provenance; those files were removed once the port was green and live only in git
history. `git log --diff-filter=D --name-only` finds the commit.

Design and decisions live in
[`../docs/superpowers/specs/`](../docs/superpowers/specs/).

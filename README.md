# dms-plugins

Plugins for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Written in QML plus plain JavaScript, with the logic kept in host-free `.js`
modules so the test suites run under `node --test` without bringing up a shell.

| Plugin | What it does |
|---|---|
| [`claude-usage`](claude-usage/) | Your Claude subscription usage in the bar: the 5-hour session window and the weekly one, with a popout breaking down every limit, the per-model sublimits and extra credit spend. |

## Installing

Each plugin is a directory under `~/.config/DankMaterialShell/plugins/`. For
development, a symlink is enough:

```bash
ln -s /home/daf3r/Projects/dms-plugins/claude-usage \
      ~/.config/DankMaterialShell/plugins/claude-usage
```

On NixOS, DMS exposes plugins as a first-class home-manager option whose `src`
takes a local path:

```nix
programs.dank-material-shell.plugins.claude-usage = {
  enable = true;
  src = /home/daf3r/Projects/dms-plugins/claude-usage;
};
```

Declaring a plugin replaces that symlink with a read-only link into the Nix
store, so every code change then needs a rebuild. **Do not set `settings` on the
submodule**: a non-empty `settings` on *any* declared plugin makes DMS write
`plugin_settings.json` into the store, and no plugin's settings panel can save
after that. See [`claude-usage/README.md`](claude-usage/README.md#nixos).

## Development

```bash
fish claude-usage/tests/run-js.fish
```

`node` comes from the `dms-plugins` devshell in `~/nixos-config`, which direnv
activates on entering the project. Outside direnv:

```bash
nix develop ~/nixos-config#dms-plugins -c fish claude-usage/tests/run-js.fish
```

Things that hold across the repo:

- **The logic modules import nothing from the host** — no QML, no Quickshell, no
  DMS. That is what makes the suites runnable headless.
- **No user-facing string is written in the code.** The logic returns
  descriptors; the text comes out of per-plugin `translations/*.json`, and the
  suite checks the catalogues have identical key sets.
- **A plugin that needs to keep working when its widget is off the bar is
  `composite`, not `widget`.** DMS destroys a `widget` when you remove it from a
  bar section; a `daemon` surface runs once with the shell. Bar widgets are also
  instantiated **once per screen**, so I/O belongs in the daemon.

`claude-usage` was originally written for [Noctalia](https://github.com/noctalia-dev)
in Luau; this repo was called `noctalia-plugins` then. The Luau sources were
removed once the DMS port was green and live only in git history. Design notes
and the port's decisions are in [`docs/superpowers/`](docs/superpowers/).

## License

MIT. See [LICENSE](LICENSE).

# Auto Foundation Undergrounds

A [Factorio](https://www.factorio.com/) mod for the [Space Age](https://www.factorio.com/space-age) DLC. When you place underground belts or underground pipes on [Vulcanus](https://wiki.factorio.com/Vulcanus), the mod automatically queues [Foundation](https://wiki.factorio.com/Foundation) tile ghosts on any lava tiles in the gap between the two ends. Your construction robots then build the foundations, allowing the underground to traverse lava without you having to place each foundation tile manually.

## How it works

Underground belts and pipes tunnel beneath the surface, but the tiles above their path still need to be buildable for the belt/pipe to be placed. On Vulcanus, lava in the way prevents this. The standard workflow is to manually lay Foundation tiles first — this mod automates that step.

When either end of an underground pair is placed, the mod:

1. Finds the paired counterpart (the other end of the same underground belt or pipe-to-ground)
2. Walks the tiles strictly between them along the cardinal axis
3. Places a Foundation tile ghost on any tile that is lava
4. Your construction robots build the Foundation ghosts as normal — no free tiles, no cheating

If you undo the placement (Ctrl+Z), the ghosts (and any already-built Foundation tiles) are also undone. Foundation ghosts are removed immediately; built Foundation tiles are marked for deconstruction so robots return the item to your logistics network. If you mine an underground manually, the same cleanup runs.

The mod only acts on the Vulcanus surface, since that is the only surface in the base game with lava.

## Undo/redo behaviour

Foundation positions are stored as tags on the Factorio undo stack rather than in persistent `storage`. This means the data is automatically discarded when the undo stack flushes — there is no unbounded memory growth. The undo tag API (`LuaUndoRedoStack`) is used to attach the positions to the undo action for the entity that triggered the ghost placement, and `on_undo_applied` / `on_redo_applied` events are used to react when the player undoes or redoes that action.

When reverting built Foundation tiles, the mod calls `LuaTile.order_deconstruction()` — Factorio's deconstruction pipeline handles collecting the Foundation item and restoring the hidden lava tile underneath, so no original tile names need to be stored by the mod.

## Development

### Requirements

- [Node.js](https://nodejs.org/) (for the test runner)
- Factorio with Space Age, installed via Steam on Windows

### Project structure

```
control.lua          Runtime mod logic
data.lua             Prototype stage (currently empty)
info.json            Mod metadata
tests/
  foundations.lua    Integration test suite
package.json         npm scripts for running tests
```

### Running tests

This project was developed on **WSL (Windows Subsystem for Linux)** with Factorio installed on the Windows host via Steam. Because of this, the test runner scripts in `package.json` hard-code the WSL path to the Factorio executable:

```
/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe
```

If your Factorio is installed elsewhere, update `--factorio-path` in `package.json`. Find the path in Steam by right-clicking Factorio → Manage → Browse local files, then translate the Windows path to WSL (`C:\` → `/mnt/c/`, etc.).

Test artifacts (mods, config, saves) are stored in a local `factorio-test-data-dir/` on the WSL filesystem. Factorio (a Windows binary) accesses WSL paths via `\\wsl.localhost\...`. Note that Windows Factorio cannot follow Linux symlinks on the WSL filesystem — the test runner works around this by copying mod files instead of symlinking. The patched fork also auto-discovers your Windows `player-data.json` via `cmd.exe` for mod portal authentication, so no manual configuration of a data directory is required.

The test runner is a patched fork of [FactorioTest](https://github.com/tylergoodman/FactorioTest) that adds WSL compatibility. It is vendored under `FactorioTest/` and referenced as a local `file:` path. Build it once before running tests:

```bash
npm run build:cli
```

Then install this mod's dependencies and run the tests:

```bash
npm install
npm test
```

To automatically re-run tests whenever a file changes:

```bash
npm run test:watch
```

Tests use [FactorioTest](https://github.com/GlassBricks/FactorioTest) (v3), a third-party integration test framework that runs tests inside a real Factorio instance. There is no mocking — tests create actual surfaces, place real entities, and assert on real tile and entity state. The `factorio-test` mod must be active alongside this mod when running tests; the CLI handles this automatically.

The test init call in `control.lua` is guarded by `script.active_mods["factorio-test"]` so it is a complete no-op in normal gameplay.

### Adding support for other lava surfaces

The surface check is centralised in the `is_supported_surface(surface)` function near the top of `control.lua`. To support a modded planet that also has lava, add its surface name to that function.

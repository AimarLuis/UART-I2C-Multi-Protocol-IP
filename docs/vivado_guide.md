# Vivado Guide

Shared guide for taking any of `uart/`, `i2c/`, or `multi/` into Vivado: adding sources, adding constraints, recreating a project from a checked-in `.tcl` script, and generating a bitstream. Nothing here is specific to one block — substitute the relevant folder (`uart/`, `i2c/`, or `multi/`) as needed.

## 1. Adding sources to a new project

1. **File → New Project** → RTL Project (either check or leave unchecked "Do not specify sources at this time" — sources can always be added afterward).
2. **Add Sources → Add or create design sources** → browse to `<block>/rtl/*.vhd`.
   - For `i2c/`, also decide whether you need a board-specific top: `i2c/rtl/i2c_top.vhd` is the pure, simulation-verified core; `i2c/vivado/i2c_hw_top.vhd` is a separate wrapper that ties it to real board buttons/switches/LEDs. Add whichever one matches what you're targeting — not both as competing top-level candidates.
3. Do **not** add the `tb_*.vhd` files under `sim/` as design sources. If you want to run Vivado's own simulator, add them instead under **Add or create simulation sources**; if you're only using Vivado for synthesis and bitstream generation (simulating separately in ModelSim/GHDL), skip them entirely.
4. Set the top module (**Sources** pane → right-click the intended top → **Set as Top**) if Vivado doesn't pick the right one automatically.

## 2. Adding constraints

1. **Add Sources → Add or create constraints** → browse to `<block>/vivado/*.xdc` (e.g. `i2c/vivado/i2c_hw_top.xdc`).
2. If a block has no `.xdc` yet (currently true only for `multi/`, which hasn't been through hardware bring-up), you'll need to write one — either from scratch, or by starting a project with the **Board** flow (Vivado auto-assigns standard clock/button/switch/LED pins from the board file) and then adding the block-specific pins by hand.
3. Constraints only take effect once synthesis runs — an early "unconstrained pins" warning when just sanity-checking a new project is expected and not a problem by itself.

## 3. Running the provided `.tcl` project-recreation scripts

`uart/` and `i2c/` each have a `vivado/create_project.tcl` — hand-written (not a raw Vivado export), using paths relative to the repo root, so they work regardless of where the repo is cloned. `multi/` has none yet (no hardware bring-up attempted for it).

The point of a recreation script is to check in a small `.tcl` file instead of the whole generated Vivado project (the `.runs/`, `.cache/`, `.sim/`, `.Xil/`, `.ip_user_files/` output that was deliberately cleaned out of this repo).

- **To run one**: open the Tcl console (**Window → Tcl Console**) with your working directory set to the repo root, and run `source uart/vivado/create_project.tcl` or `source i2c/vivado/create_project.tcl`; or from a shell, `vivado -mode batch -source uart/vivado/create_project.tcl`. Each script creates a fresh project at `./vivado_project` (git-ignored), adds that block's RTL as design sources, its `.xdc` as constraints, sets the right top module, and adds its testbenches to a simulation-only fileset (never synthesized).
- **To generate a new one** for a block that doesn't have one (`multi/`), the simplest path is to copy `i2c/vivado/create_project.tcl` as a template and edit the source file list, top module, and part name — rather than using Vivado's own **File → Project → Write Tcl...** export, which produces a machine-specific script full of absolute paths (see the note below).
- Recreation scripts bake in whatever source paths they're written with — if files get moved (as happened across this repo's `uart/`/`i2c/`/`multi/` reorganization), update or regenerate the script afterward rather than trusting a stale one.

## 4. Generating a bitstream

With sources, constraints, and a top module in place:

1. **Run Synthesis** (Flow Navigator → SYNTHESIS).
2. **Run Implementation** (after synthesis finishes).
3. **Generate Bitstream** (after implementation finishes).

Each step will prompt to run the ones before it if skipped. Once the bitstream is generated: **Open Hardware Manager → Open Target → Program Device**, with the board connected over USB-JTAG.

Keep the actual Vivado project directory (and its `.runs`/`.cache`/etc. output) **outside** this repo's `vivado/` folders — those hold only sources, constraints, and recreation scripts, exactly so that output never needs to be checked in or cleaned up again.

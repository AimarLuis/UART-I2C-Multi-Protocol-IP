# I2C Hardware Bring-Up — Arty A7-100T + TMP102

A from-scratch I2C master core in VHDL, verified on real hardware: a
Digilent Arty A7-100T FPGA board driving a real TMP102 temperature sensor
over I2C, both writing (setting the sensor's register pointer) and reading
(pulling back a 2-byte temperature value) confirmed correct with an external
USB logic analyzer.

For the RTL architecture itself, see [`i2c_report.md`](i2c_report.md). This
doc covers only the hardware-specific side: building the project, wiring up
the board, and the full bring-up debug history.

## Building the project

Requirements: Xilinx Vivado (tested with 2024.x), targeting a Digilent
Arty A7-100T (`xc7a100ticsg324-1L`). For the 35T variant, edit `part_name`
in `vivado/create_project.tcl` to `xc7a35ticsg324-1L` (pinout is identical).

From the Vivado Tcl console, with your working directory set to the repo
root:

```tcl
source i2c/vivado/create_project.tcl
```

or from a regular shell, from the repo root:

```sh
vivado -mode batch -source i2c/vivado/create_project.tcl
```

This creates a project at `vivado_project/` (git-ignored), adds all RTL as
design sources, `i2c_hw_top.xdc` as constraints, sets `i2c_hw_top` as the
top module, and adds the testbenches to the simulation-only fileset. No
debug/ILA cores are inserted — the working hardware bring-up used an
external logic analyzer instead of Vivado's internal ILA (see the journal
below).

Then, either in the GUI or via Tcl:

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

## Using the board (TMP102 test)

Wire a TMP102 breakout to Pmod JA: JA(0) = SCL, JA(1) = SDA (pull-ups are
enabled in the FPGA I/O buffer via the XDC, `PULLUP TRUE`). Default address
assumed is `0x48` (TMP102's `ADD0` pin tied to GND) — see the comment at
the top of `i2c_hw_top.vhd` for the other three address options.

- **BTN(0)** — write: sends pointer value `0x00` (selects the Temperature
  register). Tests the transmit path; a real ACK (not NACK) from the sensor
  is the pass condition.
- **BTN(1)** — read: pulls 2 bytes back (temperature MSB then LSB), ACKing
  after the first byte and NACKing after the second, per the I2C spec.
  Tests the receive path and the multi-byte continuation logic.

LEDs:

- **LED0** — heartbeat (design is alive)
- **LED1** — an operation has completed at least one byte (sticky)
- **LED2** — most recent ACK/NACK result: **off = ACK** (sensor answered),
  **on = NACK** (no answer / wrong address / wiring problem) — main
  go/no-go indicator
- **LED3** — raw `busy` (too fast to see by eye, informational only)

## Implementation notes worth knowing before touching `i2c_hw_top.vhd`

Any wrapper logic that reacts to seeing `done_o` go high (e.g. a byte counter clocked off `done_o`) is structurally one cycle too late and will terminate a multi-byte transfer one
byte later than intended. `i2c_hw_top.vhd`'s read path works around this by
never reacting to `done_o`: it holds `last_byte_i` at `'1'` continuously and
only drops it to `'0'` for the single cycle the read starts.

## Hardware bring-up — full debug journal

This section is the complete history of getting this core running on real
hardware: every approach tried, every error hit, and how each was resolved.
Kept here (not just in chat) so none of it has to be re-derived later.

### Goal and approach

The plan from the start was to verify the core on real hardware rather than
simulation alone, in two stages: first a protocol-only check with no real
I2C slave attached (just confirming the master generates a legal
START/address/ACK-or-NACK/STOP sequence), then a real sensor (TMP102) to
independently verify both the transmit and receive paths against a device
that actually answers.

### Setting up the Vivado project, manually, in the GUI

At first every pin (clock, reset, buttons, switches, LEDs, Pmod JA)
was assigned by hand in the I/O Ports view. That view is reached via
**Layout → I/O Planning** (or **Window → I/O Ports**). For each port, the
Package Pin / I/O Std / Pull Type columns were filled in manually against
the table now in `i2c_hw_top.xdc`.

The two ModelSim/Questa testbenches (`tb_i2c_master.vhd`, `tb_i2c_top.vhd`)
were deliberately kept **out** of the synthesis (design sources) fileset —
they were added only as simulation sources, never as design sources, since
Vivado would otherwise try to synthesize testbench-only constructs.

Every pin in `i2c_hw_top.xdc` (clock, reset, buttons, switches, LEDs, both
Pmod headers) was independently cross-checked, pin for pin, against
Digilent's own official `Arty-A7-100-Master.xdc`, fetched live from
`github.com/Digilent/digilent-xdc` — not assumed from memory. This later
turned out to matter: it's what let a hardware-symptom hypothesis
(bad reset pin) be conclusively ruled out rather than left as a guess.

### Phase 1 — No-slave bring-up via Vivado's internal ILA

After enough time sunk into confusing ILA captures with no clear resolution,
the explicit call was made to stop debugging through Vivado's internal
tooling and instead observe the I2C bus directly with real instruments: a
physical logic analyzer, and eventually a real I2C sensor. This turned out
to be the right call — every result from this point on was clean and
unambiguous.

### Phase 2 — No-slave re-test with an external logic analyzer

Instrument: a DSLogic U3Pro1 USB logic analyzer with DSView (a
sigrok-based application), using its built-in I2C protocol decoder with SCL
and SDA assigned to the two channels clipped onto Pmod JA. Pmod JA's
physical pinout (2×6 header) is: pin 1 = SCL, pin 2 = SDA, pins 3–4 unused,
pin 5 = GND, pin 6 = 3.3V (and the same pattern repeats on pins 7–12 for a
second sub-header / Pmod JB). A free-running capture (no trigger condition
needed) was used rather than a precisely-timed trigger, since a button
press is easy to just do live while capturing.

No Vivado project changes were needed for this — the previously generated
bitstream (built with the Mark Debug/ILA cores still present, since those
don't affect the functional pins) was simply reprogrammed onto the board.

Result: a clean, correctly decoded capture — **Start**, **Address 0x50 with
the R/W bit**, **NACK** (expected and correct, since no real slave was
present to ACK), **Stop**. This single clean result did two things at once:
it confirmed the core RTL was correct all along, and it confirmed the
earlier ILA confusion had been a tooling/debug-flow problem, not a real
design defect.

### Phase 3 — Real sensor test: TMP102

With the no-slave protocol confirmed, the next step was a real TMP102
temperature sensor (address `0x48`, `ADD0` tied to GND), to verify transmit
and receive independently, one button each:

- **BTN(0) — write**: a single byte, pointer value `0x00`, selecting the
  TMP102's Temperature register. Tests the transmit path — a real ACK from
  a real device (not a NACK) is the pass condition.
- **BTN(1) — read**: two bytes back to back (temperature MSB then LSB),
  ACKing after the first byte and NACKing after the second to end the read,
  per the I2C spec. Tests the receive path and, specifically, the
  multi-byte continuation logic.

First attempt: **NACK on both the write and the read** — indicating an
address or wiring problem rather than a protocol bug. After that was
corrected (address/wiring), the write path came back **fully correct**:
`Address write: 0x90 ACK`, `Data write: 0x00 ACK`, `Stop`, all confirmed via
the DSView decode. The read path, however, showed a real bug: it only
pulled **one** byte (with an ACK) and then stopped, instead of two bytes
ending in a NACK.

#### Root-cause analysis of the read bug

This took a careful line-by-line read of `i2c_master.vhd`'s `data_ack`
state to pin down. The key fact, easy to miss: `i2c_master` samples
`last_byte_i` to decide "is the *next* byte the last one" on the **same**
clock edge it asserts `done_o` for the **current** byte — and it uses the
value `last_byte_i` held **going into** that edge, not whatever it changes
to afterward (see the `last_q <= last_byte_i` line right where `done_o` is
also being set). The original wrapper computed `last_byte_i` **reactively**,
via a `byte_idx` counter that updated based on seeing `done_w = '1'`. Any
logic that reacts to `done_o` going high is, by construction, one clock
cycle too late to influence that specific decision — it ends up affecting
the transaction one byte later than intended, which is exactly the observed
symptom (the read terminated a byte earlier than expected relative to what
the reactive counter "meant" to do).

#### The fix

The `byte_idx` counter was removed entirely. `last_byte_i_w` is now purely
combinational and forward-looking instead of reactive: `'1'` (mark as last
byte) at all times, **except** during the exact `op_read_pulse` cycle — the
single cycle the read transaction starts — where it's `'0'` (byte 1 is not
the last byte). Because this is settled well before byte 1's own
`data_ack`/decision point even happens, byte 1's decision correctly reads
`last_byte_i = '1'` already latched in for byte 2, and byte 2's own
decision then correctly sees `last_q = '1'` and stops after it. This is the
version currently in `vivado/i2c_hw_top.vhd`.

Status: the fix was implemented and committed. Testing afterward indicated
the read then behaved as expected well enough that debugging moved on to a
deeper question (below) — but if you still have the DSView capture from
that retest, it's worth a quick glance to confirm it explicitly shows two
data bytes with an ACK after the first and a NACK after the second before
fully trusting this fix on faith.

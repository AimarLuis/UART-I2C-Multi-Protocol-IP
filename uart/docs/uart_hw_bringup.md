# UART Hardware Bring-Up — Arty A7 Loopback via USB-UART

Verifying the UART pair on real hardware using `uart_loopback_top`, the
secondary, testing-only top level: a Digilent Arty A7 configured in a
self-contained loopback (`rx_done_o -> tx_start_i`, `rx_data_o -> tx_byte_i`
— see [`uart_report.md`](uart_report.md) §7), connected to a laptop over
the board's own onboard USB-UART bridge (the same chip the constraints
target via `rx_pin_i`/`tx_pin_o` — no external converter needed).

For the RTL architecture itself, see [`uart_report.md`](uart_report.md).
This doc covers only the hardware side: building the project and the
bring-up test.

## Building the project

Requirements: Xilinx Vivado, targeting a Digilent Arty A7-100T
(`xc7a100tcsg324-1`).

From the Vivado Tcl console, with your working directory set to the repo
root:

```tcl
source uart/vivado/create_project.tcl
```

or from a shell:

```sh
vivado -mode batch -source uart/vivado/create_project.tcl
```

This creates a project at `vivado_project/` (git-ignored), adds all RTL
(both `uart_top.vhd` and `uart_loopback_top.vhd`) as design sources with
`uart_loopback_top` set as the top module — the one with a proven, working
`.xdc` for standalone bring-up — `uart_loopback_top.xdc` as constraints,
and all four testbenches to the simulation-only fileset. Then, either in
the GUI or via Tcl:

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

## Testing the loopback

With the bitstream programmed onto the board, the Arty was connected to a
laptop over USB — the same cable that powers the board also carries the
onboard USB-UART bridge, which enumerates as a normal serial port on the
laptop. Using a simple serial terminal program at 9600 baud, 8N1 (matching
`cnt.vhd`'s default `baudrate` generic), words typed on the laptop were
sent out over that port; since `uart_loopback_top` echoes everything it
receives straight back out, the same words were expected back byte for
byte.

## Bring-up note

First attempt: nothing came back — no echo, no data received on the laptop
side at all. The cause turned out to be a wiring mix-up in the
constraints, not an RTL bug: `rx_pin_i` and `tx_pin_o` had been assigned to
the USB-UART bridge's two pins the wrong way around, so the FPGA was
listening on the pin the bridge *transmits* on and transmitting onto the
pin the bridge *listens* on — the two sides were talking past each other
rather than to each other. Swapping the two pin assignments in the `.xdc`
(the correct, working assignment is what's now committed in
`vivado/uart_loopback_top.xdc`) fixed it immediately — every word sent
came back correctly on the very next test.

## Current status at a glance

| Test | Status |
|---|---|
| Loopback over the onboard USB-UART bridge (laptop ↔ Arty, arbitrary typed words) | Confirmed correct, after fixing a swapped `rx_pin_i`/`tx_pin_o` pin assignment |

`uart_top` (the primary, host-facing top) has not been through its own
hardware bring-up — it isn't a standalone bitstream target (see
`uart_report.md` §6): it's meant to be integrated into a design that
drives it, the way `multi/` reuses `uart_rx`/`uart_tx` directly.

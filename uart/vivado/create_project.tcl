# =============================================================================
# create_project.tcl
#
# Recreates the Vivado project for the UART hardware bring-up (loopback
# verification on a Digilent Arty A7-100T: send a byte in on rx_pin_i,
# confirm the same byte echoes back out tx_pin_o), from source files only.
#
# uart_top.vhd (real two-way host interface) and uart_loopback_top.vhd
# (self-contained echo) are both added as design sources, but only
# uart_loopback_top is set as the synthesis top -- it's the one with a
# proven, board-verified .xdc (see docs/uart_hw_bringup.md). uart_top is
# meant to be integrated into a larger design that drives its host ports
# (e.g. reused directly the way multi/ reuses uart_rx/uart_tx), not
# synthesized standalone with no constraints of its own.
#
# This script is meant to be committed to git INSTEAD of the actual Vivado
# project (.xpr, .cache/, .runs/, .sim/, .hw/, ...) -- those are all
# regenerable binary/machine-specific clutter that doesn't belong in version
# control. Anyone who clones the repo runs this script and gets an identical,
# working project.
#
# Usage (three ways):
#   1. GUI:    Tools -> Run Tcl Script...  and pick this file.
#   2. Tcl console inside Vivado (any working directory):
#        cd {path to the repo root}
#        source vivado/create_project.tcl
#   3. Batch / no GUI, from a shell, from the repo root:
#        vivado -mode batch -source vivado/create_project.tcl
#
# Assumes this file stays at <repo_root>/vivado/create_project.tcl -- it
# locates the repo root relative to its own location, so it works no matter
# where you cloned the repo.
# =============================================================================

set proj_name "uart_project"
set proj_dir  "./vivado_project"
set part_name "xc7a100tcsg324-1"    ;# Digilent Arty A7-100T

# ---------------------------------------------------------------------------
# Locate repo root (parent of the folder this script lives in)
# ---------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/.."]

puts "Repo root detected as: $repo_root"

# ---------------------------------------------------------------------------
# Create the project
# ---------------------------------------------------------------------------
create_project $proj_name $proj_dir -part $part_name -force

set_property target_language     VHDL [current_project]
set_property simulator_language  VHDL [current_project]

# ---------------------------------------------------------------------------
# Design sources (synthesizable RTL only -- testbenches must NOT go here).
# Both top-level flavors are added as sources; uart_loopback_top is the one
# actually set as top (see header comment above for why).
# ---------------------------------------------------------------------------
add_files -norecurse [list \
    "$repo_root/rtl/cnt.vhd" \
    "$repo_root/rtl/uart_rx.vhd" \
    "$repo_root/rtl/uart_tx.vhd" \
    "$repo_root/rtl/uart_top.vhd" \
    "$repo_root/rtl/uart_loopback_top.vhd" \
]
set_property top uart_loopback_top [current_fileset]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# Constraints
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse "$repo_root/vivado/uart_loopback_top.xdc"
set_property target_constrs_file "$repo_root/vivado/uart_loopback_top.xdc" [current_fileset -constrset]

# ---------------------------------------------------------------------------
# Simulation sources (ModelSim/Questa testbenches -- simulation-only fileset,
# kept out of sources_1 so synthesis never sees them)
# ---------------------------------------------------------------------------
add_files -fileset sim_1 -norecurse [list \
    "$repo_root/sim/tb_uart_rx.vhd" \
    "$repo_root/sim/tb_uart_tx.vhd" \
    "$repo_root/sim/tb_uart_top.vhd" \
    "$repo_root/sim/tb_uart_loopback_top.vhd" \
]
set_property top tb_uart_loopback_top [get_filesets sim_1]
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
puts ""
puts "============================================================"
puts " Project '$proj_name' created at: $proj_dir"
puts " Part: $part_name   Top: uart_loopback_top"
puts " (uart_top.vhd is also in sources_1, for reuse in a larger design --"
puts "  it is not the synthesis top and has no constraints of its own.)"
puts ""
puts " To generate a bitstream now:"
puts ""
puts "   launch_runs synth_1 -jobs 4"
puts "   wait_on_run synth_1"
puts "   launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "   wait_on_run impl_1"
puts "============================================================"

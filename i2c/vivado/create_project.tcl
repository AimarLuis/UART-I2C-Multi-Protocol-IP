# =============================================================================
# create_project.tcl
#
# Recreates the Vivado project for the I2C master hardware bring-up (the
# configuration used to talk to a real TMP102 sensor on a Digilent Arty
# A7-100T), from source files only.
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

set proj_name "i2c_project"
set proj_dir  "./vivado_project"
set part_name "xc7a100ticsg324-1L"    ;# Digilent Arty A7-100T. For the 35T
                                        ;# board instead, use xc7a35ticsg324-1L.

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
# Design sources (synthesizable RTL only -- testbenches must NOT go here)
# ---------------------------------------------------------------------------
add_files -norecurse [list \
    "$repo_root/rtl/i2c_clk_div.vhd" \
    "$repo_root/rtl/i2c_master.vhd" \
    "$repo_root/rtl/i2c_top.vhd" \
    "$repo_root/vivado/i2c_hw_top.vhd" \
]
set_property top i2c_hw_top [current_fileset]
update_compile_order -fileset sources_1

# ---------------------------------------------------------------------------
# Constraints
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse "$repo_root/vivado/i2c_hw_top.xdc"
set_property target_constrs_file "$repo_root/vivado/i2c_hw_top.xdc" [current_fileset -constrset]

# ---------------------------------------------------------------------------
# Simulation sources (ModelSim/Questa testbenches -- simulation-only fileset,
# kept out of sources_1 so synthesis never sees them)
# ---------------------------------------------------------------------------
add_files -fileset sim_1 -norecurse [list \
    "$repo_root/sim/tb_i2c_master.vhd" \
    "$repo_root/sim/tb_i2c_top.vhd" \
]
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
puts ""
puts "============================================================"
puts " Project '$proj_name' created at: $proj_dir"
puts " Part: $part_name   Top: i2c_hw_top"
puts ""
puts " No debug/ILA cores are inserted by this script -- the working"
puts " TMP102 bring-up was verified with an external logic analyzer,"
puts " not Vivado's internal ILA. To generate a bitstream now:"
puts ""
puts "   launch_runs synth_1 -jobs 4"
puts "   wait_on_run synth_1"
puts "   launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "   wait_on_run impl_1"
puts "============================================================"

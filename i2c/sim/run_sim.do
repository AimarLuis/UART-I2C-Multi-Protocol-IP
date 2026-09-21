# 1. Clean up any previous simulation
quit -sim

# 2. Delete the physical 'work' library if it already existed, to avoid corrupted data
if [file exists work] { vdel -all }

# 3. Create a clean 'work' library again
vlib work

# 4. Compile the design files (note they live in the neighboring ../rtl/ folder)
vcom ../rtl/i2c_clk_div.vhd
vcom ../rtl/i2c_master.vhd

# 5. Compile the testbench (in the current folder)
vcom tb_i2c_master.vhd

# 6. Launch the simulation
vsim work.tb_i2c_master

# 7. Add all of the TB's signals to the wave window
add wave -r sim:/tb_i2c_master/*

# 8. Run for the required amount of time
run 2 ms
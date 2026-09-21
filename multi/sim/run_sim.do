# 1. Clean up any previous simulation
quit -sim

# 2. Delete the physical 'work' library if it already existed, to avoid corrupted data
if [file exists work] { vdel -all }

# 3. Create a clean 'work' library again
vlib work

# 4. Compile the reused UART and I2C design files (unmodified)
vcom ../../uart/rtl/uart_rx.vhd
vcom ../../uart/rtl/uart_tx.vhd
vcom ../../i2c/rtl/i2c_master.vhd

# 4b. Compile the new design files (note they live in the neighboring ../rtl/ folder)
vcom ../rtl/tick_gen.vhd
vcom ../rtl/multi_proto_top.vhd

# 5. Compile the testbench (in the current folder)
vcom tb_multi_proto_top.vhd

# 6. Launch the simulation
vsim work.tb_multi_proto_top

# 7. Add only the signals needed for screenshots, grouped by block
add wave -divider "Clock / Reset / Protocol selector"
add wave -label clk            sim:/tb_multi_proto_top/tb_clk
add wave -label reset_n        sim:/tb_multi_proto_top/tb_reset_n
add wave -label protocol_sel_i sim:/tb_multi_proto_top/tb_proto_sel

add wave -divider "Shared tick generator (tick_gen)"
add wave -label cnt_q             sim:/tb_multi_proto_top/dut/u_tick_gen/cnt_q
add wave -label thresh_max        sim:/tb_multi_proto_top/dut/u_tick_gen/thresh_max
add wave -label tick_uart_o       sim:/tb_multi_proto_top/dut/u_tick_gen/tick_uart_o
add wave -label tick_i2c_o        sim:/tb_multi_proto_top/dut/u_tick_gen/tick_i2c_o
add wave -label engines_reset_n_o sim:/tb_multi_proto_top/dut/u_tick_gen/engines_reset_n_o

add wave -divider "UART"
add wave -label rx_in_i  sim:/tb_multi_proto_top/tb_rx_in
add wave -label tx_out_o sim:/tb_multi_proto_top/tb_tx_out
add wave -label tx_oe_o  sim:/tb_multi_proto_top/tb_tx_oe

add wave -divider "I2C - host interface"
add wave -label start_i     sim:/tb_multi_proto_top/tb_start
add wave -label addr_i      sim:/tb_multi_proto_top/tb_addr
add wave -label rw_i        sim:/tb_multi_proto_top/tb_rw
add wave -label wdata_i     sim:/tb_multi_proto_top/tb_wdata
add wave -label last_byte_i sim:/tb_multi_proto_top/tb_last_byte
add wave -label rdata_o     sim:/tb_multi_proto_top/tb_rdata
add wave -label done_o      sim:/tb_multi_proto_top/tb_done
add wave -label busy_o      sim:/tb_multi_proto_top/tb_busy
add wave -label ack_err_o   sim:/tb_multi_proto_top/tb_ack_err

add wave -divider "I2C - physical bus (logical out/oe/in ports)"
add wave -label scl_out_o sim:/tb_multi_proto_top/tb_scl_out
add wave -label scl_oe_o  sim:/tb_multi_proto_top/tb_scl_oe
add wave -label scl_in_i  sim:/tb_multi_proto_top/tb_scl_in
add wave -label sda_out_o sim:/tb_multi_proto_top/tb_sda_out
add wave -label sda_oe_o  sim:/tb_multi_proto_top/tb_sda_oe
add wave -label sda_in_i  sim:/tb_multi_proto_top/tb_sda_in

add wave -divider "I2C - i2c_master's internal oe (before protocol gating)"
add wave -label i2c_master.sda_oe_o sim:/tb_multi_proto_top/dut/u_i2c/sda_oe_o
add wave -label i2c_master.scl_oe_o sim:/tb_multi_proto_top/dut/u_i2c/scl_oe_o

configure wave -namecolwidth 220
configure wave -valuecolwidth 100
wave zoom full

# 8. Run for the required amount of time
run 5 ms

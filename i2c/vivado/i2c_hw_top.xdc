# =============================================================================
# i2c_hw_top.xdc
#
# Manual pin constraints for the Digilent Arty A7 (35T or 100T -- the pinout
# is identical between the two, only the die/part number differs).
#
# IMPORTANT: verify these package pins against your own Arty A7 board files
# (Digilent's "Arty-A7-35-Master.xdc" / "Arty-A7-100-Master.xdc") before
# generating a bitstream. If you use the "Board" flow described in the guide
# (recommended -- Vivado assigns CLK100MHZ / CPU_RESETN / BTN / SW / LED
# automatically from the board definition), you only need the two PULLUP
# lines and the create_clock line from this file; delete/comment out the
# PACKAGE_PIN lines for CLK100MHZ, CPU_RESETN, BTN, SW and LED so they don't
# fight with what the Board flow assigns.
# =============================================================================

## Clock (100 MHz onboard oscillator)
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk_pin -waveform {0 5} [get_ports CLK100MHZ]

## Dedicated CPU RESET push button (already active-low -- matches reset_n directly)
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

## Push buttons BTN[3:0] -- only BTN(0) is used (fires one I2C transaction)
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports {BTN[0]}]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports {BTN[1]}]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports {BTN[2]}]
set_property -dict {PACKAGE_PIN B8 IOSTANDARD LVCMOS33} [get_ports {BTN[3]}]

## Slide switches SW[3:0] -- only SW(0) is used (rw_i: 0=write, 1=read)
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {SW[1]}]
set_property -dict {PACKAGE_PIN C10 IOSTANDARD LVCMOS33} [get_ports {SW[2]}]
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33} [get_ports {SW[3]}]

## LEDs LED[3:0]
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]

## Pmod JA -> the I2C bus under test. JA(0) = SCL, JA(1) = SDA.
## PULLUP TRUE enables the 7-series FPGA's internal weak pull-up on the IOB,
## which is exactly the "constraint: PULLUP=TRUE" option your own i2c_top.vhd
## comment refers to -- with no real slave and no external resistors, this is
## what keeps SDA/SCL idle-high so the open-drain driving in i2c_top actually
## produces a valid-looking bus.
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {JA[0]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {JA[1]}]

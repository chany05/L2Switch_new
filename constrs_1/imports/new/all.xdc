# System Clock and Reset

set_property PACKAGE_PIN B6 [get_ports FPGA_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports FPGA_CLK]

# Clock Definition (100MHz assumed - adjust period as needed for your board)
create_clock -period 10.000 -name sys_clk [get_ports FPGA_CLK]

# Input Delay Constraints (relative to sys_clk)
# 외부 입력 포트에 대한 타이밍 제약
set_input_delay -clock sys_clk 0 [get_ports FPGA_RST_BTN]
set_input_delay -clock sys_clk 0 [get_ports FPGA_SEND_BTN]
set_input_delay -clock sys_clk 0 [get_ports FPGA_ADD_PACKET_BTN]
set_input_delay -clock sys_clk 0 [get_ports {FPGA_SWITCHES[*]}]
set_input_delay -clock sys_clk 0 [get_ports {KEYPAD_COL[*]}]

set_property PACKAGE_PIN Y6 [get_ports FPGA_RST_BTN]
set_property IOSTANDARD LVCMOS33 [get_ports FPGA_RST_BTN]

# Text LCD Control Signals (lcd_enb, lcd_rs, lcd_rw)
set_property PACKAGE_PIN L5 [get_ports lcd_enb]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_enb]

set_property PACKAGE_PIN M2 [get_ports lcd_rs]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs]

set_property PACKAGE_PIN M1 [get_ports lcd_rw]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_rw]

# Text LCD Data Bus (lcd_data[7:0])
set_property PACKAGE_PIN J3 [get_ports {lcd_data[7]}]
set_property PACKAGE_PIN K1 [get_ports {lcd_data[6]}]
set_property PACKAGE_PIN K2 [get_ports {lcd_data[5]}]
set_property PACKAGE_PIN K3 [get_ports {lcd_data[4]}]
set_property PACKAGE_PIN K4 [get_ports {lcd_data[3]}]
set_property PACKAGE_PIN K5 [get_ports {lcd_data[2]}]
set_property PACKAGE_PIN L1 [get_ports {lcd_data[1]}]
set_property PACKAGE_PIN L4 [get_ports {lcd_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {lcd_data[*]}]

# Keypad Column Input (KEYPAD_COL[2:0])
set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_COL[2]}]

set_property PACKAGE_PIN AA8 [get_ports {KEYPAD_COL[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_COL[1]}]

set_property PACKAGE_PIN V8 [get_ports {KEYPAD_COL[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_COL[0]}]


# Keypad Row Output (KEYPAD_ROW[3:0])
set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_ROW[3]}]

set_property PACKAGE_PIN AA10 [get_ports {KEYPAD_ROW[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_ROW[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_ROW[1]}]

set_property PACKAGE_PIN AA9 [get_ports {KEYPAD_ROW[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {KEYPAD_ROW[0]}]

# 배열 전체에 대한 기본 IOSTANDARD를 한 번에 설정할 수도 있습니다.
# set_property IOSTANDARD LVCMOS33 [get_ports KEYPAD_COL]
# set_property IOSTANDARD LVCMOS33 [get_ports KEYPAD_ROW]


# DIP Switches (FPGA_SWITCHES[7:0]) - Mapped from DIPSW1 (LSB) to DIPSW8 (MSB)

set_property PACKAGE_PIN AA6 [get_ports {FPGA_SWITCHES[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[0]}]

set_property PACKAGE_PIN AB5 [get_ports {FPGA_SWITCHES[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[1]}]

set_property PACKAGE_PIN V6 [get_ports {FPGA_SWITCHES[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[2]}]

set_property PACKAGE_PIN W5 [get_ports {FPGA_SWITCHES[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[3]}]

set_property PACKAGE_PIN Y5 [get_ports {FPGA_SWITCHES[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[4]}]

set_property PACKAGE_PIN Y4 [get_ports {FPGA_SWITCHES[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[5]}]

set_property PACKAGE_PIN AB4 [get_ports {FPGA_SWITCHES[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[6]}]

set_property PACKAGE_PIN AB3 [get_ports {FPGA_SWITCHES[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_SWITCHES[7]}]

# Discrete LEDs (FPGA_LEDS[7:0]) - Mapped from LED1 (LSB) to LED8 (MSB)

set_property PACKAGE_PIN Y1 [get_ports {FPGA_LEDS[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[0]}]

set_property PACKAGE_PIN W3 [get_ports {FPGA_LEDS[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[1]}]

set_property PACKAGE_PIN W2 [get_ports {FPGA_LEDS[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[2]}]

set_property PACKAGE_PIN W1 [get_ports {FPGA_LEDS[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[3]}]

set_property PACKAGE_PIN V5 [get_ports {FPGA_LEDS[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[4]}]

set_property PACKAGE_PIN V4 [get_ports {FPGA_LEDS[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[5]}]

set_property PACKAGE_PIN V1 [get_ports {FPGA_LEDS[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[6]}]

set_property PACKAGE_PIN U5 [get_ports {FPGA_LEDS[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {FPGA_LEDS[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports FPGA_SEND_BTN]
set_property PACKAGE_PIN V7 [get_ports FPGA_SEND_BTN]
set_property PACKAGE_PIN AB9 [get_ports {KEYPAD_ROW[1]}]
set_property PACKAGE_PIN AB10 [get_ports {KEYPAD_ROW[3]}]
set_property PACKAGE_PIN Y8 [get_ports {KEYPAD_COL[2]}]

set_property PACKAGE_PIN AB6 [get_ports FPGA_ADD_PACKET_BTN]
set_property IOSTANDARD LVCMOS33 [get_ports FPGA_ADD_PACKET_BTN]
set_property DRIVE 12 [get_ports lcd_enb]

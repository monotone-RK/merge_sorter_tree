
create_clock -period 10.000 -name CLK [get_ports CLK]
set_property PACKAGE_PIN AK34 [get_ports CLK]
set_property IOSTANDARD LVDS [get_ports CLK]


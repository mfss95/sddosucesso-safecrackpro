# Restricao de tempo: clock de 50 MHz da DE2-115 (periodo de 20 ns)
create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty

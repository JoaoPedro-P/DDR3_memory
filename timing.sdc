# ==============================================================================
# 1. Clocks Ajustados (Frequência Ultra Conservadora para GLS)
# ==============================================================================

# Barramento AXI a 20 MHz (Período: 50 ns)
create_clock -name clk_axi_bus -period 50.000 [get_ports {clk_axi_bus}]

# Memória a 10 MHz (Período: 100 ns)
create_clock -name clk_mem -period 100.000 [get_ports {clk_mem}]

# Memória a 10 MHz, Defasado 90 graus (Atraso de 25 ns)
create_clock -name clk_90_mem -period 100.000 -waveform {25.000 75.000} [get_ports {clk_90_mem}]

# ==============================================================================
# 2. Agrupamento de Domínios Assíncronos (CDC)
# ==============================================================================
# Protege os ponteiros Gray das FIFOs contra distorções de roteamento.

set_clock_groups -asynchronous \
    -group [get_clocks {clk_axi_bus}] \
    -group [get_clocks {clk_mem clk_90_mem}]

# ==============================================================================
# 3. Resolvendo "Unconstrained Paths" (Atrasos de I/O de 5.0 ns)
# ==============================================================================

# Todas as entradas da CPU/Master AXI
set_input_delay -clock [get_clocks {clk_axi_bus}] 5.0 [get_ports {STARTW STARTR m_addr* m_wdata* m_wstrb* resetn_bus}]

# Todas as saídas de volta para a CPU/Master AXI
set_output_delay -clock [get_clocks {clk_axi_bus}] 5.0 [get_ports {m_rdata* m_wdone m_rdone m_wresp* m_rresp*}]

# Reset do domínio da memória
set_input_delay -clock [get_clocks {clk_mem}] 5.0 [get_ports {reset_mem}]
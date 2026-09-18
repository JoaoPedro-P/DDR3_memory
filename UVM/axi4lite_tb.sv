// [PT] Testbench de topo para conectar os sinais ao DUT e iniciar a simulação / [EN] Top testbench to connect signals to DUT and start simulation
`timescale 1ns / 1ps

import uvm_pkg::*;
import axi4lite_pkg::*; 
`include "uvm_macros.svh"

module axi4lite_tb;

    // [PT] Geracao de Clocks / [EN] Clock Generation 
    logic clk_axi_bus = 0;
    logic clk_mem = 0;
    logic clk_90_mem = 0;

    logic resetn_bus = 0;
    logic reset_mem = 0;

    // [PT] Clocks sempre alternando para o barramento e para a memória / [EN] Clocks always toggling for the bus and the memory
    always #25 clk_axi_bus = ~clk_axi_bus;            // [PT] T = 50ns / [EN] T = 50ns
    always #50 clk_mem = ~clk_mem;                    // [PT] T = 100ns / [EN] T = 100ns
    
    // [PT] Inicializa o relógio de 90 graus para memória / [EN] Initializes 90 degree clock for memory
    initial begin
        #25;
        forever #50 clk_90_mem = ~clk_90_mem;         // [PT] T = 100ns, defasado 25ns / [EN] T = 100ns, phase shifted 25ns
    end

    // [PT] Interface / [EN] Interface
    axi4lite_if _if(clk_axi_bus, resetn_bus);

    // [PT] DUT / [EN] DUT
    axi4lite_system #(
        .ADDR_WIDTH(27), 
        .DATA_WIDTH(32)
    ) DUT (
        .clk_axi_bus(clk_axi_bus),
        .clk_mem(clk_mem),
        .clk_90_mem(clk_90_mem),
        .resetn_bus(resetn_bus),
        .reset_mem(reset_mem),
        
        .STARTW(_if.STARTW),
        .STARTR(_if.STARTR),
        .m_addr(_if.m_addr),
        .m_wdata(_if.m_wdata),
        .m_wstrb(_if.m_wstrb),
        .m_awprot(_if.m_awprot),
        .m_arprot(_if.m_arprot),
        
        .m_rdata(_if.m_rdata),
        .m_wdone(_if.m_wdone),
        .m_rdone(_if.m_rdone),
        .m_wresp(_if.m_wresp),
        .m_rresp(_if.m_rresp)
    );

    // [PT] Reset gen / [EN] Reset gen
    initial begin
        resetn_bus = 0;
        reset_mem  = 0;
        #100;
        @(negedge clk_axi_bus);
        resetn_bus = 1;
        @(negedge clk_mem);
        reset_mem  = 1;
    end

    // [PT] UVM Start / [EN] UVM Start
    initial begin
        uvm_config_db#(virtual axi4lite_if)::set(null, "*", "vif", _if);
        run_test("axi4lite_test");
    end

endmodule
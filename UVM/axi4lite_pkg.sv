// [PT] Pacote do AXI-Lite que inclui todos os componentes UVM do ambiente / [EN] AXI-Lite package that includes all UVM components of the environment
package axi4lite_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // =========================================================
    // [PT] PARAMETROS GLOBAIS DE SIMULACAO E ARQUITETURA / [EN] GLOBAL SIMULATION AND ARCHITECTURE PARAMETERS
    // =========================================================
    parameter MEM_DEPTH_LOG2 = 10;              // [PT] Log2 da profundidade = Tamanho Total (Bits) = 2^MEM\_DEPTH\_LOG2 * 8 * DATA\_WIDTH / [EN] Log2 of depth = Total Size (Bits) = 2^MEM\_DEPTH\_LOG2 * 8 * DATA\_WIDTH
    parameter DEPTH = 1 << MEM_DEPTH_LOG2;     // [PT] Profundidade calculada / [EN] Calculated depth
    parameter NUM_BANKS = 8;                   // [PT] Bancos Fisicos da DDR3 / [EN] Physical DDR3 Banks
    parameter NUM_TESTS = 50000;            // [PT] Numero de transacoes na Fase 2 / [EN] Number of transactions in Phase 2

    `include "axi4lite_item.sv"
    `include "axi4lite_sequence.sv"
    `include "axi4lite_driver.sv"
    `include "axi4lite_monitor.sv"
    `include "axi4lite_agent.sv"
    `include "axi4lite_scoreboard.sv"
    `include "axi4lite_env.sv"
    `include "axi4lite_test.sv"
endpackage
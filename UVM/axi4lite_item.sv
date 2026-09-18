// =====================================================================
// [PT] Arquivo: axi4lite_item.sv / [EN] File: axi4lite_item.sv
// [PT] Descrição: Item de sequência UVM para AXI4-Lite, representando uma transação. / [EN] Description: UVM sequence item for AXI4-Lite, representing a transaction.
// =====================================================================

class axi4lite_item extends uvm_sequence_item;
    // [PT] Campos de estímulo / [EN] Stimulus fields
    rand bit        rnw; // [PT] 0 = Escrita, 1 = Leitura / [EN] 0 = Write, 1 = Read
    rand bit [26:0] addr;
    rand bit [31:0] data;
    rand bit [3:0]  wstrb;
    rand bit [2:0]  prot;

    // [PT] Respostas capturadas do DUT / [EN] Responses captured from the DUT
    bit [31:0] rdata;
    bit [1:0]  resp;

    // [PT] Macros de utilidade do UVM para registro da classe e dos campos / [EN] UVM utility macros for class and fields registration
    `uvm_object_utils_begin(axi4lite_item)
        `uvm_field_int(rnw,   UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data,  UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(wstrb, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(prot,  UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(rdata, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(resp,  UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    // [PT] Construtor / [EN] Constructor
    function new(string name = "axi4lite_item");
        super.new(name);
    endfunction

    // [PT] Restringe os testes normais à área útil, mantendo wstrb em 4'b1111 para testes cheios de 32 bits / [EN] Restricts normal tests to the useful area, keeping wstrb at 4'b1111 for full 32-bit tests
    constraint valid_traffic_c {
        //addr < 32'h4000000;
        wstrb == 4'b1111;
        prot inside {3'b000, 3'b001}; 
    }
endclass
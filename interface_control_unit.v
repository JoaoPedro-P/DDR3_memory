/*
 * module: interface_control_unit
 * -----------------
 * PT: Unidade de Interface de Controle. 
 *     Gerencia a tradução de endereços da CPU e o rastreamento de páginas (Open/Closed).
 * 
 * EN: Interface Control Unit.
 *     Manages CPU address translation and page tracking (Open/Closed policy).
 */
module interface_control_unit(
    input  wire        clk, rst_n, cpu_req, cpu_rnw, init_done,
    input  wire [26:0] cpu_address,
    input  wire [7:0]  cpu_active_flag, cpu_idle_flag,
    output wire [13:0] row_addr,
    output wire [9:0]  col_addr,
    output wire [2:0]  bank_addr,
    output wire        cpu_ready, CS, RAS, WE, CAS,
	output wire        cmd_ack // PT: Reconhecimento de comando da FIFO | EN: FIFO command acknowledgment
);
    wire page_empty, page_hit, page_miss, update_row_en;
    
    // PT: Lógica de Comunicação (FSM JEDEC) | EN: Communication Logic (JEDEC FSM)
    comunication_control_logic comu_inst(
        .clk(clk), .rst_n(rst_n), .init_done(init_done),
        .cpu_req(cpu_req), .cpu_rnw(cpu_rnw), .page_hit(page_hit),
        .page_empty(page_empty), .page_miss(page_miss), .cpu_idle_flag(cpu_idle_flag),
        .cpu_active_flag(cpu_active_flag), .cpu_bank_addr(bank_addr),
        .cpu_ready(cpu_ready), .update_row_en(update_row_en), .CS(CS),
        .RAS(RAS), .CAS(CAS), .WE(WE),
        .cmd_ack(cmd_ack) 
    );

    // PT: Decodificador de Endereço | EN: CPU Address Decoder
    cpu_addr_decoder decoder_inst (
        .cpu_addr(cpu_address),
        .row_addr(row_addr),
        .bank_addr(bank_addr),
        .col_addr(col_addr)
    );

    // PT: Rastreador de Linhas (Page Policy) | EN: Row Tracker
    row_tracker tracker_inst(
        .clk(clk), .rst_n(rst_n), .update_row_en(update_row_en),
        .cpu_bank_addr(bank_addr), .cpu_row_addr(row_addr),
        .cpu_idle_flag(cpu_idle_flag), .cpu_active_flag(cpu_active_flag),
        .page_hit(page_hit), .page_miss(page_miss), .page_empty(page_empty)
    );
endmodule

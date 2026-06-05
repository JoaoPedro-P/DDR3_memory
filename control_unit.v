/*
 * module: control_unit
 * -----------------
 * PT: Unidade de Controle do Back-End. Arbitra entre a FSM de Inicialização, 
 *     a injeção de Refresh e os comandos do usuário.
 * 
 * EN: Back-End Control Unit. Arbitrates between the Initialization FSM,
 *     Refresh injection, and user commands.
 */
module control_unit #(parameter freq = 100) (
    input  wire clk, rst, 
    input  wire CS, RAS, CAS, WE, 
    input  wire [12:0] A, 
    input  wire [2:0]  BA,
    input  wire        frontend_idle_safe,
    
    // PT: Saídas Físicas (Chip Pins) | EN: Physical Outputs (Chip Pins)
    output wire CKE, RESET_n,
    output wire CS_out, RAS_out, CAS_out, WE_out,
    output wire [12:0] A_out,
    output wire [2:0] BA_out,
    
    // PT: Saídas Internas | EN: Internal Status Outputs
    output wire init_done, enable_read_fifo, enable_write_drivers, enable_row_decoder, refresh_mem_flag,
    output wire [7:0]  BC4_flag, AP_flag, bank_active_flag, bank_idle_flag,
    output wire [12:0] MR0, MR1, MR2, MR3
);

    wire CS_init, RAS_init, CAS_init, WE_init;
    wire [2:0]  BA_init;
    wire [12:0] A_init;
    wire refresh_ack, refresh_req, inject_refresh;

    /* -------------------------------------------------------------------------
     * PT: Multiplexador Inteligente (Arbiter de 3 vias)
     * EN: Intelligent Multiplexer (3-way Arbiter)
     * 
     * Via 1: Boot (init_done = 0)
     * Via 2: Injeção de Refresh (inject_refresh = 1)
     * Via 3: Mestre AXI / Usuário
     * -------------------------------------------------------------------------
     */
    assign CS_out  = (!init_done) ? CS_init  : (inject_refresh ? 1'b0 : CS);
    assign RAS_out = (!init_done) ? RAS_init : (inject_refresh ? 1'b0 : RAS);
    assign CAS_out = (!init_done) ? CAS_init : (inject_refresh ? 1'b0 : CAS);
    assign WE_out  = (!init_done) ? WE_init  : (inject_refresh ? 1'b1 : WE);
    
    assign BA_out  = (!init_done) ? BA_init  : BA;
    assign A_out   = (!init_done) ? A_init   : A;

    // PT: Máquina de Inicialização | EN: Initialization FSM
    inicialization_control_logic #(.freq(freq)) init_FSM (
        .CK(clk), 
        .rst_n(rst), 
        .RESET_n(RESET_n), 
        .CKE(CKE), 
        .init_done(init_done),
        .CS_n(CS_init), .RAS_n(RAS_init), .CAS_n(CAS_init), .WE_n(WE_init),
        .BA(BA_init),
        .A(A_init)
    );

    // PT: Máquina de Controle de Dados (8 Bancos) | EN: Data Control Logic (8 Banks)
    datapath_control_logic #(.freq(freq)) data_FSM (
        .CK(clk), 
        .RESET_n(RESET_n), 
        .CS_n(CS_out), .A12(A_out[12]), .A10(A_out[10]),
        .RAS_n(RAS_out), .CAS_n(CAS_out), .WE_n(WE_out), 
        .A(A_out), .BA(BA_out),
        .CKE(CKE),
        .enable_read_fifo(enable_read_fifo),
		.frontend_idle_safe(frontend_idle_safe),
        .enable_write_drivers(enable_write_drivers), 
        .enable_row_decoder(enable_row_decoder),
        .BC4_flag(BC4_flag), .AP_flag(AP_flag), 
        .bank_active_flag(bank_active_flag), .bank_idle_flag(bank_idle_flag),
        .MR0(MR0), .MR1(MR1), .MR2(MR2), .MR3(MR3),
		.refresh_ack(refresh_ack),
		.refresh_req(refresh_req),
		.refresh_mem_flag(refresh_mem_flag),
		.inject_refresh(inject_refresh)
    );
	 
	// PT: Controle de refresh | EN: Refresh control logic
	refresh_control_logic #(.freq(freq)) refresh_logic (
        .CK(clk), 
        .RESET_n(RESET_n),
	    .init_done(init_done), 
        .refresh_ack(refresh_ack), 
        .refresh_req(refresh_req)
    );
	 
endmodule

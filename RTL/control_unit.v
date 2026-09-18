// [PT] Módulo: control_unit - Unidade de Controle do Back-End. Arbitra entre a FSM de Inicialização, a injeção de Refresh e os comandos do usuário. Entradas: clk, rst, sinais JEDEC, estado frontend. Saídas: Pinos físicos da RAM e flags. / [EN] Module: control_unit - Back-End Control Unit. Arbitrates between the Initialization FSM, Refresh injection, and user commands. Inputs: clk, rst, JEDEC signals, frontend state. Outputs: RAM physical pins and flags.
module control_unit #(parameter freq = 100) (
    input  wire clk, rst, 
    input  wire CS, RAS, CAS, WE, 
    input  wire [12:0] A, 
    input  wire [2:0]  BA,
    input  wire        frontend_idle_safe,
    
    // [PT] Saídas Físicas (Pinos do Chip) / [EN] Physical Outputs (Chip Pins)
    output wire CS_out, RAS_out, CAS_out, WE_out, RESET_n,
    output wire [12:0] A_out,
    output wire [2:0] BA_out,
    
    // [PT] Saídas de Status Internas / [EN] Internal Status Outputs
    output wire init_done, enable_read_fifo, enable_write_drivers, enable_row_decoder, refresh_mem_flag,
    output wire [7:0]  BC4_flag, AP_flag, bank_active_flag, bank_idle_flag,
    output wire [12:0] MR0, MR1, MR2, MR3
);

    wire CS_init, RAS_init, CAS_init, WE_init, CKE;
    wire [2:0]  BA_init;
    wire [12:0] A_init;
    wire refresh_ack, refresh_req, inject_refresh;

    // [PT] Multiplexador Inteligente (Arbiter de 3 vias): Boot, Injeção de Refresh, Mestre AXI / [EN] Intelligent Multiplexer (3-way Arbiter): Boot, Refresh Injection, AXI Master
    assign CS_out  = (!init_done) ? CS_init  : (inject_refresh ? 1'b0 : CS);
    assign RAS_out = (!init_done) ? RAS_init : (inject_refresh ? 1'b0 : RAS);
    assign CAS_out = (!init_done) ? CAS_init : (inject_refresh ? 1'b0 : CAS);
    assign WE_out  = (!init_done) ? WE_init  : (inject_refresh ? 1'b1 : WE);
    
    assign BA_out  = (!init_done) ? BA_init  : BA;
    assign A_out   = (!init_done) ? A_init   : A;

    // [PT] Instanciação da Máquina de Inicialização (FSM) / [EN] Initialization FSM Instantiation
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

    // [PT] Instanciação da Lógica de Controle de Dados (FSM para os 8 Bancos) / [EN] Data Control Logic Instantiation (FSM for 8 Banks)
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
	 
	// [PT] Instanciação do Controle de Refresh / [EN] Refresh control logic Instantiation
	refresh_control_logic #(.freq(freq)) refresh_logic (
        .CK(clk), 
        .RESET_n(RESET_n),
	    .init_done(init_done), 
        .refresh_ack(refresh_ack), 
        .refresh_req(refresh_req)
    );
	 
endmodule

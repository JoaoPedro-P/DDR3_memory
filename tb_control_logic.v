`timescale 1ns / 1ps

module tb_control_logic();

    // -------------------------------------------------------------------------
    // Parametrização replicada do DUT
    // -------------------------------------------------------------------------
    localparam freq = 100;
    localparam num_cicles = (freq / 67) + 1;

    // -------------------------------------------------------------------------
    // Sinais de Interface
    // -------------------------------------------------------------------------
    reg CKE, CK, RESET_n, CS_n, A12, A10, RAS_n, CAS_n, WE_n;
    reg [12:0] A;  // Payload de 13 bits (A13 descartado na arquitetura física)
    reg [2:0] BA;

    wire enable_read_fifo, enable_row_decoder, enable_write_drivers;
    wire [7:0] BC4_flag, AP_flag, bank_active_flag, bank_idle_flag;
    wire [7:0] start_tRCD_timer, start_tRP_timer;
    
    // CORREÇÃO: Sinais dos Mode Registers agora com 13 bits
    wire [12:0] MR0, MR1, MR2, MR3;

    integer errors = 0;
    integer i;

    // -------------------------------------------------------------------------
    // Instanciação do DUT
    // -------------------------------------------------------------------------
    datapath_control_logic dut (
        .CKE(CKE), .CK(CK), .RESET_n(RESET_n), .CS_n(CS_n), 
        .A12(A12), .A10(A10), .RAS_n(RAS_n), .CAS_n(CAS_n), .WE_n(WE_n),
        .A(A), .BA(BA), 
        .enable_read_fifo(enable_read_fifo), 
        .start_tRCD_timer(start_tRCD_timer), 
        .start_tRP_timer(start_tRP_timer), 
        .enable_row_decoder(enable_row_decoder), 
        .enable_write_drivers(enable_write_drivers), 
        .BC4_flag(BC4_flag), 
        .AP_flag(AP_flag), 
        .bank_active_flag(bank_active_flag), 
        .bank_idle_flag(bank_idle_flag),
        .MR0(MR0), .MR1(MR1), .MR2(MR2), .MR3(MR3) // Conectando os MRS
    );

    // -------------------------------------------------------------------------
    // Geração de Clock
    // -------------------------------------------------------------------------
    initial begin
        CK = 0;
        forever #5 CK = ~CK;
    end

    // -------------------------------------------------------------------------
    // Tasks de Estímulo (Driver)
    // -------------------------------------------------------------------------
    task apply_reset;
    begin
        CKE = 1; CS_n = 1; RAS_n = 1; CAS_n = 1; WE_n = 1; 
        A10 = 0; A12 = 0; BA = 0; A = 0;
        RESET_n = 0;
        @(posedge CK);
        @(posedge CK);
        RESET_n = 1;
    end
    endtask

    task send_nop;
    begin
        CS_n <= 0; RAS_n <= 1; CAS_n <= 1; WE_n <= 1;
        @(posedge CK);
    end
    endtask

    task send_mrs;
        input [2:0] bank_addr;
        input [12:0] payload; // CORREÇÃO: Payload de 13 bits
    begin
        CS_n <= 0; RAS_n <= 0; CAS_n <= 0; WE_n <= 0; // MRS = L, L, L, L
        BA <= bank_addr;
        A  <= payload;
        @(posedge CK);
    end
    endtask

    task send_act;
        input [2:0] bank_addr;
    begin
        CS_n <= 0; RAS_n <= 0; CAS_n <= 1; WE_n <= 1;
        BA <= bank_addr; 
        @(posedge CK);
    end
    endtask

    task send_read;
        input [2:0] bank_addr;
        input a10_ap;
        input a12_bc4;
    begin
        CS_n <= 0; RAS_n <= 1; CAS_n <= 0; WE_n <= 1;
        BA <= bank_addr;
        A10 <= a10_ap; A12 <= a12_bc4;
        @(posedge CK);
    end
    endtask

    task send_write;
        input [2:0] bank_addr;
        input a10_ap;
        input a12_bc4;
    begin
        CS_n <= 0; RAS_n <= 1; CAS_n <= 0; WE_n <= 0;
        BA <= bank_addr;
        A10 <= a10_ap; A12 <= a12_bc4;
        @(posedge CK);
    end
    endtask

    task send_precharge;
        input [2:0] bank_addr;
        input a10_all;
    begin
        CS_n <= 0; RAS_n <= 0; CAS_n <= 1; WE_n <= 0;
        BA <= bank_addr;
        A10 <= a10_all; 
        @(posedge CK);
    end
    endtask

    // -------------------------------------------------------------------------
    // Tasks de Auto-Verificação (Scoreboard)
    // -------------------------------------------------------------------------
    task check_mr;
        input [8*35:1] step_name;
        input [12:0] exp_mr0, exp_mr1, exp_mr2, exp_mr3; // CORREÇÃO: Valores esperados de 13 bits
    begin
        if (CK == 1'b1) @(negedge CK); else #1;
        
        if (MR0 !== exp_mr0) begin $display("[ERRO - %0s] MR0 exp %h, obt %h", step_name, exp_mr0, MR0); errors = errors + 1; end
        if (MR1 !== exp_mr1) begin $display("[ERRO - %0s] MR1 exp %h, obt %h", step_name, exp_mr1, MR1); errors = errors + 1; end
        if (MR2 !== exp_mr2) begin $display("[ERRO - %0s] MR2 exp %h, obt %h", step_name, exp_mr2, MR2); errors = errors + 1; end
        if (MR3 !== exp_mr3) begin $display("[ERRO - %0s] MR3 exp %h, obt %h", step_name, exp_mr3, MR3); errors = errors + 1; end
    end
    endtask

    task check_outputs;
        input [8*35:1] step_name;
        input [2:0] chk_bank;
        input exp_idle, exp_act, exp_row_dec, exp_rcd_tmr, exp_rp_tmr, exp_rd_fifo, exp_wr_drv;
    begin
        if (CK == 1'b1) @(negedge CK); else #1;
        
        if (bank_idle_flag[chk_bank] !== exp_idle)       begin $display("[ERRO - %0s] bank_idle_flag[%0d] exp %b, obt %b", step_name, chk_bank, exp_idle, bank_idle_flag[chk_bank]); errors = errors + 1; end
        if (bank_active_flag[chk_bank] !== exp_act)      begin $display("[ERRO - %0s] bank_active_flag[%0d] exp %b, obt %b", step_name, chk_bank, exp_act, bank_active_flag[chk_bank]); errors = errors + 1; end
        if (start_tRCD_timer[chk_bank] !== exp_rcd_tmr)  begin $display("[ERRO - %0s] start_tRCD_timer[%0d] exp %b, obt %b", step_name, chk_bank, exp_rcd_tmr, start_tRCD_timer[chk_bank]); errors = errors + 1; end
        if (start_tRP_timer[chk_bank] !== exp_rp_tmr)    begin $display("[ERRO - %0s] start_tRP_timer[%0d] exp %b, obt %b", step_name, chk_bank, exp_rp_tmr, start_tRP_timer[chk_bank]); errors = errors + 1; end
        if (enable_row_decoder !== exp_row_dec)          begin $display("[ERRO - %0s] enable_row_decoder exp %b, obt %b", step_name, exp_row_dec, enable_row_decoder); errors = errors + 1; end
        if (enable_read_fifo !== exp_rd_fifo)            begin $display("[ERRO - %0s] enable_read_fifo exp %b, obt %b", step_name, exp_rd_fifo, enable_read_fifo); errors = errors + 1; end
        if (enable_write_drivers !== exp_wr_drv)         begin $display("[ERRO - %0s] enable_write_drivers exp %b, obt %b", step_name, exp_wr_drv, enable_write_drivers); errors = errors + 1; end
    end
    endtask

    // -------------------------------------------------------------------------
    // Sequência de Testes
    // -------------------------------------------------------------------------
    initial begin
        $display("=================================================");
        $display("TESTE DE COBERTURA ESTENDIDA DDR3 (13-BITS MRS)");
        $display("=================================================");

        // ---------------------------------------------
        // FASE 1: Reset e Configuração (MRS)
        // ---------------------------------------------
        apply_reset();
        check_mr("Reset MRS                          ", 13'h0, 13'h0, 13'h0, 13'h0);

        send_mrs(3'b000, 13'h0A5A); send_nop(); // Grava no MR0
        check_mr("Grava MR0                          ", 13'h0A5A, 13'h0, 13'h0, 13'h0);
        
        send_mrs(3'b001, 13'h1234); send_nop(); // Grava no MR1
        check_mr("Grava MR1                          ", 13'h0A5A, 13'h1234, 13'h0, 13'h0);
        
        // CORREÇÃO: Valores hexagonais ajustados para caberem em 13 bits (max 1FFF)
        send_mrs(3'b010, 13'h0222); send_nop(); // Grava no MR2
        send_mrs(3'b011, 13'h1FFF); send_nop(); // Grava no MR3
        check_mr("Grava MR2 e MR3                    ", 13'h0A5A, 13'h1234, 13'h0222, 13'h1FFF);

        // Teste de Segurança: Tenta gravar num endereço RFU (Reservado)
        send_mrs(3'b100, 13'h1000); send_nop();
        check_mr("Ignora RFU (Endereco Invalido)     ", 13'h0A5A, 13'h1234, 13'h0222, 13'h1FFF);

        // ---------------------------------------------
        // FASE 2: Interleaving de Ativação
        // ---------------------------------------------
        send_act(3'd0); // Ativa B0
        check_outputs("ACT B0                           ", 3'd0, 0, 0, 1, 1, 0, 0, 0); 

        send_act(3'd1); // Ativa B1
        check_outputs("ACT B1                           ", 3'd1, 0, 0, 1, 1, 0, 0, 0); 
        
        for (i = 0; i < num_cicles; i = i + 1) send_nop(); // Aguarda tRCD

        check_outputs("B0 Ativo                           ", 3'd0, 0, 1, 0, 0, 0, 0, 0);
        check_outputs("B1 Ativo                           ", 3'd1, 0, 1, 0, 0, 0, 0, 0);

        // ---------------------------------------------
        // FASE 3: Interleaving de Dados (Write -> Read)
        // ---------------------------------------------
        send_write(3'd0, 0, 1); // WRITE B0 (No AP, BL8)
        check_outputs("WR B0                            ", 3'd0, 0, 1, 0, 0, 0, 0, 1);

        send_write(3'd1, 0, 1); // WRITE B1 (No AP, BL8) imediatamente depois
        check_outputs("WR B1                            ", 3'd1, 0, 1, 0, 0, 0, 0, 1);

        send_nop(); send_nop(); send_nop(); // Completa os bursts

        send_read(3'd0, 0, 1); // READ B0
        check_outputs("RD B0                            ", 3'd0, 0, 1, 0, 0, 0, 1, 0);

        send_nop(); send_nop(); send_nop(); send_nop(); // Fim do burst B0

        // ---------------------------------------------
        // FASE 4: Auto-Precharge vs Manual
        // ---------------------------------------------
        // Vamos dar um comando de Read no B0 COM Auto-Precharge
        send_read(3'd0, 1, 1); // READ B0 (A10 = 1, AP)
        check_outputs("RD AP B0                         ", 3'd0, 0, 1, 0, 0, 0, 1, 0);
        
        send_nop(); send_nop(); send_nop(); // Completa o burst

        // Como foi com Auto-Precharge, o Banco 0 DEVE transitar para PRECHARGING
        send_nop();
        check_outputs("B0 entrou em Auto-Precharge      ", 3'd0, 0, 0, 0, 0, 1, 0, 0);
        
        // O Banco 1, que não recebeu AP, DEVE continuar ativo
        check_outputs("B1 Continua Ativo                ", 3'd1, 0, 1, 0, 0, 0, 0, 0);

        // Comando manual de Precharge no Banco 1
        send_precharge(3'd1, 0); // A10 = 0 (Precharge Unico)
        check_outputs("B1 entrou em Precharge manual    ", 3'd1, 0, 0, 0, 0, 1, 0, 0);

        // Espera tRP
        for (i = 0; i < num_cicles; i = i + 1) send_nop();

        // Verifica se ambos estão dormindo
        send_nop();
        check_outputs("B0 IDLE                          ", 3'd0, 1, 0, 0, 0, 0, 0, 0);
        check_outputs("B1 IDLE                          ", 3'd1, 1, 0, 0, 0, 0, 0, 0);

        $display("=================================================");
        if (errors == 0) begin
            $display("SIMULACAO CONCLUIDA COM SUCESSO! 0 ERROS.");
        end else begin
            $display("SIMULACAO FALHOU COM %0d ERRO(S).", errors);
        end
        $display("=================================================");
        $finish;
    end

endmodule
`timescale 1ns / 1ps

module tb_control_unit();

    // -------------------------------------------------------------------------
    // Parâmetros do Teste
    // -------------------------------------------------------------------------
    localparam freq = 100;
    localparam num_cicles = (freq / 67) + 1; // Para tRCD e tRP

    // -------------------------------------------------------------------------
    // Sinais de Interface
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;
    
    // Barramento Externo (Mestre / Usuário)
    reg CS, RAS, CAS, WE;
    reg [12:0] A;
    reg [2:0]  BA;
    
    // Saídas Físicas (Para a memória)
    wire CKE;
    wire RESET_n;
    wire CS_out, RAS_out, CAS_out, WE_out;
    wire [12:0] A_out;
    wire [2:0] BA_out;
    
    // Sinais Internos e Flags de Controle
    wire init_done;
    wire enable_read_fifo, enable_write_drivers, enable_row_decoder;
    wire [7:0] BC4_flag, AP_flag, bank_active_flag, bank_idle_flag;
    wire [7:0] start_tRCD_timer, start_tRP_timer;
    wire [12:0] MR0, MR1, MR2, MR3;

    integer errors = 0;
    integer i;

    // -------------------------------------------------------------------------
    // Instanciação do DUT (Device Under Test)
    // -------------------------------------------------------------------------
    control_unit #(.freq(freq)) dut (
        .clk(clk), 
        .rst(rst),
        .CS(CS), .RAS(RAS), .CAS(CAS), .WE(WE),
        .A(A), .BA(BA),
        .CKE(CKE), .RESET_n(RESET_n),
        .CS_out(CS_out), .RAS_out(RAS_out), .CAS_out(CAS_out), .WE_out(WE_out),
        .A_out(A_out), .BA_out(BA_out),
        .init_done(init_done),
        .enable_read_fifo(enable_read_fifo), 
        .enable_write_drivers(enable_write_drivers), 
        .enable_row_decoder(enable_row_decoder),
        .BC4_flag(BC4_flag), .AP_flag(AP_flag), 
        .bank_active_flag(bank_active_flag), .bank_idle_flag(bank_idle_flag),
        .start_tRCD_timer(start_tRCD_timer), .start_tRP_timer(start_tRP_timer),
        .MR0(MR0), .MR1(MR1), .MR2(MR2), .MR3(MR3)
    );

    // -------------------------------------------------------------------------
    // Geração de Clock (100 MHz -> Período de 10ns)
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // DRIVER: Tasks de Estímulo
    // -------------------------------------------------------------------------
    task apply_reset;
    begin
        CS = 1; RAS = 1; CAS = 1; WE = 1; A = 0; BA = 0;
        rst = 1; // Ativo Baixo
        @(posedge clk);
        rst = 0; // Aplica Reset
        @(posedge clk);
        @(posedge clk);
        rst = 1; // Libera Reset
    end
    endtask

    task send_nop;
    begin
        CS <= 0; RAS <= 1; CAS <= 1; WE <= 1;
        @(posedge clk);
    end
    endtask

    task send_mrs;
        input [2:0] bank_addr;
        input [12:0] payload;
    begin
        CS <= 0; RAS <= 0; CAS <= 0; WE <= 0;
        BA <= bank_addr;
        A  <= payload;
        @(posedge clk);
    end
    endtask

    task send_act;
        input [2:0] bank_addr;
    begin
        CS <= 0; RAS <= 0; CAS <= 1; WE <= 1;
        BA <= bank_addr; 
        @(posedge clk);
    end
    endtask

    task send_read;
        input [2:0] bank_addr;
        input a10_ap;
        input a12_bc4;
    begin
        CS <= 0; RAS <= 1; CAS <= 0; WE <= 1;
        BA <= bank_addr;
        A[10] <= a10_ap; A[12] <= a12_bc4;
        @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------------
    // SCOREBOARD: Tasks de Verificação
    // -------------------------------------------------------------------------
    task check_mr;
        input [8*35:1] step_name;
        input [12:0] exp_mr0, exp_mr1, exp_mr2, exp_mr3;
    begin
        if (clk == 1'b1) @(negedge clk); else #1;
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
        if (clk == 1'b1) @(negedge clk); else #1;
        if (bank_idle_flag[chk_bank] !== exp_idle)       begin $display("[ERRO - %0s] idle_flag[%0d] exp %b, obt %b", step_name, chk_bank, exp_idle, bank_idle_flag[chk_bank]); errors = errors + 1; end
        if (bank_active_flag[chk_bank] !== exp_act)      begin $display("[ERRO - %0s] act_flag[%0d] exp %b, obt %b", step_name, chk_bank, exp_act, bank_active_flag[chk_bank]); errors = errors + 1; end
        if (enable_row_decoder !== exp_row_dec)          begin $display("[ERRO - %0s] row_decoder exp %b, obt %b", step_name, exp_row_dec, enable_row_decoder); errors = errors + 1; end
        if (enable_read_fifo !== exp_rd_fifo)            begin $display("[ERRO - %0s] read_fifo exp %b, obt %b", step_name, exp_rd_fifo, enable_read_fifo); errors = errors + 1; end
    end
    endtask

    // -------------------------------------------------------------------------
    // SEQUÊNCIA DE TESTE
    // -------------------------------------------------------------------------
    initial begin
        $display("===============================================================");
        $display("INICIANDO SIMULACAO DO CONTROL UNIT (BOOT + DATAPATH + REFRESH)");
        $display("===============================================================");

        // FASE 1: Boot e Inicialização
        apply_reset();
        $display("[INFO] Reset aplicado. Aguardando init_FSM finalizar a rotina física...");
        
        wait(init_done == 1'b1);
        $display("[INFO] Inicializacao concluida em %0t ns!", $time);

        check_mr("Pos-Boot Capture", 13'h0100, 13'h0000, 13'h0000, 13'h0000);
        check_outputs("Datapath em IDLE", 3'd0, 1, 0, 0, 0, 0, 0, 0);

        // FASE 2: Intervenção do Mestre
        $display("[INFO] Assumindo controle pelo barramento Mestre.");
        send_mrs(3'b001, 13'h1234); 
        send_nop();
        check_mr("Mestre sobrescreve MR1", 13'h0100, 13'h1234, 13'h0000, 13'h0000);

        // FASE 3: Testando a Máquina de Dados (Bank Interleaving)
        $display("[INFO] Iniciando testes de Bank Interleaving e Comandos.");
        send_act(3'd0); // Ativa Banco 0
        send_act(3'd1); // Ativa Banco 1
        for (i = 0; i < num_cicles; i = i + 1) send_nop();

        // FASE 4: Pipeline de Leitura
        send_read(3'd0, 0, 1); // READ no B0 sem Auto-Precharge
        send_nop(); send_nop(); send_nop(); send_nop(); // Esvazia o burst

        // FASE 5: Teste Autônomo de Refresh
        $display("---------------------------------------------------------------");
		  $display("[INFO] Frequencia atual: %0d MHz.", freq);
        $display("[INFO] Esperando %0d ciclos para o trigger do Refresh...", (7800 * freq) / 1000);
        
        // Aguarda o temporizador de 780 ciclos disparar
        wait(dut.refresh_req == 1'b1);
        $display("[INFO] Temporizador estourou! refresh_req = 1 no tempo %0t ns", $time);
        
        // O datapath deve forçar o fechamento (precharge) dos bancos 0 e 1 imediatamente
        @(posedge clk);
		  @(negedge clk);
        if (dut.data_FSM.state[0] !== 3'b101) begin // 3'b101 = PRECHARGING
            $display("[ERRO] Datapath nao forcou o Precharge do Banco 0!");
            errors = errors + 1;
        end
        if (dut.data_FSM.state[1] !== 3'b101) begin
            $display("[ERRO] Datapath nao forcou o Precharge do Banco 1!");
            errors = errors + 1;
        end
        
        // Aguarda a injeção do comando físico no barramento
        wait(dut.inject_refresh == 1'b1);
        $display("[INFO] Todos os bancos em IDLE. Datapath injetou o comando!");
        
        // Verifica se o multiplexador forçou os pinos de saída para REFRESH (0001)
        if ({CS_out, RAS_out, CAS_out, WE_out} !== 4'b0001) begin
            $display("[ERRO] Multiplexador falhou em injetar o comando REFRESH. Obtido: %b", {CS_out, RAS_out, CAS_out, WE_out});
            errors = errors + 1;
        end else begin
            $display("[OK] Pinos fisicos assumiram comando REFRESH (CS=0, RAS=0, CAS=0, WE=1) corretamente.");
        end
        
        // Aguarda a FSM terminar a contagem de 11 ciclos (tRFC) e devolver o ACK
        wait(dut.refresh_ack == 1'b1);
        $display("[INFO] Ciclo tRFC concluido. refresh_ack enviado para reiniciar o timer em %0t ns", $time);
        $display("---------------------------------------------------------------");

        $display("===============================================================");
        if (errors == 0) begin
            $display("SIMULACAO CONCLUIDA COM SUCESSO! 0 ERROS.");
        end else begin
            $display("SIMULACAO FALHOU COM %0d ERRO(S).", errors);
        end
        $display("===============================================================");
        $finish;
    end

endmodule
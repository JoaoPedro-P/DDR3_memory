`timescale 1ns / 1ps

module tb_interface_control_unit();

    // -------------------------------------------------------------------------
    // Sinais de Interface
    // -------------------------------------------------------------------------
    reg clk, rst_n, cpu_req, cpu_rnw, init_done;
    reg [26:0] cpu_address;
    reg [7:0]  cpu_active_flag, cpu_idle_flag;

    wire [13:0] row_addr;
    wire [9:0]  col_addr;
    wire [2:0]  bank_addr;
    wire cpu_ready, CS, RAS, WE, CAS;

    integer errors = 0;
    integer i;

    // -------------------------------------------------------------------------
    // Rastreador Interno do Testbench para calcular Hit/Miss/Empty
    // -------------------------------------------------------------------------
    reg [13:0] tb_open_row [0:7];
    reg [1:0]  calc_type;
    reg [2:0]  rand_bank;
    reg [13:0] rand_row;
    reg [9:0]  rand_col;
    reg        rand_rnw;

    // -------------------------------------------------------------------------
    // Instanciação do DUT
    // -------------------------------------------------------------------------
    interface_control_unit dut (
        .clk(clk), .rst_n(rst_n), .cpu_req(cpu_req), .cpu_rnw(cpu_rnw), .init_done(init_done),
        .cpu_address(cpu_address),
        .cpu_active_flag(cpu_active_flag), .cpu_idle_flag(cpu_idle_flag),
        .row_addr(row_addr), .col_addr(col_addr), .bank_addr(bank_addr),
        .cpu_ready(cpu_ready), .CS(CS), .RAS(RAS), .WE(WE), .CAS(CAS)
    );

    // -------------------------------------------------------------------------
    // Geração de Clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // "MOCK" DO DATAPATH FÍSICO
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if ({CS, RAS, CAS, WE} == 4'b0011) begin // ACTIVATE detectado
            cpu_idle_flag[bank_addr]   <= 1'b0;
            cpu_active_flag[bank_addr] <= 1'b1; 
        end
        else if ({CS, RAS, CAS, WE} == 4'b0010) begin // PRECHARGE detectado
            cpu_idle_flag[bank_addr]   <= 1'b1;
            cpu_active_flag[bank_addr] <= 1'b0;
        end
    end

    function [26:0] get_addr(input [13:0] r, input [2:0] b, input [9:0] c);
        get_addr = {r, b, c};
    endfunction

    task check_cmd(input [3:0] expected_cmd, input [8*25:1] msg);
        begin
            if ({CS, RAS, CAS, WE} !== expected_cmd) begin
                $display("[ERRO] %0s. Esperado: %b, Obtido: %b no tempo %0t", msg, expected_cmd, {CS, RAS, CAS, WE}, $time);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // DRIVER: Emulador do Processador (Ajustado para os delays CDC_WAIT1/2)
    // -------------------------------------------------------------------------
    task cpu_transaction(input [13:0] r, input [2:0] b, input [9:0] c, input rnw, input [1:0] expected_type);
        begin
            @(posedge clk);
            cpu_address = get_addr(r, b, c);
            cpu_rnw = rnw;
            cpu_req = 1'b1;

            wait(cpu_ready == 1'b0); // FSM saiu do estado IDLE

            if (expected_type == 1) begin
                // EMPTY: ACT_CMD -> ACT_WAIT -> CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN
                @(negedge clk);
                check_cmd(4'b0011, "ACTIVATE Cmd (Empty)");
                
                wait(cpu_active_flag[b] == 1'b1); 
                @(posedge clk); // Entra em CDC_WAIT1
                @(posedge clk); // Entra em CDC_WAIT2
                @(posedge clk); // Entra em CMD_GEN
                @(negedge clk); // Borda de descida para checar os pinos no meio do ciclo
            end
            else if (expected_type == 2) begin
                // MISS: PRE_CMD -> PRE_WAIT -> ACT_CMD -> ACT_WAIT -> CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN
                @(negedge clk);
                check_cmd(4'b0010, "PRECHARGE Cmd (Miss)");
                
                wait(cpu_idle_flag[b] == 1'b1);   
                @(posedge clk); // Entra em ACT_CMD
                @(negedge clk);
                check_cmd(4'b0011, "ACTIVATE Cmd (Miss)");
                
                wait(cpu_active_flag[b] == 1'b1); 
                @(posedge clk); // Entra em CDC_WAIT1
                @(posedge clk); // Entra em CDC_WAIT2
                @(posedge clk); // Entra em CMD_GEN
                @(negedge clk);
            end
            else begin
                // HIT: CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN
                @(posedge clk); // Entra em CDC_WAIT2
                @(posedge clk); // Entra em CMD_GEN
                @(negedge clk);
            end

            // Checagem final centralizada no estado CMD_GEN
            if (rnw) check_cmd(4'b0101, "READ Command");
            else     check_cmd(4'b0100, "WRITE Command");

            @(posedge clk);
            cpu_req = 1'b0;
            wait(cpu_ready == 1'b1); // Aguarda o fim de WAIT_CCD3 e retorno ao IDLE
        end
    endtask

    // -------------------------------------------------------------------------
    // SEQUÊNCIA DE TESTE (100 TRANSAÇÕES AUTOMATIZADAS)
    // -------------------------------------------------------------------------
    initial begin
        $display("===============================================================");
        $display(" INICIANDO VALIDACAO DO SCHEDULER / FRONT-END (100 TESTES)");
        $display("===============================================================");

        rst_n = 0; cpu_req = 0; cpu_rnw = 0; init_done = 0;
        cpu_address = 0;
        cpu_idle_flag = 8'hFF;   
        cpu_active_flag = 8'h00; 
        
        // Zera o array de monitoramento
        for (i = 0; i < 8; i = i + 1) tb_open_row[i] = 14'd0;

        #20 rst_n = 1;

        @(posedge clk);
        if (cpu_ready !== 1'b0) begin 
            $display("[ERRO] cpu_ready vazou antes do init_done."); 
            errors = errors + 1;
        end

        init_done = 1;
        wait(cpu_ready == 1'b1);
        $display("[OK] Memoria inicializada. FSM em IDLE.");
        $display("---------------------------------------------------------------");
        
        // Loop gerador de 100 transações
        for (i = 0; i < 10000; i = i + 1) begin
            rand_bank = $random % 8;
            rand_row  = $random % 16384; // 14 bits (0 a 16383)
            rand_col  = $random % 1024;  // 10 bits
            rand_rnw  = $random % 2;

            // Lógica de inferência: Descobre o que a Interface DEVE fazer
            if (cpu_idle_flag[rand_bank] == 1'b1) begin
                calc_type = 1; // Empty (Página fechada)
                tb_open_row[rand_bank] = rand_row;
            end 
            else if (tb_open_row[rand_bank] == rand_row) begin
                calc_type = 0; // Hit (A mesma página já está aberta)
            end 
            else begin
                calc_type = 2; // Miss (Outra página está aberta no banco)
                tb_open_row[rand_bank] = rand_row;
            end

            cpu_transaction(rand_row, rand_bank, rand_col, rand_rnw, calc_type);
            
            // Log a cada 25 transações para não poluir demais a tela
            if ((i + 1) % 25 == 0) begin
                $display("[OK] %0d transações processadas...", i + 1);
            end
        end

        $display("===============================================================");
        if (errors == 0) $display(" SIMULACAO CONCLUIDA COM SUCESSO! 0 ERROS EM 100 TESTES.");
        else             $display(" SIMULACAO FALHOU COM %0d ERRO(S).", errors);
        $display("===============================================================");
        $finish;
    end
endmodule
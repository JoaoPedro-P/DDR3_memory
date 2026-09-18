// [PT] Módulo: tb_interface_control_unit / [EN] Module: tb_interface_control_unit
// [PT] Testbench da Unidade de Controle da Interface, que atua como o escalonador / front-end da memória. / [EN] Testbench for the Interface Control Unit, acting as the memory scheduler / front-end.
// [PT] Inputs/Outputs: Recebe transações da CPU e emite comandos (CS, RAS, CAS, WE) para a memória. / [EN] Inputs/Outputs: Receives transactions from CPU and issues commands (CS, RAS, CAS, WE) to memory.
// [PT] Papel: Verifica a correta emissão de comandos JEDEC baseado no estado (hit, miss, empty) dos bancos. / [EN] Role: Verifies the correct issuance of JEDEC commands based on the bank states (hit, miss, empty).
`timescale 1ns / 1ps

module tb_interface_control_unit();

    // -------------------------------------------------------------------------
    // [PT] Sinais de Interface / [EN] Interface Signals
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
    // [PT] Rastreador Interno do Testbench para calcular Hit/Miss/Empty / [EN] Testbench Internal Tracker to calculate Hit/Miss/Empty
    // -------------------------------------------------------------------------
    reg [13:0] tb_open_row [0:7];
    reg [1:0]  calc_type;
    reg [2:0]  rand_bank;
    reg [13:0] rand_row;
    reg [9:0]  rand_col;
    reg        rand_rnw;

    // -------------------------------------------------------------------------
    // [PT] Instanciação do DUT / [EN] DUT Instantiation
    // -------------------------------------------------------------------------
    interface_control_unit dut (
        .clk(clk), .rst_n(rst_n), .cpu_req(cpu_req), .cpu_rnw(cpu_rnw), .init_done(init_done),
        .cpu_address(cpu_address),
        .cpu_active_flag(cpu_active_flag), .cpu_idle_flag(cpu_idle_flag),
        .row_addr(row_addr), .col_addr(col_addr), .bank_addr(bank_addr),
        .cpu_ready(cpu_ready), .CS(CS), .RAS(RAS), .WE(WE), .CAS(CAS)
    );

    // -------------------------------------------------------------------------
    // [PT] Geração de Clock / [EN] Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // [PT] "MOCK" DO DATAPATH FÍSICO / [EN] PHYSICAL DATAPATH "MOCK"
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        // [PT] ACTIVATE detectado / [EN] ACTIVATE detected
        if ({CS, RAS, CAS, WE} == 4'b0011) begin 
            cpu_idle_flag[bank_addr]   <= 1'b0;
            cpu_active_flag[bank_addr] <= 1'b1; 
        end
        // [PT] PRECHARGE detectado / [EN] PRECHARGE detected
        else if ({CS, RAS, CAS, WE} == 4'b0010) begin 
            cpu_idle_flag[bank_addr]   <= 1'b1;
            cpu_active_flag[bank_addr] <= 1'b0;
        end
    end

    // [PT] Função para formatar o endereço / [EN] Function to format the address
    function [26:0] get_addr(input [13:0] r, input [2:0] b, input [9:0] c);
        get_addr = {r, b, c};
    endfunction

    // [PT] Tarefa para checar o comando de saída / [EN] Task to check output command
    task check_cmd(input [3:0] expected_cmd, input [8*25:1] msg);
        begin
            if ({CS, RAS, CAS, WE} !== expected_cmd) begin
                $display("[ERRO] %0s. Esperado: %b, Obtido: %b no tempo %0t", msg, expected_cmd, {CS, RAS, CAS, WE}, $time);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // [PT] DRIVER: Emulador do Processador (Ajustado para os delays CDC_WAIT1/2) / [EN] DRIVER: Processor Emulator (Adjusted for CDC_WAIT1/2 delays)
    // -------------------------------------------------------------------------
    task cpu_transaction(input [13:0] r, input [2:0] b, input [9:0] c, input rnw, input [1:0] expected_type);
        begin
            @(posedge clk);
            cpu_address = get_addr(r, b, c);
            cpu_rnw = rnw;
            cpu_req = 1'b1;

            // [PT] FSM saiu do estado IDLE / [EN] FSM left IDLE state
            wait(cpu_ready == 1'b0); 

            if (expected_type == 1) begin
                // [PT] EMPTY: ACT_CMD -> ACT_WAIT -> CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN / [EN] EMPTY: ACT_CMD -> ACT_WAIT -> CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN
                @(negedge clk);
                check_cmd(4'b0011, "ACTIVATE Cmd (Empty)");
                
                wait(cpu_active_flag[b] == 1'b1); 
                // [PT] Entra em CDC_WAIT1 / [EN] Enters CDC_WAIT1
                @(posedge clk); 
                // [PT] Entra em CDC_WAIT2 / [EN] Enters CDC_WAIT2
                @(posedge clk); 
                // [PT] Entra em CMD_GEN / [EN] Enters CMD_GEN
                @(posedge clk); 
                // [PT] Borda de descida para checar os pinos no meio do ciclo / [EN] Falling edge to check pins mid-cycle
                @(negedge clk); 
            end
            else if (expected_type == 2) begin
                // [PT] MISS: PRE_CMD -> PRE_WAIT -> ACT_CMD -> ACT_WAIT -> CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN / [EN] MISS: PRE_CMD -> PRE_WAIT -> ACT_CMD -> ACT_WAIT -> CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN
                @(negedge clk);
                check_cmd(4'b0010, "PRECHARGE Cmd (Miss)");
                
                wait(cpu_idle_flag[b] == 1'b1);   
                // [PT] Entra em ACT_CMD / [EN] Enters ACT_CMD
                @(posedge clk); 
                @(negedge clk);
                check_cmd(4'b0011, "ACTIVATE Cmd (Miss)");
                
                wait(cpu_active_flag[b] == 1'b1); 
                // [PT] Entra em CDC_WAIT1 / [EN] Enters CDC_WAIT1
                @(posedge clk); 
                // [PT] Entra em CDC_WAIT2 / [EN] Enters CDC_WAIT2
                @(posedge clk); 
                // [PT] Entra em CMD_GEN / [EN] Enters CMD_GEN
                @(posedge clk); 
                @(negedge clk);
            end
            else begin
                // [PT] HIT: CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN / [EN] HIT: CDC_WAIT1 -> CDC_WAIT2 -> CMD_GEN
                // [PT] Entra em CDC_WAIT2 / [EN] Enters CDC_WAIT2
                @(posedge clk); 
                // [PT] Entra em CMD_GEN / [EN] Enters CMD_GEN
                @(posedge clk); 
                @(negedge clk);
            end

            // [PT] Checagem final centralizada no estado CMD_GEN / [EN] Final check centralized in CMD_GEN state
            if (rnw) check_cmd(4'b0101, "READ Command");
            else     check_cmd(4'b0100, "WRITE Command");

            @(posedge clk);
            cpu_req = 1'b0;
            // [PT] Aguarda o fim de WAIT_CCD3 e retorno ao IDLE / [EN] Wait for WAIT_CCD3 end and return to IDLE
            wait(cpu_ready == 1'b1); 
        end
    endtask

    // -------------------------------------------------------------------------
    // [PT] SEQUÊNCIA DE TESTE (100 TRANSAÇÕES AUTOMATIZADAS) / [EN] TEST SEQUENCE (100 AUTOMATED TRANSACTIONS)
    // -------------------------------------------------------------------------
    initial begin
        $display("===============================================================");
        $display(" INICIANDO VALIDACAO DO SCHEDULER / FRONT-END (100 TESTES)");
        $display("===============================================================");

        rst_n = 0; cpu_req = 0; cpu_rnw = 0; init_done = 0;
        cpu_address = 0;
        cpu_idle_flag = 8'hFF;   
        cpu_active_flag = 8'h00; 
        
        // [PT] Zera o array de monitoramento / [EN] Clear the monitoring array
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
        
        // [PT] Loop gerador de 10000 transações / [EN] Generator loop for 10000 transactions
        for (i = 0; i < 10000; i = i + 1) begin
            rand_bank = $random % 8;
            // [PT] 14 bits (0 a 16383) / [EN] 14 bits (0 to 16383)
            rand_row  = $random % 16384; 
            // [PT] 10 bits / [EN] 10 bits
            rand_col  = $random % 1024;  
            rand_rnw  = $random % 2;

            // [PT] Lógica de inferência: Descobre o que a Interface DEVE fazer / [EN] Inference logic: Discovers what the Interface MUST do
            if (cpu_idle_flag[rand_bank] == 1'b1) begin
                // [PT] Empty (Página fechada) / [EN] Empty (Closed page)
                calc_type = 1; 
                tb_open_row[rand_bank] = rand_row;
            end 
            else if (tb_open_row[rand_bank] == rand_row) begin
                // [PT] Hit (A mesma página já está aberta) / [EN] Hit (The same page is already open)
                calc_type = 0; 
            end 
            else begin
                // [PT] Miss (Outra página está aberta no banco) / [EN] Miss (Another page is open in the bank)
                calc_type = 2; 
                tb_open_row[rand_bank] = rand_row;
            end

            cpu_transaction(rand_row, rand_bank, rand_col, rand_rnw, calc_type);
            
            // [PT] Log a cada 25 transações para não poluir demais a tela / [EN] Log every 25 transactions to avoid cluttering the screen
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
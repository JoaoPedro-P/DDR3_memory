/*
 * module: dram_bank_control
 * -----------------
 * PT: Controlador de Estado dos Bancos DRAM. 
 *     Este módulo é responsável por monitorar o estado individual de cada um dos 8 
 *     bancos da memória e garantir que as restrições de tempo JEDEC sejam respeitadas.
 *     Ele atua como um "vigilante" de protocolo, detectando tentativas de acesso 
 *     ilegais (ex: ler de um banco fechado) e gerenciando os timers tRCD e tRP.
 * 
 *     Estados do Banco:
 *     - IDLE: Banco fechado. Precisa de ACT para abrir.
 *     - ACTIVATING: Transição de abertura. Timer tRCD em progresso.
 *     - ACTIVE: Banco aberto (Página aberta). Pronto para comandos RD/WR.
 *     - PRECHARGING: Transição de fechamento. Timer tRP em progresso.
 *
 * EN: DRAM Bank State Controller.
 *     This module is responsible for monitoring the individual state of each of 
 *     the 8 memory banks and ensuring that JEDEC timing constraints are met.
 *     It acts as a protocol "watchdog", detecting illegal access attempts 
 *     (e.g., reading from a closed bank) and managing tRCD and tRP timers.
 * 
 *     Bank States:
 *     - IDLE: Bank closed. Needs ACT to open.
 *     - ACTIVATING: Opening transition. tRCD timer in progress.
 *     - ACTIVE: Bank open (Open Page). Ready for RD/WR commands.
 *     - PRECHARGING: Closing transition. tRP timer in progress.
 */
module dram_bank_control #(
    parameter freq = 100,            
    parameter T_RCD_CYCLES = 5,      
    parameter T_RP_CYCLES  = 5       
)(
    input  wire       clk,           
    input  wire       rst_n,         
    input  wire       act_cmd,       
    input  wire       pre_cmd,       
    input  wire       rd_cmd,        
    input  wire       wr_cmd,        
    input  wire [2:0] bank_addr,     
    output reg  [7:0] bank_active,   
    output reg        timing_error   
);

    // [PT] Definição de estados e vetor de estado por banco / [EN] State definitions and state vector per bank
    reg [1:0] state [0:7];
    parameter IDLE = 2'd0, ACTIVATING = 2'd1, ACTIVE = 2'd2, PRECHARGING = 2'd3;

    integer i;
    
    // [PT] CORREÇÃO: Sinais de start agora são combinacionais / [EN] CORRECTION: Start signals are now combinational
    reg [7:0] start_tRCD_timer;
    reg [7:0] start_tRP_timer;
    
    wire [$clog2(freq) + 1 : 0] tRCD_timer [0:7];
    wire [$clog2(freq) + 1 : 0] tRP_timer [0:7]; 
    
    localparam [$clog2(freq) + 1 : 0] TRCD_VAL = T_RCD_CYCLES;
    localparam [$clog2(freq) + 1 : 0] TRP_VAL  = T_RP_CYCLES;
    
    // [PT] Lógica combinacional de avaliação de erros e timers / [EN] Combinational logic for error evaluation and timers
    always @ (*) begin
        timing_error = 1'b0;
        
        // [PT] Loop sobre todos os bancos / [EN] Loop over all banks
        for(i = 0; i < 8; i = i + 1) begin : out_loop
            bank_active[i]      = 1'b0;
            start_tRCD_timer[i] = 1'b0;
            start_tRP_timer[i]  = 1'b0;
            
            if (bank_addr == i) begin
                case (state[i])
                    IDLE: begin
                        if (rd_cmd || wr_cmd || pre_cmd) timing_error = 1'b1;
                        if (act_cmd) start_tRCD_timer[i] = 1'b1;
                    end
                    ACTIVATING: begin
                        start_tRCD_timer[i] = 1'b1;
                        if (rd_cmd || wr_cmd || act_cmd || pre_cmd) timing_error = 1'b1;
                    end
                    ACTIVE: begin
                        bank_active[i] = 1'b1;
                        if (act_cmd) timing_error = 1'b1;
                        if (pre_cmd) start_tRP_timer[i] = 1'b1;
                    end
                    PRECHARGING: begin
                        start_tRP_timer[i] = 1'b1;
                        if (rd_cmd || wr_cmd || act_cmd || pre_cmd) timing_error = 1'b1;
                    end
                endcase
            end else begin
                // [PT] Mantém os estados e timers rodando para bancos não selecionados / [EN] Keeps states and timers running for unselected banks
                if (state[i] == ACTIVE) bank_active[i] = 1'b1;
                if (state[i] == ACTIVATING) start_tRCD_timer[i] = 1'b1;
                if (state[i] == PRECHARGING) start_tRP_timer[i] = 1'b1;
            end
        end
    end

    // [PT] Atualização de estado sequencial (Máquina de Estados Finita) / [EN] Sequential state update (Finite State Machine)
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // [PT] Reseta todos os estados para IDLE / [EN] Resets all states to IDLE
            for(i = 0; i < 8; i = i + 1) begin
                state[i] <= IDLE;
            end
        end else begin
            // [PT] Avalia transições de estado por banco / [EN] Evaluates state transitions per bank
            for(i = 0; i < 8; i = i + 1) begin
                case (state[i])
                    IDLE: begin
                        if (act_cmd && (bank_addr == i)) state[i] <= ACTIVATING;
                    end
                    ACTIVATING: begin
                        if (tRCD_timer[i] == 0) state[i] <= ACTIVE;
                    end
                    ACTIVE: begin
                        if (pre_cmd && (bank_addr == i)) state[i] <= PRECHARGING;
                    end
                    PRECHARGING: begin
                        if (tRP_timer[i] == 0) state[i] <= IDLE;
                    end
                endcase
            end
        end
    end

    genvar g;
    generate
        // [PT] Instanciação dos contadores de timing para cada banco / [EN] Instantiation of timing counters for each bank
        for(g = 0; g < 8; g = g + 1) begin : for_counters
            temp_param #(.freq(freq)) tRCD_counter (
                .clk       (clk), 
                .rst_n     (rst_n), 
                .num_cicles(TRCD_VAL), 
                .start     (start_tRCD_timer[g]), 
                .out       (tRCD_timer[g])
            );

            temp_param #(.freq(freq)) tRP_counter (
                .clk       (clk), 
                .rst_n     (rst_n), 
                .num_cicles(TRP_VAL), 
                .start     (start_tRP_timer[g]), 
                .out       (tRP_timer[g])
            );
        end
    endgenerate

endmodule

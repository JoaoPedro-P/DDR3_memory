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
    parameter freq = 100,            // PT: Freq. de clock. | EN: Clock freq.
    parameter T_RCD_CYCLES = 5,      // PT: Ciclos para tRCD (ACT -> RD/WR). | EN: Cycles for tRCD.
    parameter T_RP_CYCLES  = 5       // PT: Ciclos para tRP (PRE -> IDLE). | EN: Cycles for tRP.
)(
    // =========================================================================
    // Sinais de Controle | Control Signals
    // =========================================================================
    input  wire       clk,           // PT: Clock principal. | EN: Main clock.
    input  wire       rst_n,         // PT: Reset (Ativo Baixo). | EN: Reset (Active Low).
    input  wire       act_cmd,       // PT: Comando ACTIVATE detectado. | EN: ACTIVATE command.
    input  wire       pre_cmd,       // PT: Comando PRECHARGE detectado. | EN: PRECHARGE command.
    input  wire       rd_cmd,        // PT: Comando READ detectado. | EN: READ command.
    input  wire       wr_cmd,        // PT: Comando WRITE detectado. | EN: WRITE command.
    input  wire [2:0] bank_addr,     // PT: Banco alvo do comando. | EN: Target bank.
    
    // =========================================================================
    // Status de Saída | Output Status
    // =========================================================================
    output reg  [7:0] bank_active,   // PT: Bitmask de bancos abertos (1=Aberto). | EN: Active bank bitmask.
    output reg        timing_error   // PT: Flag de erro de timing/protocolo. | EN: Timing error flag.
);


    // PT: 8 máquinas de estado (uma por banco) | EN: 8 state machines (one per bank)
    reg [1:0] state [0:7];
    parameter IDLE = 2'd0, ACTIVATING = 2'd1, ACTIVE = 2'd2, PRECHARGING = 2'd3;

    integer i;
    
    reg [7:0] start_tRCD_timer;
    reg [7:0] start_tRP_timer;
    
    wire [$clog2(freq) + 1 : 0] tRCD_timer [0:7];
    wire [$clog2(freq) + 1 : 0] tRP_timer [0:7]; 
	 
	 localparam [$clog2(freq) + 1 : 0] TRCD_VAL = T_RCD_CYCLES;
    localparam [$clog2(freq) + 1 : 0] TRP_VAL  = T_RP_CYCLES;
    
    // =========================================================================
    // PT: 1. Lógica Combinacional: Flags e Erros | EN: 1. Combinational Logic
    // =========================================================================
    always @ (*) begin
        timing_error = 1'b0;
        
        for(i = 0; i < 8; i = i + 1) begin : out_loop
            bank_active[i] = 1'b0;
            
            // PT: Avalia erros de timing se o comando for para este banco
            // EN: Evaluate timing errors if command targets this bank
            if (bank_addr == i) begin
                case (state[i])
                    IDLE: begin
                        if (rd_cmd || wr_cmd || pre_cmd)
                            timing_error = 1'b1;
                    end
                    ACTIVATING: begin
                        if (rd_cmd || wr_cmd || act_cmd || pre_cmd)
                            timing_error = 1'b1;
                    end
                    ACTIVE: begin
                        bank_active[i] = 1'b1;
                        if (act_cmd)
                            timing_error = 1'b1;
                    end
                    PRECHARGING: begin
                        if (rd_cmd || wr_cmd || act_cmd || pre_cmd)
                            timing_error = 1'b1;
                    end
                endcase
            end else begin
                if (state[i] == ACTIVE)
                    bank_active[i] = 1'b1;
            end
        end
    end

    // =========================================================================
    // PT: 2. Máquina de Estados Sequencial | EN: 2. Sequential State Machine
    // =========================================================================
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i = 0; i < 8; i = i + 1) begin : loop_reset
                state[i]            <= IDLE;
                start_tRCD_timer[i] <= 1'b0;
                start_tRP_timer[i]  <= 1'b0;
            end
        end else begin
            for(i = 0; i < 8; i = i + 1) begin : loop_states
                
                start_tRCD_timer[i] <= 1'b0;
                start_tRP_timer[i]  <= 1'b0;

                case (state[i])
                    IDLE: begin
                        if (act_cmd && (bank_addr == i)) begin
                            state[i]            <= ACTIVATING;
                        end
                    end
                    
                    ACTIVATING: begin
								start_tRCD_timer[i] <= 1'b1;
                        if (tRCD_timer[i] == 0)
                            state[i] <= ACTIVE;
                    end
                    
                    ACTIVE: begin
                        if (pre_cmd && (bank_addr == i)) begin
                            state[i]           <= PRECHARGING;
                        end
                    end
                    
                    PRECHARGING: begin
								start_tRP_timer[i] <= 1'b1;
                        if (tRP_timer[i] == 0)
                            state[i] <= IDLE;
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // PT: 3. Temporizadores Estruturais | EN: 3. Structural Timers
    // =========================================================================
    genvar g;
    generate
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

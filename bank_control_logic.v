/*
 * module: dram_bank_control
 * -----------------
 * PT: Controlador de Bancos da DRAM. 
 *     Gerencia as máquinas de estado individuais para cada banco e detecta violações de timing.
 * 
 * EN: DRAM Bank Control.
 *     Manages individual state machines for each bank and detects timing violations.
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

    // PT: 8 máquinas de estado (uma por banco) | EN: 8 state machines (one per bank)
    reg [1:0] state [0:7];
    parameter IDLE = 2'd0, ACTIVATING = 2'd1, ACTIVE = 2'd2, PRECHARGING = 2'd3;

    integer i;
    
    reg [7:0] start_tRCD_timer;
    reg [7:0] start_tRP_timer;
    
    wire [$clog2(freq) + 1 : 0] tRCD_timer [0:7];
    wire [$clog2(freq) + 1 : 0] tRP_timer [0:7]; 
    
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
                .num_cicles(T_RCD_CYCLES), 
                .start     (start_tRCD_timer[g]), 
                .out       (tRCD_timer[g])
            );

            temp_param #(.freq(freq)) tRP_counter (
                .clk       (clk), 
                .rst_n     (rst_n), 
                .num_cicles(T_RP_CYCLES), 
                .start     (start_tRP_timer[g]), 
                .out       (tRP_timer[g])
            );
        end
    endgenerate

endmodule

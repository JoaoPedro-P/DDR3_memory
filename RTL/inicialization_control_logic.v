/*
 * module: inicialization_control_logic
 * -----------------
 * [PT] Lógica de Controle de Inicialização. 
 *      Implementa a sequência JEDEC obrigatória para ligar a memória DDR3.
 *      Inclui RESET, espera de estabilização, configuração de registradores de modo (MRS) e Calibração ZQ.
 * 
 * [EN] Initialization Control Logic.
 *      Implements the mandatory JEDEC sequence to power up DDR3 memory.
 *      Includes RESET, stabilization waits, Mode Register Set (MRS) configuration, and ZQ Calibration.
 */
module inicialization_control_logic #(parameter freq = 100) (
    input  wire CK, 
    input  wire rst_n, 
    output reg  RESET_n,   // [PT] Reset físico do chip / [EN] Physical chip reset
    output reg  CKE,       // [PT] Clock Enable do chip / [EN] Chip Clock Enable
    output reg  init_done, // [PT] Flag de inicialização OK / [EN] Initialization OK flag
    
    // [PT] Pinos de controle assumidos pela FSM / [EN] Control pins driven by the FSM
    output reg  CS_n, RAS_n, CAS_n, WE_n,
    output reg  [2:0]  BA,
    output reg  [12:0] A
);

    // -------------------------------------------------------------------------
    // [PT] Parâmetros de Temporização (Ciclos) / [EN] Timing Parameters (Cycles)
    // -------------------------------------------------------------------------
    localparam calc_tXPR = (120 * freq) / 1000;
    localparam calc_tMOD = (15 * freq)  / 1000;
    localparam tMRD      = 4;
    localparam tZQinit   = 512;
    
    localparam init_stab   = 200 * freq; // [PT] Espera 200us / [EN] Wait 200us
    localparam reset_CKE_n = 500 * freq; // [PT] Espera 500us / [EN] Wait 500us
    localparam tXPR        = (calc_tXPR > 5) ? calc_tXPR : 5;
    localparam tMOD        = (calc_tMOD > 12) ? calc_tMOD : 12;
    
    // [PT] Registrador de Estado / [EN] State Register
    reg [3:0] state;
    
    // [PT] Definição dos Estados / [EN] State Definitions
    parameter [3:0]
        RESET_WAIT = 0, CKE_LOW_WAIT = 1, CKE_HIGH_WAIT = 2, 
        ISSUE_MR2 = 3, WAIT_MRD2 = 4, ISSUE_MR3 = 5, WAIT_MRD3 = 6,
        ISSUE_MR1 = 7, WAIT_MRD1 = 8, ISSUE_MR0 = 9, WAIT_MOD = 10, 
        ISSUE_ZQCL = 11, WAIT_ZQCL = 12, INIT_DONE = 13;

    // [PT] Contador Global / [EN] Global Timer
    reg [15:0] timer;
    
    // -------------------------------------------------------------------------
    // [PT] Bloco 1: Lógica de Saída (Combinacional) / [EN] Block 1: Output Logic (Combinational)
    // -------------------------------------------------------------------------
    always @ (state) begin
        // [PT] Valores padrão para evitar latches / [EN] Default values to avoid latches
        RESET_n   = 1'b1;
        CKE       = 1'b1;
        init_done = 1'b0;
        CS_n  = 1'b0; RAS_n = 1'b1; CAS_n = 1'b1; WE_n = 1'b1; // [PT] NOP / [EN] NOP
        BA    = 3'b000;
        A     = 13'b0;

        case (state)
            RESET_WAIT: begin
                RESET_n = 1'b0;
                CKE     = 1'b0;
            end
            
            CKE_LOW_WAIT: begin
                RESET_n = 1'b1;
                CKE     = 1'b0;
            end
            
            ISSUE_MR2: begin
                CS_n = 1'b0; RAS_n = 1'b0; CAS_n = 1'b0; WE_n = 1'b0; // [PT] MRS / [EN] MRS
                BA = 3'd2;
            end
            
            ISSUE_MR3: begin
                CS_n = 1'b0; RAS_n = 1'b0; CAS_n = 1'b0; WE_n = 1'b0; // [PT] MRS / [EN] MRS
                BA = 3'd3;
            end
            
            ISSUE_MR1: begin
                CS_n = 1'b0; RAS_n = 1'b0; CAS_n = 1'b0; WE_n = 1'b0; // [PT] MRS / [EN] MRS
                BA = 3'd1;
                A  = 13'h0000; // [PT] DLL Ativo / [EN] DLL Enabled
            end
            
            ISSUE_MR0: begin
                CS_n = 1'b0; RAS_n = 1'b0; CAS_n = 1'b0; WE_n = 1'b0; // [PT] MRS / [EN] MRS
                BA = 3'd0;
                A  = 13'h0100; // [PT] Reset DLL / [EN] DLL Reset
            end
            
            ISSUE_ZQCL: begin
                CS_n = 1'b0; RAS_n = 1'b1; CAS_n = 1'b1; WE_n = 1'b0; // [PT] ZQCL / [EN] ZQCL
                A[10] = 1'b1;  // [PT] Calibração Longa / [EN] Long Calibration
            end
            
            INIT_DONE: begin
                init_done = 1'b1;
				CS_n = 1'b1; RAS_n = 1'b1; CAS_n = 1'b1; WE_n = 1'b1; 
                BA = 3'b000; A = 13'b0;
            end
				default: begin
				  RESET_n   = 1'b1;
				  CKE       = 1'b1;
				  init_done = 1'b0;
				  CS_n  = 1'b0; RAS_n = 1'b1; CAS_n = 1'b1; WE_n = 1'b1; // [PT] NOP / [EN] NOP
				  BA    = 3'b000;
				  A     = 13'b0;
				end
        endcase
    end

    // -------------------------------------------------------------------------
    // [PT] Bloco 2: Transição de Estados / [EN] Block 2: State Transitions
    // -------------------------------------------------------------------------
    always @ (posedge CK or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET_WAIT;
            timer <= 16'd0;
        end else begin
            case (state)
                RESET_WAIT:
                    if(timer < init_stab - 1) begin
                        state <= RESET_WAIT;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= CKE_LOW_WAIT;
                        timer <= 16'd0;
                    end
                    
                CKE_LOW_WAIT:
                    if(timer < reset_CKE_n - 1) begin
                        state <= CKE_LOW_WAIT;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= CKE_HIGH_WAIT;
                        timer <= 16'd0;
                    end
                    
                CKE_HIGH_WAIT:
                    if(timer < tXPR - 1) begin
                        state <= CKE_HIGH_WAIT;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= ISSUE_MR2;
                        timer <= 16'd0;
                    end
                    
                ISSUE_MR2: begin
                    state <= WAIT_MRD2;
                    timer <= 16'd0;
                end
                    
                WAIT_MRD2:
                    if(timer < tMRD - 1) begin
                        state <= WAIT_MRD2;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= ISSUE_MR3;
                        timer <= 16'd0;
                    end

                ISSUE_MR3: begin
                    state <= WAIT_MRD3;
                    timer <= 16'd0;
                end
                    
                WAIT_MRD3:
                    if(timer < tMRD - 1) begin
                        state <= WAIT_MRD3;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= ISSUE_MR1;
                        timer <= 16'd0;
                    end
                    
                ISSUE_MR1: begin
                    state <= WAIT_MRD1;
                    timer <= 16'd0;
                end
                    
                WAIT_MRD1:
                    if(timer < tMRD - 1) begin
                        state <= WAIT_MRD1;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= ISSUE_MR0;
                        timer <= 16'd0;
                    end
                    
                ISSUE_MR0: begin
                    state <= WAIT_MOD;
                    timer <= 16'd0;
                end
                    
                WAIT_MOD:
                    if(timer < tMOD - 1) begin
                        state <= WAIT_MOD;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= ISSUE_ZQCL;
                        timer <= 16'd0;
                    end
                    
                ISSUE_ZQCL: begin
                    state <= WAIT_ZQCL;
                    timer <= 16'd0;
                end
                    
                WAIT_ZQCL:
                    if(timer < tZQinit - 1) begin
                        state <= WAIT_ZQCL;
                        timer <= timer + 16'd1;
                    end else begin
                        state <= INIT_DONE;
                        timer <= 16'd0;
                    end
              
                INIT_DONE: begin
                    state <= INIT_DONE;
                    timer <= 16'd0;
                end
                
                default: begin
                    state <= RESET_WAIT;
                    timer <= 16'd0;
                end
            endcase
        end
    end
    
endmodule

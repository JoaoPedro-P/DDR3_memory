// [PT] Módulo: datapath_control_logic - Lógica de Controle do Datapath (Agendador de Backend). Este módulo é o cérebro JEDEC do controlador. Ele gerencia as máquinas de estado individuais para cada um dos 8 bancos da memória DDR3, garantindo que os comandos enviados à DRAM respeitem rigorosamente os tempos de protocolo (tRCD, tRP, tRFC). Principais Funções: 1. Decodificação JEDEC. 2. Máquinas de Estado de Banco. 3. Gerenciamento de Burst. 4. Refresh Automático. 5. Registradores de Modo (MR). / [EN] Module: datapath_control_logic - Datapath Control Logic (Backend Scheduler). This module is the JEDEC brain of the controller. It manages individual state machines for each of the 8 DDR3 memory banks, ensuring that commands sent to the DRAM strictly respect protocol timings (tRCD, tRP, tRFC). Key Functions: 1. JEDEC Decoding. 2. Bank State Machines. 3. Burst Management. 4. Automatic Refresh. 5. Mode Registers (MR).
module datapath_control_logic #(parameter freq = 100) (
    // [PT] Sinais de Clock e Controle / [EN] Clock and Control Signals
    input  wire        CK,           // [PT] Clock da memória (0°). / [EN] Memory clock (0°).
    input  wire        CKE,          // [PT] Clock Enable da DRAM. / [EN] DRAM Clock Enable.
    input  wire        RESET_n,      // [PT] Reset (Ativo Baixo). / [EN] Reset (Active Low).
    input  wire        CS_n,         // [PT] Chip Select (Ativo Baixo). / [EN] Chip Select (Active Low).
    input  wire        A12,          // [PT] Endereço A12 (Burst Chop select). / [EN] Address A12 (BC select).
    input  wire        A10,          // [PT] Endereço A10 (Auto-Precharge select). / [EN] Address A10 (AP select).
    input  wire        RAS_n,        // [PT] Row Address Strobe (Ativo Baixo). / [EN] Row Address Strobe (Active Low).
    input  wire        CAS_n,        // [PT] Column Address Strobe (Ativo Baixo). / [EN] Column Address Strobe (Active Low).
    input  wire        WE_n,         // [PT] Write Enable (Ativo Baixo). / [EN] Write Enable (Active Low).
    input  wire        refresh_req,  // [PT] Solicitação de Refresh pendente. / [EN] Pending Refresh request.
    input  wire [12:0] A,            // [PT] Barramento de endereço JEDEC. / [EN] JEDEC address bus.
    input  wire [2:0]  BA,           // [PT] Barramento de endereço de banco. / [EN] Bank address bus.
	input  wire        frontend_idle_safe, // [PT] Indica que o frontend está ocioso p/ Refresh. / [EN] Indicates frontend is idle for Refresh.
    
    // [PT] Sinais de Habilitação (PHY/Data) / [EN] Enable Signals (PHY/Data)
    output reg         enable_read_fifo,      // [PT] Habilita leitura da FIFO de retorno. / [EN] Enable read FIFO.
    output reg         enable_write_drivers,  // [PT] Habilita drivers de escrita DQ. / [EN] Enable write drivers.
    output reg         enable_row_decoder,    // [PT] Habilita decodificador de linha. / [EN] Enable row decoder.
    
    // [PT] Controle de Refresh / [EN] Refresh Control
    output reg         refresh_ack,           // [PT] Confirma execução do Refresh. / [EN] Ack Refresh execution.
    output reg         refresh_mem_flag,      // [PT] Indica que a memória está em ciclo de Refresh. / [EN] Refresh in progress.
    output reg         inject_refresh,        // [PT] Pulso para injetar comando REF físico. / [EN] Pulse to inject physical REF.
    
    // [PT] Flags de Status / [EN] Status Flags
    output reg  [7:0]  BC4_flag,              // [PT] Flag de Burst Chop (4 palavras) por banco. / [EN] BC4 flag per bank.
    output reg  [7:0]  AP_flag,               // [PT] Flag de Auto-Precharge por banco. / [EN] AP flag per bank.
    output reg  [7:0]  bank_active_flag,      // [PT] Banco está com linha ativa. / [EN] Bank is active.
    output reg  [7:0]  bank_idle_flag,        // [PT] Banco está em IDLE (fechado). / [EN] Bank is idle.
    
    // [PT] Registradores de Modo / [EN] Mode Registers
    output reg  [12:0] MR0, MR1, MR2, MR3     // [PT] Conteúdo dos registradores de configuração. / [EN] MR contents.
);

	localparam [$clog2(freq) + 9'd1 : 0] T_RC_VAL = (freq / 9'd67) + 9'd1;
	localparam tRFC_ns = 110; 
    localparam tRFC_cycles = (tRFC_ns * freq) / 1000;
	 
    // [PT] Definição dos Estados / [EN] State Definitions
    parameter [2:0]
        IDLE        = 3'b000, 
        ACTIVATING  = 3'b001, 
        BANK_ACTIVE = 3'b010, 
        READING     = 3'b011, 
        WRITING     = 3'b100, 
        PRECHARGING = 3'b101,
        REFRESH     = 3'b110;

    // [PT] Arrays para gerenciar os 8 bancos independentemente / [EN] Arrays to manage the 8 banks independently
    reg [2:0] state [0:7];
    reg [2:0] next_state [0:7];
    reg [1:0] burst_timer [0:7];
    reg [7:0] load_timer;
	reg [7:0] start_tRCD_timer, start_tRP_timer;
    
    // [PT] Temporizador para o ciclo de Refresh (tRFC) / [EN] Timer for Refresh cycle (tRFC)
    reg [31:0] refresh_timer; 

    wire [$clog2(freq) + 1 : 0] tRCD_timer [0:7];
    wire [$clog2(freq) + 1 : 0] tRP_timer [0:7]; 

    // [PT] Decodificação de Comandos JEDEC / [EN] JEDEC Command Decoding
    wire cmd_act   = (!CS_n && !RAS_n &&  CAS_n &&  WE_n);
    wire cmd_read  = (!CS_n &&  RAS_n && !CAS_n &&  WE_n);
    wire cmd_write = (!CS_n &&  RAS_n && !CAS_n && !WE_n);
    wire cmd_pre   = (!CS_n && !RAS_n &&  CAS_n && !WE_n);
    wire cmd_mrs   = (!CS_n && !RAS_n && !CAS_n && !WE_n);

    integer i;
    wire all_banks_idle = &bank_idle_flag;

    // 1. [PT] Bloco Always: Atualização dos Registradores de Modo / [EN] Always Block: Mode Register Update
    always @(posedge CK or negedge RESET_n) begin
        if (!RESET_n) begin
            MR0 <= 13'd0; MR1 <= 13'd0; MR2 <= 13'd0; MR3 <= 13'd0;
        end else if (CKE && cmd_mrs) begin
            case (BA)
                3'b000: MR0 <= A; 3'b001: MR1 <= A;
                3'b010: MR2 <= A; 3'b011: MR3 <= A;
            endcase
        end
    end
    
    // 2. [PT] Bloco Always: Lógica do Temporizador de Refresh / [EN] Always Block: Refresh Timer Logic
    always @(posedge CK or negedge RESET_n) begin
        if (!RESET_n) begin
            refresh_timer <= 4'd0;
        end else if (refresh_mem_flag) begin
            refresh_timer <= refresh_timer + 4'd1;
        end else begin
            refresh_timer <= 4'd0;
        end
    end

    // 3. [PT] Bloco Always: Atualização de Estados e Burst Timers / [EN] Always Block: State and Burst Timer Update
    always @(posedge CK or negedge RESET_n) begin
        if (!RESET_n) begin
            // [PT] Loop inicial: reseta arrays de status de bancos / [EN] Initial loop: resets bank status arrays
            for(i = 0; i < 8; i = i + 1) begin
                state[i]       <= IDLE;
                burst_timer[i] <= 3'd0;
                AP_flag[i]     <= 1'b0;
                BC4_flag[i]    <= 1'b0;
            end
        end else if (CKE) begin
            // [PT] Loop por 8 bancos para atualização dos burst timers / [EN] Loop through 8 banks for burst timers update
            for(i = 0; i < 8; i = i + 1) begin
                state[i] <= next_state[i];
                if (load_timer[i]) burst_timer[i] <= 2'd3;
                else if (burst_timer[i] > 0) burst_timer[i] <= burst_timer[i] - 2'd1;
            end
            if (cmd_read || cmd_write) begin
                AP_flag[BA]  <= A10;  // [PT] Auto-Precharge / [EN] Auto-Precharge
                BC4_flag[BA] <= ~A12; // [PT] Burst Chop 4 / [EN] Burst Chop 4
            end
        end
    end

    // 4. [PT] Bloco Always: Lógica de Próximo Estado (Coração do Controlador) / [EN] Always Block: Next State Logic (Controller Core)
    always @(*) begin
        enable_read_fifo     = 1'b0;
        enable_write_drivers = 1'b0;
        enable_row_decoder   = 1'b0;
        refresh_mem_flag     = 1'b0;
        refresh_ack          = 1'b0;
        inject_refresh       = 1'b0;

        // [PT] Lógica Global de Refresh / [EN] Global Refresh Logic
        if (state[0] == REFRESH) begin
            refresh_mem_flag = 1'b1;
            if (refresh_timer == 0) inject_refresh = 1'b1; 
            if (refresh_timer >= tRFC_cycles) refresh_ack = 1'b1;
        end

        // [PT] Loop para avaliar o próximo estado de cada banco / [EN] Loop to evaluate the next state of each bank
        for(i = 0; i < 8; i = i + 1) begin
            next_state[i]       = state[i];
            load_timer[i]       = 1'b0;
            start_tRCD_timer[i] = 1'b0;
            start_tRP_timer[i]  = 1'b0;
            bank_active_flag[i] = 1'b0;
            bank_idle_flag[i]   = 1'b0;
            
            // [PT] Força fechamento de bancos para Refresh / [EN] Force bank closure for Refresh
            if (refresh_req && state[i] == BANK_ACTIVE && frontend_idle_safe)
                next_state[i] = PRECHARGING;

            case (state[i])
                IDLE: begin
                    bank_idle_flag[i] = 1'b1;
                    if (cmd_act && (BA == i)) begin 
                        enable_row_decoder  = 1'b1;
                        start_tRCD_timer[i] = 1'b1;
                        next_state[i]       = ACTIVATING;
                    end
                    else if (refresh_req && all_banks_idle && frontend_idle_safe) begin
                        next_state[i] = REFRESH;
                    end
                end

                ACTIVATING: begin
                    enable_row_decoder  = 1'b1;
                    start_tRCD_timer[i] = 1'b1;
                    if(tRCD_timer[i] == 0) next_state[i] = BANK_ACTIVE;
                end

                BANK_ACTIVE: begin
                    bank_active_flag[i] = 1'b1;
                    if (cmd_read && (BA == i)) begin
                        load_timer[i] = 1'b1; next_state[i] = READING;
                    end else if (cmd_write && (BA == i)) begin
                        load_timer[i] = 1'b1; next_state[i] = WRITING;
                    end else if (cmd_pre && (BA == i || A10)) begin
                        next_state[i] = PRECHARGING;
                    end
                end

                READING: begin
                    enable_read_fifo = 1'b1; bank_active_flag[i] = 1'b1;
                    if (cmd_read && (BA == i)) begin
                        load_timer[i] = 1'b1; next_state[i] = READING;
                    end else if (burst_timer[i] == 3'd0) begin
                        if (AP_flag[i]) next_state[i] = PRECHARGING;
                        else next_state[i] = BANK_ACTIVE;
                    end
                end

                WRITING: begin
                    enable_write_drivers = 1'b1; bank_active_flag[i] = 1'b1;
                    if (cmd_write && (BA == i)) begin
                        load_timer[i] = 1'b1; next_state[i] = WRITING;
                    end else if (burst_timer[i] == 3'd0) begin
                        if (AP_flag[i]) next_state[i] = PRECHARGING;
                        else next_state[i] = BANK_ACTIVE;
                    end
                end

                PRECHARGING: begin
                    start_tRP_timer[i] = 1'b1;
                    if(tRP_timer[i] == 0) begin
                        next_state[i] = IDLE;
                    end
                end
                
                REFRESH: begin
                    if (refresh_timer >= tRFC_cycles) 
						next_state[i] = IDLE;
                end
                
                default: next_state[i] = IDLE;
            endcase
        end
    end

    // [PT] Geração: Temporizadores Parametrizados por banco / [EN] Generate: Parameterized Timers per bank
    genvar g;
    generate
        for(g = 0; g < 8; g = g + 1) begin : for_counters
            temp_param #(.freq(freq)) tRCD_counter (
                .clk       (CK), 
                .rst_n     (RESET_n), 
                .num_cicles(T_RC_VAL), 
                .start     (start_tRCD_timer[g]), 
                .out       (tRCD_timer[g])
            );

            temp_param #(.freq(freq)) tRP_counter (
                .clk       (CK), 
                .rst_n     (RESET_n), 
                .num_cicles(T_RC_VAL), 
                .start     (start_tRP_timer[g]), 
                .out       (tRP_timer[g])
            );
        end
    endgenerate
endmodule

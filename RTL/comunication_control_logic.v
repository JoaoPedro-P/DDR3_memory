// [PT] Módulo: comunication_control_logic - Lógica de controle de comunicação. Esta FSM gera os comandos JEDEC (ACT, PRE, RD/WR) com base no estado da página. Entradas: Sinais da CPU e de controle de página. Saídas: Sinais JEDEC para RAM. / [EN] Module: comunication_control_logic - Communication control logic. This FSM generates JEDEC commands (ACT, PRE, RD/WR) based on the page status. Inputs: CPU and page control signals. Outputs: JEDEC signals for RAM.
module comunication_control_logic(
    input  wire clk, rst_n, init_done, cpu_req, cpu_rnw,
    input  wire page_hit, page_empty, page_miss,
    input  wire [7:0] cpu_idle_flag, cpu_active_flag,
    input  wire [2:0] cpu_bank_addr,
    output reg  cpu_ready, update_row_en, CS, RAS, CAS, WE,
	output reg  cmd_ack
);

    reg [3:0] state;
    
    parameter 
        BOOT_WAIT = 4'd0, 
        IDLE      = 4'd1, 
        CMD_GEN   = 4'd2, 
        ACT_CMD   = 4'd3, 
        PRE_CMD   = 4'd4, 
        PRE_WAIT  = 4'd5, 
        ACT_WAIT  = 4'd6,
        WAIT_CCD1 = 4'd7,
        WAIT_CCD2 = 4'd8,
        WAIT_CCD3 = 4'd9,
        CDC_WAIT1 = 4'd10,
        CDC_WAIT2 = 4'd11; 

    // [PT] Bloco Always: Lógica Combinacional de Saída / [EN] Always Block: Combinational Output Logic
    always @ (*) begin
        cpu_ready     = 1'b0;
        update_row_en = 1'b0;
        CS            = 1'b0;
        RAS           = 1'b0;
        CAS           = 1'b0;
        WE            = 1'b0;
        cmd_ack       = 1'b0; 

        case (state)
            BOOT_WAIT, PRE_WAIT, ACT_WAIT, WAIT_CCD1, WAIT_CCD2, CDC_WAIT1, CDC_WAIT2: begin
                {RAS, CAS, WE} = 3'b111; // [PT] Comando NOP / [EN] NOP Command
            end
            
            WAIT_CCD3: begin
                {RAS, CAS, WE} = 3'b111;
                cmd_ack = 1'b1; // [PT] Sinal de Pop da FIFO / [EN] FIFO Pop signal
            end
            
            IDLE: begin
                {RAS, CAS, WE} = 3'b111; 
                // [PT] Pronto apenas se a página estiver em estado conhecido / [EN] Ready only if page is in a known state
                if (page_hit || page_empty || page_miss)
                    cpu_ready = 1'b1;
                else
                    cpu_ready = 1'b0;
            end
            
            PRE_CMD: begin
                CAS = 1'b1; // [PT] Comando PRECHARGE / [EN] PRECHARGE Command
            end
            ACT_CMD: begin
                {CAS, WE}     = 2'b11; // [PT] Comando ACTIVATE / [EN] ACTIVATE Command
                update_row_en = 1'b1;
            end
            CMD_GEN: begin
                if(cpu_rnw) {RAS, WE} = 2'b11; // [PT] Comando READ / [EN] READ Command
                else        RAS = 1'b1;        // [PT] Comando WRITE / [EN] WRITE Command
            end
            default: {RAS, CAS, WE} = 3'b111;
        endcase
    end

    // [PT] Bloco Always: Transição de Estados da FSM / [EN] Always Block: FSM State Transitions
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= BOOT_WAIT;
        end else begin
            case (state)
                BOOT_WAIT: if(init_done) state <= IDLE; else state <= BOOT_WAIT;
                
                IDLE:
                    if (cpu_req && cpu_ready) begin 
                        if(page_hit)       state <= CDC_WAIT1;
                        else if(page_empty)state <= ACT_CMD;
                        else if(page_miss) state <= PRE_CMD;
                        else               state <= IDLE;
                    end else state <= IDLE; 
                    
                CDC_WAIT1: state <= CDC_WAIT2;
                CDC_WAIT2: state <= CMD_GEN;
                    
                PRE_CMD:  state <= PRE_WAIT;
                PRE_WAIT: if (cpu_idle_flag[cpu_bank_addr]) state <= ACT_CMD; else state <= PRE_WAIT;
                
                ACT_CMD:  state <= ACT_WAIT;
                ACT_WAIT: if (cpu_active_flag[cpu_bank_addr]) state <= CDC_WAIT1; else state <= ACT_WAIT;
                    
                CMD_GEN:   state <= WAIT_CCD1;
                WAIT_CCD1: state <= WAIT_CCD2;
                WAIT_CCD2: state <= WAIT_CCD3;
                WAIT_CCD3: state <= IDLE;
                    
                default: state <= BOOT_WAIT;
            endcase
        end
    end
endmodule

/*
 * module: axi_lite_fsm
 * -----------------
 * PT: Máquina de estados (FSM) que implementa o protocolo AXI-Lite para o controlador DDR3.
 *     
 *     Diferente de uma FSM AXI-Lite comum, esta possui estados expandidos para lidar com a 
 *     arquitetura de prefetch da DDR3. Como o core da memória opera internamente com 
 *     blocos de 64 bits (8 bytes), mas a interface AXI-Lite é de 16 bits, a FSM realiza 
 *     automaticamente rajadas de 4 palavras para preencher ou ler o bloco de 64 bits.
 *
 *     Operação:
 *     - Escrita: Ao receber AWVALID e WVALID, a FSM entra em uma sequência (WRITE_W1..W4).
 *       Ela injeta o dado de 16 bits quatro vezes no buffer de escrita da memória para 
 *       garantir que o bloco de 64 bits seja preenchido, e então dispara o comando de escrita.
 *     - Leitura: Ao receber ARVALID, a FSM solicita uma leitura (READ_MEM). Ela aguarda 
 *       o burst de 4 palavras da memória (READ_R1..R4), captura apenas a primeira palavra 
 *       desejada (latch_r) e descarta as demais, retornando o dado ao mestre AXI.
 *
 * EN: State machine (FSM) that implements the AXI-Lite protocol for the DDR3 controller.
 *     
 *     Unlike a standard AXI-Lite FSM, this one has expanded states to handle the 
 *     DDR3 prefetch architecture. Since the memory core operates internally with 
 *     64-bit blocks (8 bytes), but the AXI-Lite interface is 16-bit, the FSM 
 *     automatically performs 4-word bursts to fill or read the 64-bit block.
 *
 *     Operation:
 *     - Write: Upon receiving AWVALID and WVALID, the FSM enters a sequence (WRITE_W1..W4).
 *       It injects the 16-bit data four times into the memory write buffer to ensure 
 *       the 64-bit block is filled, then triggers the write command.
 *     - Read: Upon receiving ARVALID, the FSM requests a read (READ_MEM). It waits 
 *       for the memory's 4-word burst (READ_R1..R4), captures only the first word 
 *       desired (latch_r), discards the others, and returns the data to the AXI master.
 */
module axi_lite_fsm(
    // =========================================================================
    // Clocks e Resets | Clocks and Resets
    // =========================================================================
    input      ACLK,       // PT: Clock do AXI. | EN: AXI Clock.
    input      ARESETn,    // PT: Reset (Ativo Baixo). | EN: Reset (Active Low).

    // =========================================================================
    // Interface AXI-Lite (Controle) | AXI-Lite Interface (Control)
    // =========================================================================
    input      AWVALID,    // PT: Endereço de escrita válido. | EN: Write address valid.
    input      WVALID,     // PT: Dado de escrita válido. | EN: Write data valid.
    input      BREADY,     // PT: Mestre pronto p/ resp. escrita. | EN: Master ready for write resp.
    input      ARVALID,    // PT: Endereço de leitura válido. | EN: Read address valid.
    input      RREADY,     // PT: Mestre pronto p/ resp. leitura. | EN: Master ready for read resp.

    output reg AWREADY,    // PT: Pronto p/ receber end. escrita. | EN: Ready for write address.
    output reg WREADY,     // PT: Pronto p/ receber dado escrita. | EN: Ready for write data.
    output reg BVALID,     // PT: Resposta de escrita válida. | EN: Write response valid.
    output reg ARREADY,    // PT: Pronto p/ receber end. leitura. | EN: Ready for read address.
    output reg RVALID,     // PT: Resposta de leitura válida. | EN: Read response valid.

    // =========================================================================
    // Interface com a Memória (ddr_mem) | Memory Interface (ddr_mem)
    // =========================================================================
    input      cpu_ready,  // PT: Memória pronta p/ novos comandos. | EN: Memory ready for new cmds.
    input      rx_valid,   // PT: Dado vindo da memória é válido. | EN: Data from memory is valid.
    input      tx_full,    // PT: Buffer de transmissão cheio. | EN: TX buffer is full.
    input      init_done,  // PT: Calibração JEDEC concluída. | EN: JEDEC calibration done.

    output reg cpu_req,    // PT: Solicita comando à memória. | EN: Request command to memory.
    output reg cpu_rnw,    // PT: 1=Read, 0=Write. | EN: 1=Read, 0=Write.
    output reg cpu_wr_en,  // PT: Habilita escrita no buffer. | EN: Enable write to buffer.

    // =========================================================================
    // Sinais p/ Datapath Interno | Signals for Internal Datapath
    // =========================================================================
    output reg latch_aw,   // PT: Salva o endereço de escrita AXI. | EN: Latch AXI write address.
    output reg latch_w,    // PT: Salva o dado de escrita AXI. | EN: Latch AXI write data.
    output reg latch_ar,   // PT: Salva o endereço de leitura AXI. | EN: Latch AXI read address.
    output reg latch_r,    // PT: Salva o dado lido da memória. | EN: Latch data read from memory.
    output reg sel_read    // PT: Seleciona endereço AR (1) ou AW (0). | EN: Select AR (1) or AW (0) addr.
);


    reg [3:0] state;

    // Estados expandidos para preencher e esvaziar os Bursts de 4 palavras (64-bits)
    parameter IDLE = 4'd0, 
              READ_MEM = 4'd1, 
              READ_R1 = 4'd2, 
              READ_R2 = 4'd3, 
              READ_R3 = 4'd4, 
              READ_R4 = 4'd5, 
              READ_RESP = 4'd6, 
              WRITE_W1 = 4'd7, 
              WRITE_W2 = 4'd8, 
              WRITE_W3 = 4'd9, 
              WRITE_W4 = 4'd10, 
              WRITE_RESP = 4'd11;

    always @ (*) begin
        AWREADY   = 1'b0;
        WREADY    = 1'b0;
        BVALID    = 1'b0;
        ARREADY   = 1'b0;
        RVALID    = 1'b0;
        cpu_req   = 1'b0;
        cpu_rnw   = 1'b0;
        cpu_wr_en = 1'b0;
        latch_ar  = 1'b0;
        latch_aw  = 1'b0;
        latch_w   = 1'b0;
        latch_r   = 1'b0;
        sel_read  = 1'b0;

        case (state)
            IDLE: begin
                if(init_done) begin
                    if(ARVALID)
                        latch_ar = 1'b1;
                    else if(!ARVALID && AWVALID && WVALID) begin
                        latch_aw = 1'b1;
                        latch_w  = 1'b1;
                    end
                end
            end
            
READ_MEM: begin
                sel_read = 1'b1;
                if(cpu_ready) begin
                    cpu_req  = 1'b1;
                    cpu_rnw  = 1'b1;
                    ARREADY  = 1'b1;
                end
            end
            READ_R1: begin 
                if (rx_valid) latch_r = 1'b1; // Captura APENAS a 1ª palavra do Burst
            end
            READ_R2: begin end                // Ignora
            READ_R3: begin end                // REMOVA O LATCH DAQUI. Ignora
            READ_R4: begin end                // Ignora
            READ_RESP: RVALID = 1'b1;         // Responde ao AXI com o dado blindado
            
            WRITE_W1: if (!tx_full) cpu_wr_en = 1'b1; // Injeta cópia 1
            WRITE_W2: if (!tx_full) cpu_wr_en = 1'b1; // Injeta cópia 2
            WRITE_W3: if (!tx_full) cpu_wr_en = 1'b1; // Injeta cópia 3
            WRITE_W4: begin
                if(cpu_ready && !tx_full) begin 
                    cpu_req   = 1'b1;                 // Dispara o comando!
                    cpu_wr_en = 1'b1;                 // Injeta cópia 4
                    AWREADY   = 1'b1;
                    WREADY    = 1'b1;
                end
            end 
            WRITE_RESP: BVALID = 1'b1;
            default: begin end
        endcase
    end

    always @ (posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            state <= IDLE;
        else
            case (state)
                IDLE: begin
                    if(init_done) begin
                        if(ARVALID) state <= READ_MEM;
                        else if(!ARVALID && AWVALID && WVALID) state <= WRITE_W1;
                    end
                end
                
                READ_MEM:  if (cpu_ready) state <= READ_R1;
                READ_R1:   if (rx_valid)  state <= READ_R2;
                READ_R2:   if (rx_valid)  state <= READ_R3;
                READ_R3:   if (rx_valid)  state <= READ_R4;
                READ_R4:   if (rx_valid)  state <= READ_RESP;
                READ_RESP: if (RREADY)    state <= IDLE;
                
                WRITE_W1:   if (!tx_full) state <= WRITE_W2;
                WRITE_W2:   if (!tx_full) state <= WRITE_W3;
                WRITE_W3:   if (!tx_full) state <= WRITE_W4;
                WRITE_W4:   if (cpu_ready && !tx_full) state <= WRITE_RESP;
                WRITE_RESP: if (BREADY)   state <= IDLE;
                
                default: state <= IDLE;
            endcase
    end
endmodule
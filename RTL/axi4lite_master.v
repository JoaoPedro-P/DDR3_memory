// =========================================================================
// [PT] Módulo AXI4-Lite Master / [EN] AXI4-Lite Master Module
// [PT] Implementa o mestre do barramento AXI4-Lite para operações de leitura e escrita. / [EN] Implements the AXI4-Lite bus master for read and write operations.
// =========================================================================
module axi4lite_master #(parameter ADDR_WIDTH = 27, parameter DATA_WIDTH = 32)(
    input ACLK,
    input ARESETn,

    // [PT] Entradas do Master a partir da CPU / [EN] Master input from CPU
    input STARTW,
    input STARTR,
    input [ADDR_WIDTH-1:0] m_addr,
    input [DATA_WIDTH-1:0] m_wdata,
    input [3:0] m_wstrb,
    input [2:0] m_awprot, 
    input [2:0] m_arprot, 
    
    output reg [DATA_WIDTH-1:0] m_rdata,
    output reg m_wdone,
    output reg m_rdone,
    output reg [1:0] m_wresp,
    output reg [1:0] m_rresp,

    // [PT] Endereço de Escrita (AW) / [EN] Write Address (AW)
    input AWREADY,
    output reg AWVALID,
    output reg [ADDR_WIDTH-1:0] AWADDR,
    output reg [2:0] AWPROT,

    // [PT] Dados de Escrita (W) / [EN] Write Data (W)
    input WREADY,
    output reg WVALID,
    output reg [DATA_WIDTH-1:0] WDATA,
    output reg [3:0] WSTRB,

    // [PT] Resposta de Escrita (B) / [EN] Write Response (B)
    input BVALID,
    input [1:0] BRESP,
    output reg BREADY,

    // [PT] Endereço de Leitura (AR) / [EN] Read Address (AR)
    input ARREADY,
    output reg ARVALID,
    output reg [ADDR_WIDTH-1:0] ARADDR,
    output reg [2:0] ARPROT,

    // [PT] Dados de Leitura (R) / [EN] Read Data (R)
    input RVALID,
    input [DATA_WIDTH-1:0] RDATA,
    input [1:0] RRESP,
    output reg RREADY
);

    // =========================================================================
    // [PT] FSM DE ESCRITA (WRITE PROCESS) - MESCLADO (MEALY + EARLY READY) / [EN] WRITE FSM (WRITE PROCESS) - MERGED (MEALY + EARLY READY)
    // =========================================================================
    localparam WIDLE = 2'b00, WSEND = 2'b01, WRESP = 2'b10;
    
    reg [1:0] state_write, next_state_write;
    reg aw_done_reg, w_done_reg;
    
    reg [ADDR_WIDTH-1:0] latched_awaddr;
    reg [DATA_WIDTH-1:0] latched_wdata;
    reg [3:0]            latched_wstrb;
    reg [2:0]            latched_awprot;

    // [PT] Lógica combinacional da FSM de Escrita / [EN] Combinational logic for Write FSM
    always @(*) begin
        AWVALID = 1'b0;
        WVALID  = 1'b0;
        BREADY  = 1'b0; 
        AWADDR  = latched_awaddr;
        WDATA   = latched_wdata;
        WSTRB   = latched_wstrb;
        AWPROT  = latched_awprot;

        case (state_write)
            WIDLE: begin
                if (STARTW) begin
                    AWVALID = 1'b1;
                    WVALID  = 1'b1;
                    BREADY  = 1'b1; // [PT] <-- OTIMIZAÇÃO: Early BREADY / [EN] <-- OPTIMIZATION: Early BREADY
                    AWADDR  = m_addr;
                    WDATA   = m_wdata;
                    WSTRB   = m_wstrb;
                    AWPROT  = m_awprot;
                end
            end
            WSEND: begin
                AWVALID = !aw_done_reg;
                WVALID  = !w_done_reg;
                BREADY  = 1'b1; // [PT] <-- OTIMIZAÇÃO: Mantém Early BREADY alto / [EN] <-- OPTIMIZATION: Keep Early BREADY high
            end
            WRESP: begin
                BREADY = 1'b1;
            end
        endcase
    end

    // [PT] Lógica de próximo estado da FSM de Escrita / [EN] Next state logic for Write FSM
    always @(*) begin
        next_state_write = state_write;
        case (state_write)
            WIDLE: if (STARTW) next_state_write = (AWREADY && WREADY) ? WRESP : WSEND;
            WSEND: if ((aw_done_reg || (AWVALID && AWREADY)) && (w_done_reg || (WVALID && WREADY))) next_state_write = WRESP;
            WRESP: if (BVALID) next_state_write = WIDLE;
        endcase
    end

    // [PT] Lógica sequencial da FSM de Escrita / [EN] Sequential logic for Write FSM
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state_write    <= WIDLE;
            aw_done_reg    <= 1'b0;
            w_done_reg     <= 1'b0;
            latched_awaddr <= 0;
            latched_wdata  <= 0;
            latched_wstrb  <= 0;
            latched_awprot <= 0;
            m_wdone        <= 1'b0;
            m_wresp        <= 2'b00;
        end else begin
            state_write <= next_state_write;
            m_wdone     <= 1'b0;

            case (state_write)
                WIDLE: begin
                    if (STARTW) begin
                        latched_awaddr <= m_addr;
                        latched_wdata  <= m_wdata;
                        latched_wstrb  <= m_wstrb;
                        latched_awprot <= m_awprot;
                        aw_done_reg    <= AWREADY; 
                        w_done_reg     <= WREADY;
                    end
                end
                WSEND: begin
                    if (AWVALID && AWREADY) aw_done_reg <= 1'b1;
                    if (WVALID && WREADY)   w_done_reg  <= 1'b1;
                end
                WRESP: begin
                    if (BVALID && BREADY) begin
                        m_wresp     <= BRESP;
                        m_wdone     <= 1'b1;
                        aw_done_reg <= 1'b0;
                        w_done_reg  <= 1'b0;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // [PT] FSM DE LEITURA (READ PROCESS) - MESCLADO (MEALY + EARLY READY) / [EN] READ FSM (READ PROCESS) - MERGED (MEALY + EARLY READY)
    // =========================================================================
    localparam RIDLE = 2'b00, RADDR = 2'b01, RRECEIVE = 2'b10;
    
    reg [1:0] state_read, next_state_read;
    reg [ADDR_WIDTH-1:0] latched_araddr;
    reg [2:0]            latched_arprot;

    // [PT] Lógica combinacional da FSM de Leitura / [EN] Combinational logic for Read FSM
    always @(*) begin
        ARVALID = 1'b0;
        RREADY  = 1'b0;
        ARADDR  = latched_araddr;
        ARPROT  = latched_arprot;

        case (state_read)
            RIDLE: begin
                if (STARTR) begin
                    ARVALID = 1'b1;
                    RREADY  = 1'b1; // [PT] <-- OTIMIZAÇÃO: Early RREADY / [EN] <-- OPTIMIZATION: Early RREADY
                    ARADDR  = m_addr;
                    ARPROT  = m_arprot;
                end
            end
            RADDR: begin
                ARVALID = 1'b1;
                RREADY  = 1'b1; // [PT] <-- OTIMIZAÇÃO: Mantém Early RREADY alto / [EN] <-- OPTIMIZATION: Keep Early RREADY high
            end
            RRECEIVE: begin
                RREADY = 1'b1;
            end
        endcase
    end

    // [PT] Lógica de próximo estado da FSM de Leitura / [EN] Next state logic for Read FSM
    always @(*) begin
        next_state_read = state_read;
        case (state_read)
            RIDLE: if (STARTR) next_state_read = (ARREADY) ? RRECEIVE : RADDR;
            RADDR: if (ARREADY) next_state_read = RRECEIVE;
            RRECEIVE: if (RVALID) next_state_read = RIDLE;
        endcase
    end

    // [PT] Lógica sequencial da FSM de Leitura / [EN] Sequential logic for Read FSM
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state_read     <= RIDLE;
            latched_araddr <= 0;
            latched_arprot <= 0;
            m_rdone        <= 1'b0;
            m_rdata        <= 0;
            m_rresp        <= 0;
        end else begin
            state_read <= next_state_read;
            m_rdone    <= 1'b0;

            case (state_read)
                RIDLE: begin
                    if (STARTR) begin
                        latched_araddr <= m_addr;
                        latched_arprot <= m_arprot;
                    end
                end
                RRECEIVE: begin
                    if (RVALID && RREADY) begin
                        m_rdata <= RDATA;
                        m_rresp <= RRESP;
                        m_rdone <= 1'b1;
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule
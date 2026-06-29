module axi4lite_master #(parameter ADDR_WIDTH = 27, parameter DATA_WIDTH = 16)(
    input ACLK,
    input ARESETn,

    // Master input from CPU
    input STARTW, // start a write transaction (from CPU)
    input STARTR, // start a read transaction (from CPU)
    input [ADDR_WIDTH-1:0] m_addr, // address for read/write from CPU
    input [DATA_WIDTH-1:0] m_wdata, // write data from CPU
    input [1:0] m_wstrb, //strobe from CPU
    
    output reg [DATA_WIDTH-1:0] m_rdata, //DADO LIDO
    output reg m_wdone, // write done
    output reg m_rdone, // read done
    output reg [1:0] m_wresp, // write response - send by the slave
    output reg [1:0] m_rresp, // read response - send by the slave

    // Write Address (AW)
    input AWREADY,
    output reg AWVALID,
    output reg [ADDR_WIDTH-1:0] AWADDR,
    output reg [2:0] AWPROT,

    // Write Data (W)
    input WREADY,
    output reg WVALID,
    output reg [DATA_WIDTH-1:0] WDATA,
    output reg [1:0] WSTRB,

    // Write Response (B)
    input BVALID,
    input [1:0] BRESP,
    output reg BREADY,

    // Read Address (AR)
    input ARREADY,
    output reg ARVALID,
    output reg [ADDR_WIDTH-1:0] ARADDR,
    output reg [2:0] ARPROT,

    // Read Data (R)
    input RVALID,
    input [DATA_WIDTH-1:0] RDATA,
    input [1:0] RRESP,
    output reg RREADY
);

    // =========================================================================
    // FSM - Write Process (Totalmente Síncrona)
    // =========================================================================
    localparam WIDLE = 2'b00, WSEND = 2'b01, WRESP = 2'b10;
    reg [1:0] state_write;
    reg aw_done_reg, w_done_reg;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state_write <= WIDLE;
            AWVALID     <= 1'b0;
            WVALID      <= 1'b0;
            BREADY      <= 1'b0;
            m_wdone     <= 1'b0;
            aw_done_reg <= 1'b0;
            w_done_reg  <= 1'b0;
            AWADDR      <= 0;
            WDATA       <= 0;
            WSTRB       <= 0;
            //AWPROT      <= 3'b000;
        end else begin
            // Pulso padrão: m_wdone só fica alto por 1 ciclo
            m_wdone <= 1'b0;

            case (state_write)
                WIDLE: begin
                    aw_done_reg <= 1'b0;
                    w_done_reg  <= 1'b0;
                    
                    if (STARTW) begin
                        state_write <= WSEND;
                        AWVALID     <= 1'b1;
                        WVALID      <= 1'b1;
                        AWADDR      <= m_addr;
                        WDATA       <= m_wdata;
                        WSTRB       <= m_wstrb;
                    end
                end

                WSEND: begin
                    // Gerencia os canais de forma independente
                    if (AWVALID && AWREADY) begin
                        AWVALID     <= 1'b0; // Abaixa o Valid assim que aceito
                        aw_done_reg <= 1'b1;
                    end
                    if (WVALID && WREADY) begin
                        WVALID      <= 1'b0; // Abaixa o Valid assim que aceito
                        w_done_reg  <= 1'b1;
                    end
                    
                    // Só avança quando ambos os canais finalizarem o handshake
                    if ((aw_done_reg || (AWVALID && AWREADY)) && 
                        (w_done_reg  || (WVALID && WREADY))) begin
                        state_write <= WRESP;
                        BREADY      <= 1'b1;
                    end
                end

                WRESP: begin
                    if (BVALID && BREADY) begin
                        BREADY      <= 1'b0;
                        m_wresp     <= BRESP;
                        m_wdone     <= 1'b1; // Sinaliza Testbench
                        state_write <= WIDLE;
                    end
                end
                default: state_write <= WIDLE;
            endcase
        end
    end

    // =========================================================================
    // FSM - Read Process (Totalmente Síncrona)
    // =========================================================================
    localparam RIDLE = 2'b00, RADDR = 2'b01, RRECEIVE = 2'b10;
    reg [1:0] state_read;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state_read <= RIDLE;
            ARVALID    <= 1'b0;
            RREADY     <= 1'b0;
            m_rdone    <= 1'b0;
            m_rdata    <= 0;
            ARADDR     <= 0;
            //ARPROT     <= 3'b000;
        end else begin
            // Pulso padrão
            m_rdone <= 1'b0;

            case (state_read)
                RIDLE: begin
                    if (STARTR) begin
                        state_read <= RADDR;
                        ARVALID    <= 1'b1;
                        ARADDR     <= m_addr;
                    end
                end

                RADDR: begin
                    if (ARVALID && ARREADY) begin
                        ARVALID    <= 1'b0;
                        RREADY     <= 1'b1;
                        state_read <= RRECEIVE;
                    end
                end

                RRECEIVE: begin
                    if (RVALID && RREADY) begin
                        RREADY     <= 1'b0;
                        m_rdata    <= RDATA;
                        m_rresp    <= RRESP;
                        m_rdone    <= 1'b1; // Sinaliza Testbench
                        state_read <= RIDLE;
                    end
                end
                default: state_read <= RIDLE;
            endcase
        end
    end

endmodule
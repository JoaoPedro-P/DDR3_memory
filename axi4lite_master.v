//Módulo Master AXI4-LITE

/* 

Write Address (AW)
Write Data (W)
Write Response (B)
Read Address (AR)
Read Data (R)

Write Process:
IDLE → SEND ADDR/DATA → WAIT FOR RESPONSE

Read Process:
IDLE → SEND ADDR → WAIT FOR DATA

*/

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

    // FSM - Write Process

    // idle -> send addr -> resp

    reg [1:0] state_write;

    localparam WIDLE = 2'b00,
               WSEND = 2'b01,
               WRESP = 2'b10;

    //output logic - write process FSM
	 reg aw_done, w_done;
    always @(*) begin	

		// defaults
		     AWVALID = 1'b0; // write address
           WVALID  = 1'b0; // write data
           BREADY  = 1'b0; // write response
           AWADDR  = {ADDR_WIDTH{1'b0}};
           AWPROT  = 3'b000;
           WDATA   = {DATA_WIDTH{1'b0}};
           WSTRB   = {(DATA_WIDTH/8){1'b0}};
           m_wdone = 1'b0;
           m_wresp = 2'b00; 
				
        case(state_write)
	
            WIDLE: begin
				

            end

            WSEND: begin
				
                //address signals
                AWADDR  = m_addr;
                AWVALID = 1'b1;

                //data signals
                WDATA   = m_wdata;
                WSTRB   = m_wstrb;
                WVALID  = 1'b1;
					 
					 if (AWVALID && AWREADY) begin 
							aw_done = 1'b1;
						  end else aw_done = 1'b0;
					 if(WVALID && WREADY) begin 
						w_done = 1'b1;
					 end else w_done = 1'b0;
					 
            end

            WRESP: begin
                BREADY = 1'b1;

                if (BVALID) begin
                    m_wresp = BRESP;
                    m_wdone = 1'b1;
                end
            end

            default: begin
                AWVALID = 1'b0; // write address
                WVALID  = 1'b0; // write data
                BREADY  = 1'b0; // write response
                AWADDR  = {ADDR_WIDTH{1'b0}};
                AWPROT  = 3'b000;
                WDATA   = {DATA_WIDTH{1'b0}};
                WSTRB   = {(DATA_WIDTH/8){1'b0}};
                m_wdone = 1'b0;
                m_wresp = 2'b00;
            end

        endcase

    end

    // Next-state logic

    always @(posedge ACLK or negedge ARESETn) begin

        if (!ARESETn) begin
            state_write <= WIDLE;
        end
        else begin
            case (state_write)

                WIDLE: begin

                    if (STARTW) begin
                        state_write <= WSEND;
                    end

                end

                WSEND: begin
						  
                    if (aw_done && w_done) begin
                        state_write <= WRESP;
                    end

                end

                WRESP: begin
					 if(BVALID && BREADY) begin
                    state_write <= WIDLE;
					end
                end

                default: begin
                    state_write <= WIDLE;
                end

            endcase
        end

    end

    // FSM - Read Process
	 // IDLE → SEND ADDR → WAIT FOR DATA
	  
	 reg [2:0] state_read;

    localparam RIDLE = 3'b00,
               RADDR = 3'b01,
               RRECEIVE = 3'b10;
	 
	  //output logic - read process FSM
    always @(*) begin
	 
	  // defaults
		ARVALID = 1'b0;  
		ARADDR  = {ADDR_WIDTH{1'b0}};
		ARPROT  = 3'b000;
		RREADY = 1'b0;
		
		m_rdone = 1'b0;
	   m_rresp = 2'b00;

        case(state_read)

            RIDLE: begin

            end

            RADDR: begin
                //address signals
                ARADDR  = m_addr;
                ARVALID = 1'b1;

            end

            RRECEIVE: begin
                RREADY = 1'b1;

                if (RVALID) begin
						  m_rdata = RDATA;
                    m_rresp = RRESP;
                    m_rdone = 1'b1;
                end
            end

            default: begin
               ARVALID = 1'b0;  
					ARADDR  = {ADDR_WIDTH{1'b0}};
					ARPROT  = 3'b000;
					RREADY = 1'b0;
		
					m_rdata = {DATA_WIDTH{1'b0}};
					m_rdone = 1'b0;
					m_rresp = 2'b00;
            end

        endcase

    end
	 
	  // Next-state logic
	  
    always @(posedge ACLK or negedge ARESETn) begin

        if (!ARESETn) begin
            state_read <= RIDLE;
        end
        else begin
            case (state_read)

                RIDLE: begin

                    if (STARTR) begin
                        state_read <= RADDR;
                    end

                end

                RADDR: begin

                    if (ARVALID && ARREADY) begin
                        state_read <= RRECEIVE;
                    end

                end

                RRECEIVE: begin
						if(RVALID && RREADY) begin
                    state_read <= RIDLE;
						 end
                end

                default: begin
                    state_read <= RIDLE;
                end

            endcase
        end

    end


endmodule
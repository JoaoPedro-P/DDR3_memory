//  este módulo é responsável por conectar a interface axi4lite_master ao slave DDR3 memory

module axi4lite_system #(parameter ADDR_WIDTH = 27, parameter DATA_WIDTH = 16)(

	input clk_axi_bus, 
	input clk_mem, 
	input clk_90_mem, 
	input resetn_bus, 
	input reset_mem,
	
	input STARTW, // start a write transaction (from CPU)
   input STARTR, // start a read transaction (from CPU)
   input [ADDR_WIDTH-1:0] m_addr, // address for read/write from CPU
   input [DATA_WIDTH-1:0] m_wdata, // write data from CPU
   input [1:0] m_wstrb, //strobe from CPU
   output [DATA_WIDTH-1:0] m_rdata, //DADO LIDO
   output m_wdone, // write done
   output m_rdone, // read done
   output [1:0] m_wresp, // write response - send by the slave
   output [1:0] m_rresp // read response - send by the slave
);

// Write Address (AW)

wire AWREADY;
wire AWVALID;
wire [ADDR_WIDTH-1:0] AWADDR;
wire [2:0] AWPROT;

// Write Data (W)

wire WREADY;
wire WVALID;
wire [DATA_WIDTH-1:0] WDATA;
wire [1:0] WSTRB;

// Write Response (B)

wire BVALID;
wire [1:0] BRESP;
wire BREADY;

// Read Address (AR)

wire ARREADY;
wire ARVALID;
wire [ADDR_WIDTH-1:0] ARADDR;
wire [2:0] ARPROT;

// Read Data (R)

wire RVALID;
wire [DATA_WIDTH-1:0] RDATA;
wire [1:0] RRESP;
wire RREADY;

axi4lite_master master0 (
	.ACLK(clk_axi_bus),
	.ARESETn(resetn_bus),
	.STARTW(STARTW),
	.STARTR(STARTR),
	.m_addr(m_addr),
	.m_wdata(m_wdata),
	.m_wstrb(m_wstrb),
	.m_rdata(m_rdata),
	.m_wdone(m_wdone),
	.m_rdone(m_rdone),
	.m_wresp(m_wresp),
	.m_rresp(m_rresp),
	.AWREADY(AWREADY),
	.AWVALID(AWVALID),
	.AWADDR(AWADDR),
	.AWPROT(AWPROT),
	.WREADY(WREADY),
	.WVALID(WVALID),
	.WDATA(WDATA),
	.WSTRB(WSTRB),
	.BVALID(BVALID),
	.BRESP(BRESP),
	.BREADY(BREADY),
	.ARREADY(ARREADY),
	.ARVALID(ARVALID),
	.ARADDR(ARADDR),
	.ARPROT(ARPROT),
	.RVALID(RVALID),
	.RDATA(RDATA),
	.RRESP(RRESP),
	.RREADY(RREADY)
	
);

subordinate_module slave0 (

	.ACLK(clk_axi_bus),
	.ARESETn(resetn_bus),
	.clk(clk_mem),
	.clk_90(clk_90_mem),
	.rst_n(reset_mem),
	.AWREADY(AWREADY),
	.AWVALID(AWVALID),
	.AWADDR(AWADDR),
	.WREADY(WREADY),
	.WVALID(WVALID),
	.WDATA(WDATA),
	.WSTRB(WSTRB),
	.BVALID(BVALID),
	.BRESP(BRESP),
	.BREADY(BREADY),
	.ARREADY(ARREADY),
	.ARVALID(ARVALID),
	.ARADDR(ARADDR),
	.RVALID(RVALID),
	.RDATA(RDATA),
	.RRESP(RRESP),
	.RREADY(RREADY)
);



endmodule
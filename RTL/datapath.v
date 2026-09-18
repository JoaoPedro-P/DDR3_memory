// [PT] Módulo: datapath - Datapath Físico (PHY). Gerencia a interface de dados síncrona e assíncrona. Contém as FIFOs de TX/RX e a lógica de strobe (DQS). Entradas: clocks, reset, reqs, dados cpu. Saídas: FIFOs, DQS. / [EN] Module: datapath - Physical Datapath (PHY). Manages synchronous and asynchronous data interfaces. Contains TX/RX FIFOs and strobe (DQS) logic. Inputs: clocks, reset, reqs, cpu data. Outputs: FIFOs, DQS.
module datapath(
    input  wire        clk,
    input  wire        clk_90,
    input  wire        rst_n,
    input  wire        write_req,
    input  wire        cpu_clk,   
    input  wire        cpu_rst_n, 
    
    // [PT] Sinais ATUALIZADOS PARA 32 BITS / [EN] UPDATED TO 32 BITS signals
    input  wire        cpu_wr_en, 
    input  wire [31:0] cpu_wdata,
	input  wire [3:0]  cpu_wstrb,
    output wire        tx_full,   
	output wire        tx_empty,  
    output wire [31:0] cpu_rdata, 
    output wire        rx_valid,  

    output wire        odt_out,
	input  wire [7:0]  dq_in,
    input  wire        dqs_in,
    input  wire        dqs_n_in,
    output wire [7:0]  dq_out,
    output wire        dqs_out_pad,
    output wire        dqs_n_out_pad,
    output wire        phy_dq_oe,
    output wire        phy_dqs_oe,
    output wire        DM
);

    wire tx_fifo_rd;
    wire phy_dq_en, phy_dqs_en, phy_dqs_val;
    wire dqs_out, dqs_n_out, dqs_tri_en;
    
    wire [31:0] internal_tx_data; 
	wire [31:0] internal_rx_data;
    wire [3:0]  internal_tx_wstrb;	
    wire        internal_rx_valid; 
    wire        rx_fifo_empty;     

    // [PT] Instanciação da Lógica de Controle Físico / [EN] Physical Control Logic Instantiation
    physic_control_logic control_inst (
        .clk(clk), .rst_n(rst_n), .write_req(write_req),
        .tx_fifo_rd(tx_fifo_rd), .phy_dq_en(phy_dq_en), 
        .phy_dqs_en(phy_dqs_en), .phy_dqs_val(phy_dqs_val), .odt_out(odt_out)
    );

    // [PT] Instanciação do Phase Shifter DQS / [EN] DQS Phase Shifter Instantiation
    dqs_phase_shifter phase_inst(
        .clk_90(clk_90), .phy_dqs_en(phy_dqs_en), .phy_dqs_val(phy_dqs_val), 
        .dqs_out(dqs_out), .dqs_n_out(dqs_n_out), .dqs_tri_en(dqs_tri_en)
    );

    // [PT] TX FIFO (Agora 36 bits: 32 Data + 4 Strobe) / [EN] TX FIFO (Now 36 bits: 32 Data + 4 Strobe)
    fifo_async #(.DATA_WIDTH(36), .ADDR_WIDTH(4)) tx_fifo_inst(
        .wr_clk(cpu_clk), .wr_rst_n(cpu_rst_n), .wr_en(cpu_wr_en),        
        .wr_data({cpu_wstrb, cpu_wdata}), .full(tx_full),           
        .rd_clk(clk), .rd_rst_n(rst_n), .rd_en(tx_fifo_rd),       
        .rd_data({internal_tx_wstrb, internal_tx_data}), .empty(tx_empty)
    );

	assign phy_dq_oe  = phy_dq_en;
    assign phy_dqs_oe = dqs_tri_en;
	 
    // [PT] Conversor Tri-state e Interface de Dados / [EN] Tri-state and Data Interface Converter
    tri_state_and_converter tri_converter_inst(
        .clk(clk), .clk_90(clk_90), .rst_n(rst_n), 
        .phy_dq_en(phy_dq_en), .phy_dqs_en(dqs_tri_en),
        .dqs_out(dqs_out), .dqs_n_out(dqs_n_out),
        .tx_data(internal_tx_data), .rx_data(internal_rx_data),   
        .rx_valid(internal_rx_valid), .tx_wstrb(internal_tx_wstrb),
		.dq_in(dq_in), .dqs_in(dqs_in), .dqs_n_in(dqs_n_in),
        .dq_out(dq_out), .dqs_out_pad(dqs_out_pad), .dqs_n_out_pad(dqs_n_out_pad),
        .DM(DM)
    );

    // [PT] RX FIFO (Agora 32 bits puros) / [EN] RX FIFO (Now pure 32 bits)
    fifo_async #(.DATA_WIDTH(32), .ADDR_WIDTH(4)) rx_fifo_inst(
        .wr_clk(clk), .wr_rst_n(rst_n), .wr_en(internal_rx_valid),
        .wr_data(internal_rx_data), .full(), 
        .rd_clk(cpu_clk), .rd_rst_n(cpu_rst_n), .rd_en(!rx_fifo_empty), 
        .rd_data(cpu_rdata), .empty(rx_fifo_empty)
    );

    assign rx_valid = !rx_fifo_empty;
endmodule
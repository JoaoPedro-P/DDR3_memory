/*
 * module: datapath
 * -----------------
 * PT: Datapath Físico (PHY). Gerencia a interface de dados síncrona e assíncrona.
 *     Contém as FIFOs de TX/RX e a lógica de strobe (DQS).
 * 
 * EN: Physical Datapath (PHY). Manages synchronous and asynchronous data interfaces.
 *     Contains TX/RX FIFOs and strobe (DQS) logic.
 */
module datapath(
    // -------------------------------------------------------------------------
    // PT: Sinais do Sistema | EN: System Signals
    // -------------------------------------------------------------------------
    input  wire        clk,       // PT: Clock principal (0°) | EN: Main PHY clock (0 degrees)
    input  wire        clk_90,    // PT: Clock defasado (90°) | EN: Delayed PHY clock (90 degrees)
    input  wire        rst_n,     // PT: Reset | EN: Reset
	 
    // -------------------------------------------------------------------------
    // PT: Interface com o Scheduler | EN: Scheduler Interface
    // -------------------------------------------------------------------------
    input  wire        write_req, // PT: Inicia burst de escrita | EN: Starts write burst

    // -------------------------------------------------------------------------
    // PT: Interface com a CPU | EN: CPU Interface (External Clock Domain)
    // -------------------------------------------------------------------------
    input  wire        cpu_clk,   
    input  wire        cpu_rst_n, 
    input  wire        cpu_wr_en, 
    input  wire [15:0] cpu_wdata, 
    output wire        tx_full,   
	output wire        tx_empty,  
    output wire [15:0] cpu_rdata, 
    output wire        rx_valid,  

    // -------------------------------------------------------------------------
    // PT: Pinos Físicos DDR3 | EN: Physical DDR3 Pins
    // -------------------------------------------------------------------------
    output wire        odt_out,
    inout  wire [7:0]  DQ,
    inout  wire        DQS, 
    inout  wire        DQS_n
);

    // PT: Roteamento Interno | EN: Internal Routing
    wire tx_fifo_rd;
    wire phy_dq_en, phy_dqs_en, phy_dqs_val;
    wire dqs_out, dqs_n_out, dqs_tri_en;
    
    wire [15:0] internal_tx_data; 
	 
	wire [15:0] internal_rx_data;  
    wire        internal_rx_valid; 
    wire        rx_fifo_empty;     

    // =========================================================================
    // PT: 1. FSM de Controle Físico | EN: 1. PHY Controller FSM
    // =========================================================================
    physic_control_logic control_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .write_req(write_req),
        .tx_fifo_rd(tx_fifo_rd), 
        .phy_dq_en(phy_dq_en), 
        .phy_dqs_en(phy_dqs_en), 
        .phy_dqs_val(phy_dqs_val), 
        .odt_out(odt_out)
    );

    // =========================================================================
    // PT: 2. Deslocador de Fase DQS | EN: 2. DQS Phase Shifter
    // =========================================================================
    dqs_phase_shifter phase_inst(
        .clk_90(clk_90),      
        .phy_dqs_en(phy_dqs_en),  
        .phy_dqs_val(phy_dqs_val), 
        .dqs_out(dqs_out),
        .dqs_n_out(dqs_n_out),
        .dqs_tri_en(dqs_tri_en)
    );

    // =========================================================================
    // PT: 3. FIFO de Transmissão | EN: 3. TX FIFO (CPU -> PHY)
    // =========================================================================
    fifo_async #(.DATA_WIDTH(16), .ADDR_WIDTH(4)) tx_fifo_inst(
        .wr_clk(cpu_clk),
        .wr_rst_n(cpu_rst_n),
        .wr_en(cpu_wr_en),        
        .wr_data(cpu_wdata),      
        .full(tx_full),           

        .rd_clk(clk),
        .rd_rst_n(rst_n),
        .rd_en(tx_fifo_rd),       
        .rd_data(internal_tx_data), 
        .empty(tx_empty)
    );

    // =========================================================================
    // PT: 4. Conversor Tri-State e SDR-DDR | EN: 4. Tri-State and SDR-DDR Converter
    // =========================================================================
    tri_state_and_converter tri_converter_inst(
        .clk(clk), 
        .clk_90(clk_90),            
        .rst_n(rst_n), 
        .phy_dq_en(phy_dq_en), 
        .phy_dqs_en(dqs_tri_en),
        .dqs_out(dqs_out), 
        .dqs_n_out(dqs_n_out),
        
        .tx_data(internal_tx_data), 
        .rx_data(internal_rx_data),   
        .rx_valid(internal_rx_valid), 
        
        .DQ(DQ),
        .DQS(DQS), 
        .DQS_n(DQS_n)
    );

    // =========================================================================
    // PT: 5. FIFO de Recepção | EN: 5. RX FIFO (PHY -> CPU)
    // =========================================================================
    fifo_async #(.DATA_WIDTH(16), .ADDR_WIDTH(4)) rx_fifo_inst(
        .wr_clk(clk),
        .wr_rst_n(rst_n),
        .wr_en(internal_rx_valid),
        .wr_data(internal_rx_data),
        .full(), 

        .rd_clk(cpu_clk),
        .rd_rst_n(cpu_rst_n),
        .rd_en(!rx_fifo_empty), 
        .rd_data(cpu_rdata),
        .empty(rx_fifo_empty)
    );

    assign rx_valid = !rx_fifo_empty;
endmodule

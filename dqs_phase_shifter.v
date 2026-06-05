/*
 * module: dqs_phase_shifter
 * -----------------
 * PT: Deslocador de Fase do Strobe de Dados (DQS). 
 *     Gera os sinais DQS e DQS# defasados para centralizar o strobe no "olho" dos dados.
 * 
 * EN: Data Strobe (DQS) Phase Shifter.
 *     Generates phase-shifted DQS and DQS# signals to center the strobe in the data "eye".
 */
module dqs_phase_shifter (
    // PT: Clock de 90° vindo do PLL | EN: 90-degree clock from PLL
    input  wire clk_90,      

    // PT: Sinais de Controle da PHY | EN: Control Signals from PHY
    input  wire phy_dqs_en,  // PT: Habilita Tri-State | EN: Tri-State Enable
    input  wire phy_dqs_val, // PT: 0=Pre/Post-amble (Estat.), 1=Data (Pulsante) | EN: 0=Pre/Post-amble (Stat.), 1=Data (Pulsing)

    // PT: Saídas para o Pad Ring | EN: Pad Ring Outputs
    output wire dqs_out,
    output wire dqs_n_out,
    output wire dqs_tri_en
);

    assign dqs_tri_en = phy_dqs_en;

    /*
     * PT: Lógica do Strobe Principal:
     * Se val=1, pulsa com o clk_90. Se val=0, fica em 0 (Pre/Post-amble).
     * EN: Main Strobe Logic:
     * If val=1, pulses with clk_90. If val=0, stays at 0 (Pre/Post-amble).
     */
    assign dqs_out = (phy_dqs_val == 1'b1) ? clk_90 : 1'b0;

    /*
     * PT: Lógica Diferencial DQS#:
     * Inverso lógico do strobe principal.
     * EN: DQS# Differential Logic:
     * Logical inverse of the main strobe.
     */
    assign dqs_n_out = (phy_dqs_val == 1'b1) ? ~clk_90 : 1'b1;

endmodule

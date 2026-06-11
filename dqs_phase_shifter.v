/*
 * module: dqs_phase_shifter
 * -----------------
 * PT: Deslocador de Fase do Strobe de Dados (DQS). Este módulo é parte essencial da PHY 
 *     (Camada Física) do controlador de memória.
 *     
 *     Importância do clk_90:
 *     Em memórias DDR3, o sinal de strobe (DQS) deve estar alinhado no centro do "olho" de 
 *     dados para garantir a maior margem de captura possível em altas frequências. 
 *     O uso de um clock defasado em 90° emula a função de um DLL (Delay Locked Loop) 
 *     analógico, permitindo que as bordas do DQS ocorram exatamente quando o dado DQ 
 *     está mais estável.
 *
 *     Estados do Strobe:
 *     1. Preamble/Post-amble: O DQS é mantido em nível lógico baixo (ou alto p/ DQS#) 
 *        pela lógica de controle (val=0).
 *     2. Fase de Dados: O DQS pulsa síncrono ao clk_90 (val=1), capturando os dados DQ.
 *
 * EN: Data Strobe (DQS) Phase Shifter. This module is an essential part of the memory 
 *     controller's PHY (Physical Layer).
 *     
 *     Importance of clk_90:
 *     In DDR3 memories, the strobe signal (DQS) must be aligned at the center of the 
 *     data "eye" to ensure the maximum capture margin at high frequencies. 
 *     The use of a 90-degree phase-shifted clock emulates an analog DLL 
 *     (Delay Locked Loop) function, allowing DQS edges to occur exactly when 
 *     the DQ data is most stable.
 *
 *     Strobe Phases:
 *     1. Preamble/Post-amble: DQS is held at a low logic level (or high for DQS#) 
 *        by the control logic (val=0).
 *     2. Data Phase: DQS pulses synchronously with clk_90 (val=1), capturing DQ data.
 */
module dqs_phase_shifter (
    // PT: Clock de 90° vindo do PLL/Gerador de clock. | EN: 90-degree clock from PLL.
    input  wire clk_90,      

    // PT: Sinais de Controle da PHY | EN: Control Signals from PHY
    input  wire phy_dqs_en,  // PT: Habilita Tri-State (1=Saída, 0=Hi-Z). | EN: Tri-State Enable.
    input  wire phy_dqs_val, // PT: 0=Pre/Post-amble, 1=Dado Pulsante. | EN: 0=Pre/Post-amble, 1=Pulsing Data.

    // PT: Saídas Diferenciais | EN: Differential Outputs
    output wire dqs_out,     // PT: Sinal DQS positivo. | EN: DQS positive signal.
    output wire dqs_n_out,   // PT: Sinal DQS negativo (Inverso). | EN: DQS negative signal.
    output wire dqs_tri_en   // PT: Controle de enable para o buffer tri-state. | EN: Tri-state buffer enable.
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

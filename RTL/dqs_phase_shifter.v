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
/*
 * module: dqs_phase_shifter
 * -----------------
 * PT: Deslocador de Fase do Strobe de Dados (DQS).
 * (Otimizado para síntese segura de Clock Gating)
 * EN: Data Strobe (DQS) Phase Shifter.
 * (Optimized for safe Clock Gating synthesis)
 */
module dqs_phase_shifter (
    input  wire clk_90,      // [PT] Clock deslocado em 90 graus / [EN] 90-degree shifted clock
    input  wire phy_dqs_en,  // [PT] Habilita o tri-state do DQS / [EN] Enables DQS tri-state
    input  wire phy_dqs_val, // [PT] Sinal de validade do DQS / [EN] DQS valid signal
    output wire dqs_out,     // [PT] Saída positiva do DQS / [EN] DQS positive output
    output wire dqs_n_out,   // [PT] Saída negativa do DQS / [EN] DQS negative output
    output wire dqs_tri_en   // [PT] Controle de habilitação do DQS / [EN] DQS enable control
);
    // [PT] Atribuição do tri-state / [EN] Tri-state assignment
    assign dqs_tri_en = phy_dqs_en;

    // [PT] Remoção do latch de atraso que estava eliminando o 1º pulso de DQS. Como phy_dqs_val transita na borda do clk (0°), e o clk_90 sempre está em 0 nesses instantes exatos, a porta AND não gera glitches. / [EN] Removal of the delay latch that was eliminating the 1st DQS pulse. Since phy_dqs_val transitions at the clk edge (0°), and clk_90 is always 0 at these exact moments, the AND gate does not generate glitches.
    assign dqs_out   = phy_dqs_val & clk_90;
    assign dqs_n_out = ~(phy_dqs_val & clk_90);

endmodule
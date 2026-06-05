/*
 * module: cpu_addr_decoder
 * -----------------
 * PT: Decodificador de Endereços da CPU. 
 *     Divide o endereço linear de 27 bits da CPU em Linha, Banco e Coluna.
 * 
 * EN: CPU Address Decoder.
 *     Splits the 27-bit linear CPU address into Row, Bank, and Column components.
 */
module cpu_addr_decoder (
    input  wire [26:0] cpu_addr,     // PT: Endereço linear | EN: Linear address
    output wire [13:0] row_addr,     // PT: Endereço de Linha (16K) | EN: Row address (16K)
    output wire [2:0]  bank_addr,    // PT: Endereço de Banco (8) | EN: Bank address (8)
    output wire [9:0]  col_addr      // PT: Endereço de Coluna (1K) | EN: Column address (1K)
);

    // PT: Mapeamento de bits baseado no Datasheet | EN: Bit mapping based on the Datasheet
    assign row_addr  = cpu_addr[26:13];
    assign bank_addr = cpu_addr[12:10];
    assign col_addr  = cpu_addr[9:0];

endmodule

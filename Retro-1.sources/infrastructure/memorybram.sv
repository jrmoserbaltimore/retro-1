// vim: sw=4 ts=4 et
// BRAM memory module
//
// Used for one-cycle cartridge cache, video RAM, system RAM, and so forth.
//
// For larger (512Kio) RAM, use RetroSRAM. Sega CD for example requires 768Kio of main system RAM.

module RetroBRAM
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 8
)
(
    RetroMemoryPort.Target Initiator
);
    assign Initiator.Ready = '1;
    assign Initiator.DataReady = '1;
    
    // TODO:  Instantiate multiple BRAMs based on AddressBusWidth, multiplex across them based on
    // DataBusWidth, mux when exceeding DataBusWidth. e.g. for 16-bit address bus at 8-bit data
    // width, a 7-series requires 16 36Kb (4Kio + ECC) blocks, so we must fetch 16 bits at a time
    // and use WE to control when writing a byte.
    
`ifdef 7SERIES
   // BRAM_SINGLE_MACRO: Single Port RAM
   // Xilinx HDL Language Template, version 2020.1

   /////////////////////////////////////////////////////////////////////
   //  READ_WIDTH | BRAM_SIZE | READ Depth  | ADDR Width |            //
   // WRITE_WIDTH |           | WRITE Depth |            |  WE Width  //
   // ============|===========|=============|============|============//
   //    37-72    |  "36Kb"   |      512    |    9-bit   |    8-bit   //
   //    19-36    |  "36Kb"   |     1024    |   10-bit   |    4-bit   //
   //    10-18    |  "36Kb"   |     2048    |   11-bit   |    2-bit   //
   //     5-9     |  "36Kb"   |     4096    |   12-bit   |    1-bit   //
   //     3-4     |  "36Kb"   |     8192    |   13-bit   |    1-bit   //
   //       2     |  "36Kb"   |    16384    |   14-bit   |    1-bit   //
   //       1     |  "36Kb"   |    32768    |   15-bit   |    1-bit   //
   /////////////////////////////////////////////////////////////////////

   BRAM_SINGLE_MACRO #(
      .BRAM_SIZE("36Kb"), 
      .DEVICE("7SERIES"), // Target Device: "7SERIES" 
      .DO_REG(0), // Output register adds a cycle of latency
      .WRITE_WIDTH(DataBusWidth), // Valid values are 1-72 (37-72 only valid when BRAM_SIZE="36Kb")
      .READ_WIDTH(DataBusWidth),  // Valid values are 1-72 (37-72 only valid when BRAM_SIZE="36Kb")
      .WRITE_MODE("WRITE_FIRST"), // "WRITE_FIRST", "READ_FIRST", or "NO_CHANGE" 

   ) BRAMBlock (
      .DO(DO),       // Output data, width defined by READ_WIDTH parameter
      .ADDR(ADDR),   // Input address, width defined by read/write port depth
      .CLK(CLK),     // 1-bit input clock
      .DI(DI),       // Input data port, width defined by WRITE_WIDTH parameter
      .EN(EN),       // 1-bit input RAM enable
      .REGCE(REGCE), // 1-bit input output register enable
      .RST(RST),     // 1-bit input reset
      .WE(WE)        // Input write enable, width defined by write port depth
   );

`endif
endmodule
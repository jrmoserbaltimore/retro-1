// vim: sw=4 ts=4 et
// BRAM memory module
//
// Used for cartridge cache, video RAM, system RAM, and so forth.
//
// For larger (512Kio) RAM, use RetroSRAM. Sega CD for example requires 768Kio of main system RAM.

// FIXME:  rework around Wishbone Classic Pipelined
module RetroBRAM
#(
    parameter AddressBusWidth = 12,  // 4096 bytes = 1 block 8 bit + ecc on 7-series
    parameter DataBusWidth = 1, // Bytes
    parameter DeviceType = "Xilinx"
)
(
    IWishbone.SysCon System,
    //IRetroMemoryPort.Target Initiator
    IWishbone.Target Initiator
);
    assign Initiator.STALL = '0;

    generate
    if (DeviceType == "Xilinx")
    begin: Xilinx_BRAM_Inferred
        //  Xilinx Single Port Byte-Write Read First RAM
        //  This code implements a parameterizable single-port byte-write read-first memory where when data
        //  is written to the memory, the output reflects the prior contents of the memory location.
        //  If a reset or enable is not necessary, it may be tied off or removed from the code.
        //  Modify the parameters for the desired RAM characteristics.

        localparam NB_COL = DataBusWidth;            // Specify number of columns (number of bytes)
        localparam COL_WIDTH = 8;                    // Specify column width (byte width, typically 8 or 9)
        localparam RAM_DEPTH = 2**AddressBusWidth;   // Specify RAM depth (number of entries)

        logic [(NB_COL*COL_WIDTH)-1:0] Bram [RAM_DEPTH-1:0];
        logic [(NB_COL*COL_WIDTH)-1:0] BramData = {(NB_COL*COL_WIDTH){1'b0}};

        always @(posedge System.CLK)
        if (Initator.CYC && Initiator.STB) Initiator.DAT_ToInitiator <= Bram[Initiator.ADDR];

        genvar i;
        for (i = 0; i < NB_COL; i = i+1) begin: byte_write
            always @(posedge System.CLK)
            if (Initiator.CYC && Initiator.STB && Initiator.WE && Initiator.SEL[i])
            begin
                Bram[Initiator.ADDR][(i+1)*COL_WIDTH-1:i*COL_WIDTH]
                  <= Initiator.DAT_ToTarget[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
            end
        end
    end
    endgenerate

    // Always returns the data on the next clock cycle, no stall    
    always @(posedge System.CLK)
        Initiator.ACK <= Initiator.CYC & Initiator.STB;
endmodule
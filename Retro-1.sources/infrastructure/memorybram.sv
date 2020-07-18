// vim: sw=4 ts=4 et
// BRAM memory module
//
// Used for one-cycle cartridge cache, video RAM, system RAM, and so forth.
//
// For larger (512Kio) RAM, use RetroSRAM. Sega CD for example requires 768Kio of main system RAM.

module RetroBRAM
#(
    parameter int AddressBusWidth = 12,  // 4096 bytes = 1 block 8 bit + ecc on 7-series
    parameter int DataBusWidth = 1, // Bytes
    parameter string DeviceType = "Xilinx"
)
(
    RetroMemoryPort.Target Initiator
);
    assign Initiator.Ready = '1;
    assign Initiator.DataReady = ~(|Initiator.Write) & Initiator.Access; // Data ready on read
    
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

            // Initialize memory to all zeroes
            // XXX:  Is this strictly necessary to cause BRAM inferrence?
            integer ram_index;
            initial
                for (ram_index = 0; ram_index < RAM_DEPTH; ram_index = ram_index + 1)
                    Bram[ram_index] = {(NB_COL*COL_WIDTH){1'b0}};

        always @(posedge Initiator.Clk)
        if (Initiator.Access)
        begin
          Initiator.Dout <= Bram[Initiator.Address];
        end

        genvar i;
            for (i = 0; i < NB_COL; i = i+1) begin: byte_write
                always @(posedge Initiator.Clk)
                if (Initiator.Access && Initiator.Write[i])
                begin
                    Bram[Initiator.Address][(i+1)*COL_WIDTH-1:i*COL_WIDTH]
                      <= Initiator.Din[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
                end
            end
        end
    endgenerate
endmodule
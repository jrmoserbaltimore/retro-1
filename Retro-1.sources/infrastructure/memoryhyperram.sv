// vim: sw=4 ts=4 et
// PSRAM HyperRAM controller
//
// This can control a single HyperRAM PSRAM device and present it as SRAM.  HyperRAM PSRAM
//
//  - Operates at double data rate
//  - Has low latency (166MHz, 6 clock latency, 1 clock transfer, 42ns)
//  - Can operate in linear burst mode up to 128-bytes, perfect for OneCycleCache fetches
//  - Uses a simple protocol similar to SDRAM
//    - CS# transitions high to low
//    - 48 bits of Command/Address are written over 6 cycles
//    - Data is returned double-data-rate on the 8 bit bus (386ns to transfer 128 bytes)
//    - CS# transitions low to high

interface IHyperRAM;
    logic CS;
    logic CK; // Clock, external
    // DQ
    logic [7:0] SDin;
    logic [7:0] SDout;
    logic SRWDSin, SRWDSout;
    logic Reset;

    // Controller's view of the HyperRAM chip
    modport Component
    (
        output CS,
        input CK,
        output .Dout(SDin),
        input .Din(SDout),
        output .RWDSout(SRWDSin),
        input .RWDSin(SRWDSout),
        output Reset
    );

    // HyperRAM chip's view of the controller
    modport Controller
    (
        input CS,
        input CK,
        input .Din(SDin),
        output .Dout(SDout),
        input .RWDSin(SRWDSin),
        output .RWDSout(SRWDSout),
        input Reset
    );
endinterface

module RetroHyperRAM
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 8
)
(
    RetroMemoryPort.Target Initiator,
    IHyperRAM.Component HyperRAM
);

endmodule
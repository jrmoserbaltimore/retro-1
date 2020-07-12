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

module RetroHyperRAM
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 8
)
(
    RetroMemoryPort.Target Initiator,
    // TODO:  HyperRAM interface
);

endmodule
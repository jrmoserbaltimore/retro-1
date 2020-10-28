// vim: sw=4 ts=4 et
// Moonset Retro console
//
// The console connects directly to the DDR chips.  A RISC-V CPU core hosts an OS to control this
// as a peripheral.  That CPU's memory controller must request RAM from the DMA bus, rather than
// the console going through the OS to get data.

// BRAM memory module exposed as Wishbone Classic Pipelined
//
// Use WishboneBRAM for cartridge cache, video RAM, system RAM, and so forth.
//
// Use WishboneCache or another low-latency RAM for larger (512Kio) RAM. Sega CD for example
// requires 768Kio of main system RAM.

module RetroConsole
(
    // Clock
    input logic Clk,
    input logic Reset,

    // System memory
    // FIXME:  Not Wishbone all the way down; need real I/O to DDR and HyperRAM
    IWishbone.Initiator DDRBus0,
    IWishbone.Initiator DDRBus1,
    IWishbone.Initiator HyperRAM0,
    IWishbone.Initiator HyperRAM1,

    // Audio-Video
    output logic [12:0] AV,

    // ================
    // = External Bus =
    // ================
    // An FPGA expansion can use this entire bus when not using the cartridge port, notably for
    // optical-based systems such as SegaCD, Sega Saturn, or PSXFPGA.  Mostly this might enable
    // Playstation 2 or other demanding hardware by adding an FPGA to offload functions.

    // Cartridge bus wide enough for NES, 69 I/O
    // XXX:  Just make this the expansion port?
    output logic CartridgeClk,
    input logic [68:0] CartridgeIn,
    output logic [68:0] CartridgeOut,
    
    // SPI for microcontroller
    input logic MISO,
    output logic MOSI,
    output logic SPICS,
    output logic SPIClk,

    // Expansion
    input logic [31:0] ExpansionPortIn,
    output logic [31:0] ExpansionPortOut
);

    logic ClkEn;

    // TODO:
    //  - Instantiate DDR and HyperRAM controllers, if configured
    //  - Instantiate Wishbone interface to memory elements
    //  - Instantiate SPI command manager
    //  - Instantiate DMA
    //  - Instantiate video filters
    //  - Instantiate audio filters
    //  - Instantiate AV controller
    //  - Instantiate RISC-V CPU
    //  - Release the reset

    // Boot porcess:
    //  - Microcontroller configures FPGA
    //  - Upon reset, DMA points to SPI controller signaling boot ROM
    //  - Microcontroller provides the loaded boot ROM (from SD card)
    //  - Boot ROM copies itself to RAM, disables boot ROM
    //  - Boot begins
    //
    //  All further boot process considerations are in software.
endmodule
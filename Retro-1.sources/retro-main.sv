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

// XXX:  Should some of these be uwire?
// FIXME:  Should somehow be callable and configurable, instead of using RetroCoreShim
module RetroConsole
(
    // Clock
    IWishbone.SysCon System,

    // Communications port from host
    // Reset and Pause are packets on this interface
    IWishbone.Target Host,
    
    // System memory
    // XXX:  Should we just use one bus with stacked chips?
    IDDR3.Component DDRChip0,
    IDDR3.Component DDRChip1,

    // Audio-Video
    output logic [12:0] AV,

    // ================
    // = External Bus =
    // ================
    // An FPGA expansion can use this entire bus when not using the cartridge port, notably for
    // optical-based systems such as SegaCD, Sega Saturn, or PSXFPGA.  Mostly this might enable
    // Playstation 2 or other demanding hardware by adding an FPGA to offload functions.

    // Cartridge bus wide enough for NES, 69 I/O
    output logic CartridgeClk,
    input logic [68:0] CartridgeIn,
    output logic [68:0] CartridgeOut,
    
    // Controller I/O, from µC
    input logic ControllerClk,
    input logic ControllerIn,
    output logic ControllerOut,
        
    // Expansion
    input logic [31:0] ExpansionPortIn,
    output logic [31:0] ExpansionPortOut,
    
    // Core
    IWishbone.Initiator Core
);

    logic ClkEn;

endmodule
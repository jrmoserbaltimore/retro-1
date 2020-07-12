// vim: sw=4 ts=4 et
// Moonset Retro console
//
// The console connects directly to the DDR chips.  A RISC-V CPU core hosts an OS to control this
// as a peripheral.  That CPU's memory controller must request RAM from the DMA bus, rather than
// the console going through the OS to get data.

// XXX:  Should some of these be uwire?
module RetroConsole
(
    // Clock
    input Clk,

    // Communications port from host
    // Reset and Pause are packets on this interface
    RetroComm.Target Comm,
    
    // System memory
    // XXX:  Should we just use one bus with
    IDDR3.Component DDRChip0,
    IDDR3.Component DDRChip1,
        
    // HyperRAM
    IHyperRAM.Component HyperRAM0,
    IHyperRAM.Component HyperRAM1,
    
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
    RetroComm.Initiator Core
);

endmodule
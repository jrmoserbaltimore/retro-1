// vim: sw=4 ts=4 et
// Example RetroCoreShim.  The shim sets up for an actual core, creating RAM objects, mapping the
// expansion port (e.g. to a cartridge), exposing the controller properly to the core, managing
// CATC, handling cache, and so forth.
//
// Each core will require individualized RAM creation and mapping.  Multi-core systems will
// consume enormous amounts of BRAM if instantiated concurrently.  A multi-core configuration must
// implement its own shim to allocate these resources to whatever system is running.

// Example GamePak interface
interface ExampleGamePak
(
);
    logic Clk;
    logic Write;
    logic Read;
    logic CS;
    logic Address [15:0];
    logic DataIn [7:0];
    logic DataOut [7:0];
    logic Reset;
    logic AudioIn;

    modport Controller
    (
        output Clk,
        output Write,
        output Read,
        output CS,
        output Address,
        input DataIn,
        output DataOut,
        output Reset,
        input Audio
    );
    
    modport VirtualPak
    (
        input Write,
        input Read,
        input CS,
        input Address,
        output DataIn,
        input DataOut,
        input Reset,
        output Audio
    );
endinterface

// This is the core shim.  RetroConosle connects everything to this, which then connects to the
// core module.  In here we set up various types of RAM, clock control, the cartridge controller,
// and any peripherals.
module RetroCoreShim
(
    // The console sends a core system clock (e.g. 200MHz) and a clock-enable
    // to produce the console's reference clock.
    input logic CoreClock, // Core system clock
    input logic ClkEn,

    // DDR System RAM or other large
    RetroMemoryPort.Initiator MainRAM,
    // DDR, HyperRAM, or SRAM on the expansion bus
    RetroMemoryPort.Initiator ExpansionRAM0,
    RetroMemoryPort.Initiator ExpansionRAM1,
    RetroMemoryPort.Initiator ExpansionRAM2,

    output logic [12:0] AV,  // AV
    // ================
    // = External Bus =
    // ================

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

    // Console
    RetroComm.Target Console
);

    uwire Delay;
    uwire Reset;
    uwire Ce;
    
    uwire Read, Write, CS;
    uwire [15:0] Address;
    uwire [7:0] DataIn, DataOut;
    uwire AudioIn;

    uwire CartDelay;
    uwire MainRAMDelay;
    uwire VRAMDelay;
    
    assign Delay = CartDelay | MainRAMDelay | VRAMDelay;

    RetroCATC CATC(
        .Clk(CoreClk),
        .Delay(Delay),
        .ClkEn(ClkEn),
        .Reset(Reset),
        .ClkEnOut(Ce)
    );

    ExampleGamePak GamePak(
        .Clk(CartridgeClk),
        .Write(CartridgeOut[2]),
        .Read(CartridgeOut[3]),
        .CS(CartridgeOut[4]),
        .Address(CartridgeOut[20:5]),
        .DataIn(CartridgeIn[28:21]),
        .DataOut(CartridgeOut[28:21]),
        .Reset(CartridgeOut[29]),
        .AudioIn(CartridgeIn[30]),
    );

    ExampleGamePak VirtualGamePak
    (
        .Clk('0),
        .Write(Write),
        .Read(Read),
        .CS(CS),
        .Address(Address),
        .DataIn(DataIn),
        .DataOut(DataOut),
        .Reset(Reset),
        .AudioIn(AudioIn)
    );

    // Cartridge Controller is either pass-through or storage + mappers
    ExampleCartridgeController CartridgeController
    (
        .Clk(CoreClk),
        .ClkEn(Ce), // Note:  Operations fetching/caching virtual cart must continue regardless
        .Delay(CartDelay),
        // Example:  Gameboy GamePak
        .GamePak(GamePak.Controller),
        .Frontend(VirtualGamePak.VirtualPak)
    );
    // XXX: Create MainRAM and VRAM memory ports
    RetroMyCore TheCore
    (
        .Clk(CoreClk),
        .ClkEn(Ce),
        // TODO:  Create MainRAM, .MainRAM(MainRAM),
        // TODO:  Create VRAM, .VRAM(VRAM)
        .AV(AV),
        .GamePak(VirtualGamePak.Controller),
        // TODO:  Serial controller
        // etc.
    );
endmodule

// Core module:  Abstract to clock/CE, RAM elements, AV, cartridge, peripherals.
// Might make sense to abstract the cartridge address/data buses as a memory port.
module RetroMyCore
(
    input Clk,
    input ClkEn,
    RetroMemoryPort.Initiator MainRAM,
    RetroMemoryPort.Initiator VRAM,

    // FIXME:  input for comm with HDMI/DP?
    output logic [12:0] AV;

    // ================
    // = External Bus =
    // ================
    // Cartridge and serial bus only in this configuration.
    // Uses 30 I/O GamePak + 4 I/O serial = 34 I/O

    // GamePak bus
    ExampleCartridgeController.Controller(GamePak);

    // Serial bus for Game-Link cable
    output logic SerialOut,
    output logic SerialIn,
    output logic SD, // CPU pin 14? Disconnected in the cable
    output logic SerialClk
);

endmodule
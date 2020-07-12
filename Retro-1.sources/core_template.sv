// vim: sw=4 ts=4 et
// Example core

module myRetro1Core
(
	input uwire Clk,
	input uwire Reset,
    input uwire Pause,  // Level-sensitive

    // TODO: module interface for SRAM (two buses)
    // TODO: module interface for SDRAM (DDR)
    // TODO: module interface for storage (packet-based, DMA)
    //  XXX: peripheral/APIC instead?
    // TODO: 68-pin
    //  - Direct to Cartridge
    //  - Interfaces with Cartridge controller
    // TODO: Controller pins 
	// TODO: module interface for AV output
);

endmodule
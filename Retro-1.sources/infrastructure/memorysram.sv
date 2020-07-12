// vim: sw=4 ts=4 et
// SRAM controller
//
// This can control multiple SRAM devices with a single-port interface:
//
//  - Use the MSBits as a chip select; or
//  - Increase the data bus width
//
// The latter is recommended.  For 16 bits, shift the address right one; for 32 bits, two. 
//
// For independent busses, instantiate multiple modules.
//
// The instantiator must handle all signaling beyond address, data, and WR.

module RetroSRAM
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 8
)
(
    RetroMemoryPort.Target Initiator,
    output bit [AddressBusWidth-1:0] Address,
    output logic Write,
    output bit [DataBusWidth-1:0] Dout,
    input bit [DataBusWidth-1:0] Din
);
    assign Write = Initiator.Write & Initiator.Access;
    assign Address = Initiator.Address;
    assign Dout = Initiator.Din;
    assign Initiator.Dout = Din;
    assign Initiator.Ready = '1;
    assign Initiator.DataReady = '1;
endmodule
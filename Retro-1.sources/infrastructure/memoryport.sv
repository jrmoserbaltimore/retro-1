// vim: sw=4 ts=4 et
// Memory port interface.
//
// This is a read-write port addressed directly with data coming in and out.  It's unbuffered.
//
// For non-protocol RAM, such as SRAM, this acts as a direct bus:  Address, data, and Write go
// directly to the backing chip.  A permanently-mapped chip, such as an SRAM chip, will
// permanently read Ready and DataReady. 
//
// For other RAM, Ready signals ready to take commands, and DataReady signals that data is
// ready for read in FIFO order.  This means a long-latency read from e.g. DRAM can concurrently
// send address reads and writes while reading output.

interface RetroMemoryPort
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 8
);
logic Clk;
logic [AddressBusWidth-1:0] Address;
logic [DataBusWidth-1:0] DInitiator;
logic [DataBusWidth-1:0] DTarget;
logic Access;
logic Write;
logic Ready;
logic DataReady;

modport Initiator
(
    input Clk,
    output Address,
    output .Dout(DInitiator), 
    input .Din(DTarget),
    output Access,
    output Write,
    input Ready,
    input DataReady
);

modport Target
(
    input Clk,
    input Address,
    input .Din(DInitiator), 
    output .Dout(DTarget),
    input Access,
    input Write,
    output Ready,
    output DataReady
);
endinterface
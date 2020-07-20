// vim: sw=4 ts=4 et
// RetroSoc communications interface.
//
// 16-bit

interface IRetroComm;
logic Interrupt;  // Target interrupts host.  Target always treats Strobe as interrupt.

// Data
logic Clk;
logic [15:0] DInitiator;  // Initiator output target input
logic [15:0] DTarget;  // Initiator input target output
logic IStrobe; // Data is ready
logic TStrobe;

modport Initiator
(
    input Clk,
    input Interrupt,
    // Data
    output .Dout(DInitiator), 
    input .Din(DTarget),
    output .Raise(TStrobe),
    input .Strobe(IStrobe)
);

modport Target
(
    input Clk,
    output Interrupt,
    
    input .Din(DInitiator), 
    output .Dout(DTarget),
    output .Raise(IStrobe),
    input .Strobe(TStrobe)
);
endinterface
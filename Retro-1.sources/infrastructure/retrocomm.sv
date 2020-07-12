// vim: sw=4 ts=4 et
// RetroSoc communications interface.
//
// 16-bit double data rate

interface RetroComm;
// Base system
logic Reset;
logic Pause;
logic Interrupt;

// Data
logic Clk;
logic [15:0] DInitiator;  // Initiator output target input
logic [15:0] DTarget;  // Initiator input target output
logic IStrobe;
logic TStrobe;

modport Initiator
(
    input Clk,
    output Reset,
    output Pause,
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
    input Reset,
    input Pause,
    output Interrupt,
    
    input .Din(DInitiator), 
    output .Dout(DTarget),
    output .Raise(IStrobe),
    input .Strobe(TStrobe)
);
endinterface
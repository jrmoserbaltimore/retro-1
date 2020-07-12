// vim: sw=4 ts=4 et
// DDR3 chip controller

interface IDDR3;
    logic Clk;
    
    modport Component
    (
        input Clk
    );
endinterface
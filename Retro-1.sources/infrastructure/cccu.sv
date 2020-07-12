// vim: sw=4 ts=4 et
// Clock Control Catch-Up infrastructure
//
// The CCCU module controls the reference clock into a core to work around timing issues.
//
// The reference clock for a core is a multiple of the standard reference clock.  The core only
// ticks on Ce, acting as a clock divider.
//
// Long-latency operations pause the core by disabling Ce and increment a catch-up register at
// each reference clock tick.  Whenever not paused in this manner, Ce remains enabled so long as
// the catch-up register is non-zero, and the catch-up register only decrements when the reference
// clock is not itself ticking.  The core operates from a faster reference clock during this time.
//
// An NES PPU frame is 16.64ms; a 44100Hz audio sample is 22.68us.  An NES ticks CPU every 559ns
// and PPU every 186ns from a 46.6ns reference clock, but none of those matter.
//
// At 2x, a 1.1us delay catches up 2.23us from its beginning, or four NES CPU clock ticks:  the two
// delayed, one at double speed to make up those two, and one more at double speed to make up for
// the clock cycle missed during catch-up.  A 13.4µs delay will require a total 23.5µs, just over a
// single audio sample.  These timings don't change on other systems:  on Gameboy Color, 113 rather
// than 24 CPU ticks makes 13.4µs, with the same catch-up time at 2x.
//
// Cores requiring CCCU operate at significantly higher fMax than their natural frequency.  The
// Sega CD uses a 12.5MHz (80ns) Motorola 68000; the 32X uses a 23MHz (43ns) SH2.  If these cannot
// run at 4x, then the core must buffer audio samples—although the buffer can be a few dozen
// microseconds.

module ClockCCU
#(
    parameter int ClockFactor = 2
)
(
    input Clk,
    input Delay, // Create a delay
    input CeIn,
    output Ce
);

    localparam ClockDivBits = 2**ClockFactor;
    bit [ClockDivBits-1:0] ClockDiv;
    bit [15:0] CatchUp;
    
    // Enable at the divided clock frequency or when catching up, but not when delaying
    assign Ce = (!ClockDiv | |CatchUp) & !Delay & CeIn;
    
    always_ff @(posedge Clk)
    begin
        if (CeIn)
        begin
            if (Delay & !ClockDiv) CatchUp++;
            // We're trying to catch up, but the clock is still ticking, so count those ticks too
            if (!Delay && ClockDiv == 0 && CatchUp > 0) CatchUp--;
            // Keep ticking the divider so the clock ticks will line up
            ClockDiv++;
        end
    end
endmodule
// vim: sw=4 ts=4 et
// Cycle Accurate Timing Control (CATC) infrastructure
//
// The CATC module controls the reference clock into a core to work around timing issues.
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
// Cores operate at significantly higher fMax than their natural frequency to use CATC.  The Sega
// CD uses a 12.5MHz (80ns) Motorola 68000; the 32X uses a 23MHz (43ns) SH2.  If these cannot run
// at 4x, then the core must buffer audio samples—although the buffer can be a few dozen
// microseconds.
//
// This also has a frequent cycle-check feature running the (multiplied) reference clock
// slightly-slow and checking frequently for lag, then accelerating.

module RetroCATC
#(
    parameter int ClockFactor = 2,
    parameter int CoreClock = 200000000, // 200MHz FPGA core clock
    parameter int ReferenceClock = 21477272, // NES reference clock
    parameter int TestFrequency = 18 // 1 second / 2^n, here 3.81 microseconds
)
(
    input Clk,
    input Delay, // Create a delay
    input ClkEn,
    input Reset,
    output ClkEnOut
);
    // Number of core clock cycles that pass between tests
    localparam int CoreCheckCycles = CoreClock / 2**TestFrequency;
    // Number of Reference Clock cycles that should have passed at each check.
    // ReferenceClock * 2**TestFrequency / CoreClock
    localparam int CheckCycles = 2**ClockFactor * ReferenceClock / CoreCheckCycles;
    
     // Clock divider to produce reference clock, slightly-slow if inexact.
     // e.g. 28.9% underclocked for NTSC NES.  With the defaults above, this is 23.64 reference
     // clock cycles behind at each check or almost 2 CPU clock cycles or 6 PPU cycles, checked
     // every 3.81 microseconds
     //
     // The clock factor is how much faster the reference clock should run, so multiplies the
     // reference clock.  Adding 1 is a substitute for ceiling.
    localparam int CoreDiv = 1 + (CoreClock / (ReferenceClock * 2**ClockFactor));
 
    // Catch-up rate
    localparam int CoreDivCatchup = ClockFactor * ReferenceClock / CoreClock;
    localparam int ClockDivBits = 2**$clog2(CoreDiv);
    
    bit [ClockDivBits-1:0] CoreClockDiv;
    bit [ClockFactor-1:0] ReferenceClockDiv;
    bit [15:0] CatchUp;
    bit [29:0] CoreCycles; // Core cycle counter
    bit [29:0] ReferenceCycles; // Reference cycle counting
    bit [TestFrequency:0] TestCount; // Yes it's meant to be 1 bit wider
    
    // Enable at the divided clock frequency or when catching up, but not when delaying.
    // Don't run at the full reference clock
    assign ClkEnOut = (!ReferenceClockDiv || CatchUp > 0) && !Delay && ClkEn && !CoreClockDiv;
    
    always_ff @(posedge Clk)
    if (Reset)
    begin
        CoreClockDiv = '0;
        ReferenceClockDiv = '0;
        CatchUp = '0;
        CoreCycles = '0;
        ReferenceCycles = '0;
        TestCount = '1;
    end
    
    always_ff @(posedge Clk)
    if (ClkEn && !Reset)
    begin
        if (CoreCycles == CoreClock - 1)
        begin
            // it's cycle check time
            // One full second has passed.  Align the clocks.
            // Delay is implied here.
            // Doesn't need to add to existing CatchUp because it's checking the whole count
            CatchUp <= ReferenceClock - ReferenceCycles
                + (CoreClockDiv == CoreClockDiv - 1 && !ReferenceClockDiv);
            // If the core clock divides evenly, then this happens.
            TestCount <= TestCount + (CoreCycles == CoreCheckCycles * TestCount) ? 1 : 0;
        end
        else if (CoreCycles == CoreCheckCycles * TestCount)
        begin
            // Multiply the cycles per check times the number of tests, and subtract the actual
            // cycles passed.
            // Delay is implied here.
            CatchUp <= CheckCycles * TestCount - CoreCycles
                + (CoreClockDiv == CoreClockDiv - 1 && !ReferenceClockDiv);
            if (TestCount[TestFrequency] && TestCount[1])
            begin
                // Reduce the number of reference clock cycles by 1 second and reset the test
                // count by as much.  This ensures the precisely-aligned check never fires when
                // ReferenceCycles > ReferenceClock. 
                ReferenceCycles <= ReferenceCycles - ReferenceClock; // no tick
                TestCount[TestFrequency] <= '0;
            end
            else
            begin
                TestCount <= TestCount + 1;
            end
        end
        else if (CoreClockDiv == CoreDiv - 1)
        begin
            // Always increment when ticking on delay
            if (Delay & !ReferenceClockDiv) CatchUp <= CatchUp + 1;
            // We're trying to catch up, but the clock is still ticking, so count those ticks too
            if (!Delay && ReferenceClockDiv != 0 && CatchUp > 0) CatchUp <= CatchUp - 1;
            // Keep ticking the divider so the clock ticks will line up
            ReferenceClockDiv <= ReferenceClockDiv + 1;
            ReferenceCycles <= ReferenceCycles + 1; // Count the tick
        end
        // Manage the core clock divider
        CoreClockDiv <= (CoreClockDiv == CoreDiv - 1) ? 0 : CoreClockDiv + 1;
        // Manage core clock cycle counter
        CoreCycles <= (CoreCycles == CoreClock - 1) ? '0 : CoreCycles + 1;
    end
endmodule
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
    parameter ClockFactor = 2,
    parameter CoreClock = 200000000, // 200MHz FPGA core clock
    parameter ReferenceClock = 21477272, // NES reference clock
    parameter TestFrequency = 18 // 1 second / 2^n, here 3.81 microseconds
)
(
    input Clk,
    input Delay, // Create a delay
    input FastCatchup,
    input Reset,
    input ClkEn,
    output ClkEnOut
);
    // Number of core clock cycles that pass between tests
    localparam CoreCheckCycles = CoreClock / 2**TestFrequency;
    // Number of Reference Clock cycles that should have passed at each check.
    localparam CheckCycles = ReferenceClock / CoreCheckCycles;

    wire InternalDelay;

    // With cartridges, we can run slower, but not faster by much.  For NES, the reference clock
    // is 1/9.312 of a 200MHz core clock.  200/9 is 3.47% overclocked, 200/10 is 6.88%
    // underclocked.  That's 2.8 reference clock cycles ahead, 5.6 cycles behind.  For faster
    // clocks, the difference will be smaller.
    //
    // Cartridge consoles have little RAM or else faster CPUs using CPU cache, so no long delays.
    // When running from a load image, a 128-byte fetch may take 3-4 microseconds.  It could take
    // over 100 microseconds to catch up in some cases, in which time more fetch may be required.
    // In such cases, without external hardware, a higher clock factor works.
    //
    // The core divider must operate at a high reference clock speed, but will typically run at
    // normal speed.  CoreDiv shows the normal reference clock speed, or slightly overclocked.
    // If it divides evenly, it runs at normal speed when not underclocked; otherwise it runs
    // faster.
    localparam CoreDiv = CoreClock / ReferenceClock;
    // If it divides evenly, the faster divider must be 1 less
    localparam EvenDiv = (CoreDiv == CoreClock / ReferenceClock) ? 1 : 0;
    
    // Catch-up rate uses a multiple of the reference clock
    localparam CoreDivCatchup = CoreClock / (ClockFactor * ReferenceClock);
    localparam ClockDivBits = 2**$clog2(CoreDivCatchup);

    bit [ClockDivBits-1:0] ReferenceClockDiv;
    bit [15:0] CatchUp;
 
    bit [$clog2(CoreClock):0] CoreCycles; // Core cycle counter
    bit [$clog2(ReferenceClock):0] ReferenceCycles; // Reference cycle counting
    bit [TestFrequency:0] TestCount; // Yes it's meant to be 1 bit wider

    wire ReferenceTick;
    wire FastReferenceTick;
    wire SlowReferenceTick;
    
    // Tick once the divider counts up
    assign ReferenceTick = (ReferenceClockDiv == CoreDiv - 1);
    // If running fast, i.e. cartless, use the faster CoreDivCatchup;
    // else use the reference tick.  If the reference tick is exactly accurate, speed it up
    // slightly.
    assign FastReferenceTick = 
                  ReferenceClockDiv == ((FastCatchup ? CoreDivCatchup : CoreDiv - EvenDiv) - 1);
    // Slow the reference clock down slightly
    assign SlowReferenceTick =
                  ReferenceClockDiv == (CoreDiv + 1);
    // Don't need to count missed ticks because deviation is calculated in full at each test cycle*******
    // Enable at the divided clock frequency or when catching up, but not when delaying.
    // Don't run at the full reference clock
    wire CEOut;
    assign CEOut = ClkEn && !InternalDelay &&
                      (
                       (CatchUp > 0  && FastReferenceTick) || // Speed up when behind
                       (CatchUp == 0 && ReferenceTick) ||     // Normal speed
                       (CatchUp < 0  && SlowReferenceTick)    // Slow down when ahead
                      );
    assign ClkEnOut = CEOut;

    // Delay if CatchUp is negative i.e. we're ahead and clock needs to slow down.
    // In FastCatchup mode, flat out stop; otherwise the slow reference tick will take over 
    assign InternalDelay = Delay || (CatchUp < 0 && !FastCatchup);
    
    always_ff @(posedge Clk)
    if (Reset)
    begin
        ReferenceClockDiv <= '0;
        CatchUp <= '0;
        CoreCycles <= '0;
        ReferenceCycles <= '0;
        TestCount <= 'h01;
    end
    else if (ClkEn)
    begin
        if (CoreCycles == CoreClock - 1)
        begin
            // One full second has passed.  Align the clocks.
            // Doesn't need to add to existing CatchUp because it's checking the whole count.
            // Make sure to include the current tick.
            CatchUp <= ReferenceClock - (ReferenceCycles + CEOut);
            // This is an aligning cycle
            TestCount <= '1;
        end else if (CoreCycles == CoreCheckCycles * TestCount)
        begin
            // Multiply the cycles per check times the number of tests, and subtract the actual
            // cycles passed.
            // The reference clock still ticks here, so capture CEOut 
            CatchUp <= CheckCycles * TestCount // The number of cycles that should have passed
                       - (ReferenceCycles + CEOut); // The number of cycles that have passed
            TestCount <= TestCount + 1;
        end else
        begin
            // Decrement CatchUp unless the real reference clock ticks
            CatchUp <= CatchUp - CEOut + ReferenceTick;
        end
        // Manage the core clock divider
        ReferenceClockDiv <= CEOut ? 0 : ReferenceClockDiv + 1;
        // Manage core clock cycle counter
        CoreCycles <= (CoreCycles == CoreClock - 1) ? '0 : CoreCycles + 1;
        // If it ticks on the output for any reason, count it
        ReferenceCycles <= ReferenceCycles + CEOut -
                          (CoreCycles == CoreClock - 1) ? ReferenceClock : '0;
    end
endmodule
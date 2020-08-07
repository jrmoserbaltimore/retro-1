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
    parameter TestFrequency = 16 // 1 second / 2^n, here 15.26 microseconds
)
(
    input Clk,
    input Delay, // Create a delay
    input FastCatchup,
    input Reset,
    input ClkEn,
    output ClkEnOut
);
    wire InternalDelay;

    // With cartridges, we can run slower, but not faster by much.  For NES, the reference clock
    // is 1/9.312 of a 200MHz core clock.  200/9 is 3.47% overclocked, 200/10 is 6.88%
    // underclocked.  That's 2.8 reference clock cycles ahead, 5.6 cycles behind.  For faster
    // clocks, the difference will be smaller.  Note that the overclock has to be faster than the
    // underclock!  That means the stepped-up clock has to run e.g. 200/8 or 16% faster.
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
    localparam EvenDiv = !(CoreClock % ReferenceClock);
    
    // Catch-up rate uses a multiple of the reference clock
    localparam CoreDivCatchup = CoreClock / (ClockFactor * ReferenceClock);
    localparam ClockDivBits = 2**$clog2(CoreDivCatchup);

    // Resources:  using an Alt clock instead of Fast/Slow moves from 215 to 184 LUT
    bit [ClockDivBits:0] ReferenceClockDiv = '0;
    bit [ClockDivBits:0] AltReferenceClockDiv = '0;
    bit [ClockDivBits-1:0] TickSuppress = '0;
    logic TickHold;

    bit signed [TestFrequency:0] CatchUp; // for 16, 3ms @ 21MHz, 327us @ 200MHz
 
    bit [$clog2(CoreClock):0] CoreCycles; // Core cycle counter
    bit signed [$clog2(ReferenceClock):0] ReferenceCycles; // Reference cycle counting
    // Needs to use this strategy to avoid compounding rounding error enormously
    bit [$clog2(ReferenceClock)+TestFrequency:0] ExpectedCycles;
    bit [$clog2(CoreClock)+TestFrequency:0] CoreExpectedCycles; 

    wire ReferenceTick;
    wire AltReferenceTick;

    wire AltTickFast;
    wire [ClockDivBits-1:0] FastTickTime;
    wire OneSecondSync;
    assign AltTickFast = (CatchUp > 0);
    assign FastTickTime = (FastCatchup ? CoreDivCatchup : CoreDiv - EvenDiv) - 1;
    assign OneSecondSync = CoreCycles == (CoreClock - 1);

    // Tick once the divider counts up
    assign ReferenceTick = (ReferenceClockDiv == (CoreDiv - EvenDiv));
    // If running fast, i.e. cartless, use the faster CoreDivCatchup; else use the reference tick.
    // If the reference tick is exactly accurate, speed it up slightly.
    // Harmless bug:  If you switch to fast catch-up while running, you may need to wait for the
    // divider to overflow.  This just creates additional delay, and the use case for these
    // switches is practically non-existent anyway; it's visible in the test simulation.
    assign AltReferenceTick = AltReferenceClockDiv == (AltTickFast ? FastTickTime : (CoreDiv + 1));
    // Don't need to count missed ticks because deviation is calculated in full at each test cycle*******
    // Enable at the divided clock frequency or when catching up, but not when delaying.
    // Don't run at the full reference clock
    wire CEOut;
    assign CEOut = ClkEn && !InternalDelay &&
                      (
                       // Normal speed if !CatchUp, else adjust
                       CatchUp ? AltReferenceTick : ReferenceTick // Saves no LUT
                      );
    assign ClkEnOut = CEOut;

    // Delay if CatchUp is negative i.e. we're ahead and clock needs to slow down.
    // In FastCatchup mode, flat out stop; otherwise the slow reference tick will take over 
    assign InternalDelay = Delay || (CatchUp < 0 && FastCatchup) || ((!CatchUp || TickHold) && TickSuppress);

    // FIXME:  Need a way to saturate, i.e. if behind, CatchUp is positive and max; if ahead,
    // CatchUp is negative and minimum.  These get recomputed either way, and the swing should
    // never be more than a few microseconds, but in case of more than 327us accumulated delay it
    // should just run full-speed catch-up until the next check.
    always_ff @(posedge Clk)
    if (Reset)
    begin
        ReferenceCycles <= ReferenceClock;
        // Trigger OneSecondSync
        CoreCycles <= CoreClock - 2;
        // The dividers don't strictly need to align with anything
        // OneSecondSync phase clears CatchUp, ExpectedCycles, and CoreExpectedCycles
    end
    else if (ClkEn)
    begin
        if (OneSecondSync)
        begin
            // One full second has passed.  Align the clocks.
            // Doesn't need to add to existing CatchUp because it's checking the whole count.
            // Include the current tick (this also saves a few LUTs by reusing the operation)
            CatchUp <= ReferenceClock - (ReferenceCycles + CEOut);
            ExpectedCycles <= ReferenceClock;
            CoreExpectedCycles <= CoreClock;
        end else if (CoreCycles == (CoreExpectedCycles >> TestFrequency))
        begin
            // Multiply the cycles per check times the number of tests, and subtract the actual
            // cycles passed.
            // The reference clock still ticks here, so capture CEOut 
            CatchUp <= (ExpectedCycles >> TestFrequency)
                       - (ReferenceCycles + CEOut); // The number of cycles that have passed
            ExpectedCycles <= ExpectedCycles + ReferenceClock;
            CoreExpectedCycles <= CoreExpectedCycles + CoreClock;
        end else
        begin
            // Decrement CatchUp unless the real reference clock ticks
            // CEOut  ReferenceTick  X
            //     0              0  0
            //     1              0 -1
            //     0              1  1
            //     1              1  0
            CatchUp <= CatchUp - CEOut + ReferenceTick;
        end
        // Manage the core clock divider
        // ReferenceTick ? 0 : ReferenceClockDiv + 1; // requires 1 more LUT
        ReferenceClockDiv <= (ReferenceClockDiv + 1) & {(ClockDivBits+1){~ReferenceTick}};
        AltReferenceClockDiv <= (AltReferenceClockDiv + 1) & {(ClockDivBits+1){~AltReferenceTick}};
        // Manage core clock cycle counter
        CoreCycles <= (CoreCycles + 1) & {($clog2(CoreClock)+1){~OneSecondSync}};
        // If it ticks on the output for any reason, count it
        // Resources:  subtracting the lower line instead raises from 164 LUT to 184 LUT
        ReferenceCycles <= ReferenceCycles + CEOut -
                          (ReferenceClock & {($clog2(ReferenceClock)+1){OneSecondSync}});
                          //((CoreCycles == CoreClock - 1) ? ReferenceClock : '0);
        // Suppress for half the reference clock period
        TickSuppress <= CEOut ? FastTickTime : (TickSuppress - (TickSuppress > 0));
        // Make sure to suppress an early tick when entering catch-up mode.
        // (Syntax saves 3 LUT vs 'if (CEOut) TickHold <= CatchUp == '0;')
        TickHold <= (CEOut & TickHold) | (!CatchUp);
    end
endmodule
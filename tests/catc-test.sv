// vim: sw=4 ts=4 et
// CATC test

module TestCATC
(
);
timeunit 1ns;
timeprecision 1ns;

logic clk = '0;
always #5 clk=~clk; 

wire Delay;
wire Fast;
logic ClkEn = '1;
logic ClkEnOut;
logic ClkEnOutStress;
logic Reset = '1;
bit [31:0] CoreClockCount;
bit [31:0] ReferenceClockCount;
bit [31:0] StressReferenceClockCount;

wire signed [15:0] ReferenceDifference;
bit signed [15:0] ReferenceDifferenceMax;
bit [23:0] TimeBehind;
bit [23:0] TimeBehindMax;

assign ReferenceDifference = ReferenceClockCount - StressReferenceClockCount;

RetroCATC #(.CoreClock(100000000))CATC
(
    .Clk(clk),
    .Delay('0),
    .FastCatchup('0),
    .Reset(Reset),
    .ClkEn(ClkEn),
    .ClkEnOut(ClkEnOut)
);

RetroCATC #(.CoreClock(100000000))CATCStress
(
    .Clk(clk),
    .Delay(Delay),
    .FastCatchup(Fast),
    .Reset(Reset),
    .ClkEn(ClkEn),
    .ClkEnOut(ClkEnOutStress)
);

assign Delay = CoreClockCount[13] & CoreClockCount[8];
assign Fast = '1;//CoreClockCount[14];

always_ff @(posedge clk)
begin
    if (Reset)
    begin
        ClkEn <= '1;
        Reset <= '0;
        CoreClockCount <= '0;
        ReferenceClockCount <= '0;
        StressReferenceClockCount <= '0;
        ReferenceDifferenceMax <= '0;
        TimeBehind <= '0;
        TimeBehindMax <= '0;
    end else
    begin
        CoreClockCount <= CoreClockCount + 1;
        ReferenceClockCount <= ReferenceClockCount + ClkEnOut;
        StressReferenceClockCount <= StressReferenceClockCount + ClkEnOutStress;
        TimeBehind <= ReferenceDifference? TimeBehind + 1 : '0;
        if (TimeBehind > TimeBehindMax)
            TimeBehindMax <= TimeBehind;
        if (ReferenceDifference > ReferenceDifferenceMax)
            ReferenceDifferenceMax <= ReferenceDifference;
    end
end

endmodule
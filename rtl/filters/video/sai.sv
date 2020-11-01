// vim: sw=4 ts=4 et
// SaI scaler
//
// This 2xSaI, superEagle, and Super2xSaI by Derek Liauw Kie Fa.  Bult from non-clean-room analysis
// of the original.  All static bit-shifts (which are just connecting wires), bitwise operations,
// and additions (carry chain).
//
// Basic operation:
//
//   The SaI scalers are doubling algorithms working pixel-by-pixel.  They operate on a matrix as
//   such:
//
//      -1 0 1 2
//  -1     E F
//   0   G A B I  =>  A'  A'''
//   1   H C D J      A'' A''''
//   2     K L
//
//   Consider the below block of pixels, one column wider and taller:
//
//       I E F J W
//       G A B K X  =>  A A B B
//       H C D L Y      A A B B
//       M N O P Z  =>  C C D D
//       R S T U V      C C D D
//
//   It is technically possible to compute the entire doubled image in one computation, in massive
//   parallel.  This requires high bandwidth to access the input data, which is resource intensive.
//
//   This scaler can operate in real time on video, or cores can use it to scale tiles, sprites, or
//   textures.

// Scalers take pixel-by-pixel input.  2xSaI buffers 4 lines; if it still needs its top-left pixel
// in the next clock, it stalls (use a skid buffer!).  The line base increments each iteration to
// wrap to the top.
//
//  0:  xxxxx
//  1:  xxxxx
//  2:  xxxxx
//  3:  xxxxx

//
//  Client:  Call scaler with attributes:  input/output resolution, color depth
//  for each pixel:
//    Client:  Provide one (1) pixel
//    Scaler:  Store pixel, if provided, in buffer for the next line;
//             ACK to Client if an ACK is still pending;
//             Process pixel and send to output
//
// Note that when scaling by a factor of n, the output buffer must hold n lines so as to output
// line by line to the display.  When scaling 320 to 640, that's 2,560 bytes.  An output filter
// buffers this.
module Scaler_2xSaI
#(
    parameter InputWidth = 320 // Sega Genesis 320x240; SNES can be 512x448
)
(
    ISysCon SysCon,
    IWishbone.Target Client,
    IWishbone.Initiator VideoOut // 64 bit = 4 16-bit pixels
);

    logic pixelDepth565;
    // Set based on if pixel depth reset to 565 or 555
    wire [15:0] colorMask = {pixelDepth565 ? 8'hf7 : 8'h7b, 8'hde};
    wire [15:0] lowPixelMask = {pixelDepth565 ? 8'h08 : 8'h04, 8'h21};
    wire [15:0] qColorMask = {pixelDepth565 ? 8'he7 : 8'h73, 8'h9c};
    wire [15:0] qLowPixelMask = {pixelDepth565 ? 8'h18 : 8'h03, 8'h63};

    // XXX:  This allows up to 512 width and height
    logic [8:0] inputWidth;
    logic [8:0] inputHeight;
    // Doubling
    wire [9:0] outputWidth = {inputWidth, 1'b0};
    wire [9:0] outputHeight = {inputHeight, 1'b0};

    logic [8:0] x_coord;
    logic [8:0] y_coord;
    logic [8:0] buffer_x;

    // VRAM buffer, 4 lines, using 320x240 Sega Genesis as the upper bound
    // TODO:  Attach this to a shared memory module that can output vertical sets of 4 pixels,
    // allowing us to use the same memory resource for all available filters.
    logic [15:0] vBuffer [0:3][0:InputWidth-1];
    logic [2:0] bufferBase;

    // See 2xSaI original source for reference on these two functions.  Shift functions are just
    // running wires to lower output bits, so these are highly-efficient and parallel.  Additions
    // consume the most resources here.
    function logic[31:0] SaI_Interpolate(input logic [31:0] A, input logic [31:0] B);
        return (A == B) ? A
             : (  ((A & {colorMask, colorMask}) >> 1)
                + ((B & {colorMask, colorMask}) >> 1)
                +  (A & B & {lowPixelMask, lowPixelMask})
               );
    endfunction
    
    function logic[31:0] SaI_QInterpolate
    (
        input logic [31:0] A,
        input logic [31:0] B,
        input logic [31:0] C,
        input logic [31:0] D
    );
        var integer x, y;
        x =   ((A & qColorMask) >> 2)
            + ((B & qColorMask) >> 2)
            + ((C & qColorMask) >> 2)
            + ((D & qColorMask) >> 2);
        y =   (((A & qLowPixelMask)
            + (B & qLowPixelMask)
            + (C & qLowPixelMask)
            + (D & qLowPixelMask)) >> 2) & qLowPixelMask;
        return x + y;
    endfunction

    // Truth table:
    // A=C A=D B=C B=D   R
    // 0   0   0   0     0
    // 0   0   1   0     0
    // 0   0   0   1     0
    // 0   0   1   1     1
    // 1   0   x   0     0
    // 1   0   x   1     0
    // 0   1   0   x     0
    // 0   1   1   x     0
    // 1   1   x   x     -1
    // Note in the original, GetResult1 and GetResult2 take a fifth input but do nothing with it,
    // and GetResult2 = 0 - GetResult1.  For GetResult2, caller just inverts the returned bits.
    //
    // The 4 GetResult additions can be seen as 4 one-hot flags, e.g.
    //
    //   {r1p,r2p,r3p,r4p,r1n,r2n,r3n,r4n}
    //
    // $countones(r[7:4]) can then be compared to $countones(r[3:0]).
    function logic[1:0] GetResult
    (
        input logic [31:0] A,
        input logic [31:0] B,
        input logic [31:0] C,
        input logic [31:0] D
    );
        return {
                (A == C) || (A == D), // -1
                ( !((A == C) && (A == D)) && (B == C) && (B == D)) // +1
               };
    endfunction

    enum
    {
        idle, // No job
        init,       // Begin receiving request register
        startFill,  // Receiving First 3 lines
        startLine,  // Receiving first 3 pixels on the line
        encode,     // Encoding an output
        complete    // Finishing any pending ACKs
    } currentState, nextState;
    logic [1:0] requestStage;

    always_comb
    begin : nextStateLogic
        nextState = currentState;
        unique case (currentState)
            // Begin init on first packet
            idle:  if (Client.RequestReady()) nextState = init;
            // Leave init when receiving 
            // FIXME:  should move to opening the video device with proper resolution
            init:  if (Client.RequestReady() && requestStage == 3) nextState = startFill; 
        endcase
    end

    // There is no read request, so WE doesn't exist.
    always_ff @(posedge SysCon.CLK)
    if (SysCon.RST)
    begin
        // Go idle
        currentState <= idle;
        requestStage <= '0;
    end else case (currentState)
        idle, init:
            if (Client.RequestReady())
            begin
                case (requestStage)
                0:
                begin
                    // Initial packet is mm.. ..ww wwww wwww, mode and width
                    // mm=00 555, mm=01 565, mm=10 24 bit 888 // FIXME:  Will need to improve this
                    pixelDepth565 <= {Client.GetRequest()}[14];
                    inputWidth <= {Client.GetRequest()}[8:0];
                    x_coord <= '0;
                    y_coord <= '0;
                    buffer_x <= '0;
                    // bufferBase <= '0; //Doesn't actually matter
                    requestStage <= 1;
                end
                1:
                begin
                    inputHeight <= {Client.GetRequest()}[8:0];
                    requestStage <= 2;
                end
                2:
                begin
                    //outputWidth <= {Client.GetRequest()}[9:0]; // 2x
                    requestStage <= 3;
                end
                3:
                begin
                    //outputHeight <= {Client.GetRequest()}[9:0]; // 2x
                    requestStage <= 0;
                end
                endcase
                Client.SendResponse('0);
            end
        // TODO:  Give VideoOut an initialization statement on our output bpp and 
        startFill, startLine, encode:
            begin
            end
    endcase
endmodule
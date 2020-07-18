// vim: sw=4 ts=4 et
// PSRAM HyperRAM controller
//
// This can control a single HyperRAM PSRAM device and present it as SRAM.  HyperRAM PSRAM
//
//  - Operates at double data rate
//  - Has low latency (166MHz, 6 clock latency, 1 clock transfer, 42ns)
//  - Can operate in linear burst mode up to 128-bytes, perfect for OneCycleCache fetches
//  - Uses a simple protocol similar to SDRAM
//    - CS# transitions high to low
//    - 48 bits of Command/Address are written over 6 cycles
//    - Data is returned double-data-rate on the 8 bit bus (386ns to transfer 128 bytes)
//    - CS# transitions low to high
//
// Special notes about the protocol for 128Mb components:
//
//  - The 128Mb die is two 64Mb dies
//  - Command register CA35 (Address[22]) selects which die (the top half is in the upper die)
//  - Deep power down only affects one die, based on CA35
//  - Fixed latency mode only!
//  - Linear burst cannot cross dies
//  - Input capacitance is doubled, so clock latency to data strobe is affected
//
// To handle this, the controller reads configuration registers 0 and 1, notating the following:
//
//  - CR0[12:8] row address bit count plus CR0[7-4] column address bit count, total address width.
//  - CR0[15:14] die ID.  Should be 0 on single-die devices with top address bit set.
//  - If die ID is 1 at upper half, we have MCP; never linear burst into an MSB toggle.
//  - CR1[3:0] reads 0000 to indicate HyperRAM
//
// Also note recommended T[cms] is 4µs, which is 664 ticks at 166MHz, 400 ticks at 100MHz, etc..
// After initiating linear burst, data comes once per differential clock tick (at 166MHz, this is
// 332MHz of clock crossings), which allows us to transfer:
//
//  - 3 ticks command register write
//  - 6 ticks initial latency
//  - 6 ticks of 2x latecny if RWDS is driven high by the component (always on MCPs e.g. 128Mb)
//  - 1 tick per 2 bytes of data
//
// …649 × 2 = 1,298 bytes of data in one T[cms] period on a 166MHz device; 770 bytes per 100MHz.
//
// These figures are for a device temperature of 85°C, and the refresh interval is longer when
// cold.   Restricting to these maximums ensures device integrity.  Restricting to 1,298 bytes
// transferred in one burst gives 2.26% overhead to overall data transfer rate; restricting to
// 1,024 bytes gives a 2.85% overhead.  Fetching only a single 128 byte cache line in a transaction
// incurs a 19.0% overhead, and so pre-fetch and buffering is highly recommended.
//
// Pre-fetch and buffering in this controller use one simple dual port BRAM as a buffer.  Data
// transactions pull to the next 1,024-byte boundary and note completeness in a direct-mapped
// 32-entry table.  A 4-entry 4-way associative table indicates the upper bits of the address.
// Any incomplete 128-byte block in a 1024-byte block is fetched when the controller is not
// otherwise busy accessing RAM, or on demand.  Reads draw from this buffer if present, rather
// than from HyperRAM, acting as a first-stage prefetch; writes write to this buffer and mark it
// dirty, writing back when it becomes the second-least-recently-used block.
//
// This allows tracking incomplete reads and completing them on-demand, while also reading
// immediately with no unnecessary latency by starting in the middle and breaking off the read
// if HyperRAM device access becomes necessary to service a new request.
//
// Note that for even the PSX, transfer should be 2.45x as fast as the CPU's bus bandwidth. This
// will easily outrun systems implementable on 2020 FPGA fabric, and otherwise SDRAM is a better
// option in terms of cost.

interface IHyperRAM;
    logic CS;
    logic CK; // Clock, external
    logic CKN; // Clock negative, CS#
    // DQ
    logic [7:0] SDin;
    logic [7:0] SDout;
    logic SRWDSin, SRWDSout;
    logic Reset;

    // Port on the controller
    modport Controller
    (
        output CS, // chip select
        output CK, // Disabling the clock is part of the protocol
        output CKN,
        output .Dout(SDin),
        input .Din(SDout),
        output .RWDSout(SRWDSin),
        input .RWDSin(SRWDSout),
        output Reset
    );

    // HyperRAM chip's port
    modport Component
    (
        input CS,
        input CK,
        input CKN,
        input .Din(SDin),
        output .Dout(SDout),
        input .RWDSin(SRWDSin),
        output .RWDSout(SRWDSout),
        input Reset
    );
endinterface

// XXX:  Should this run on a 2x clock and leave the inversion and timing to outside sources?
module RetroHyperRAM
#(
`ifdef HYPERRAM_BLOCK_BUFFER // Remove these in favor of generate statements for features
    parameter bit BlockBuffer = 0, // If 1, use a 4KiB BRAM for a buffer
`endif
`ifdef HYPERRAM_DETECT_DEVICE
    parameter bit DetectDevice = 0, // Read pertinent information from ID registers, notably device size
`endif
    parameter int AddressBusWidth = 23 // 128Mb x 8 x 2 (DDR so it's an 8 bit bus twice per clock)
)
(
    input logic Clk, // HyperRAM reference clock
    input logic ClkN, // Negative clock
    RetroMemoryPort.Target Initiator,
    IHyperRAM.Controller HyperRAM
);

    // Initial implementation only communicates bluntly with the device on assumption of its size.
    // It uses wrapped 128-byte reads.
    uwire [AddressBusWidth-1:0] RowMask;
    uwire [AddressBusWidth-1:0] ColumnMask;

    // Store a copy of the ID register 0 here
    logic [15:0] IDR0 = '1;
    assign ColumnMask = (1 << IDR0[7:4]) - 1;
    assign RowMask = ((1 << IDR0[12:8]) - 1) << IDR0[7:4];

    // ====================
    // = Command register =
    // ====================
    union {
        bit [5:0][8:0] Bytes;
        bit [47:0] Register;
    } Command;

    // Read-Write 1=read 0=write
    logic Read = '1;
    assign Command.Register[47] = Read;

    // Address space 0=RAM 1=Register
    logic AS;
    assign Command.Register[46] = AS;

    // Burst type, 1=linear, 0=wrapped
    logic BurstType = '1;
    assign Command.Register[45] = BurstType;    

    // the address to command.  Note bits 15:3 are reserved on the bus
    logic [AddressBusWidth-1:0] CommandAddress;
    assign Command.Register[44:(44-AddressBusWidth)+15] = '0; // top of the address bus is zero
    assign Command.Register[(44-AddressBusWidth)+15-1:16] = CommandAddress[AddressBusWidth-1:3];
    
    assign Command.Register[15:3] = '0; // Reserved bits

    assign Command.Register[2:0] = CommandAddress[2:0];

    // ====================
    // = State Management =
    // ====================
    // Timing cycle if executing a command; 0 if idle
    bit [3:0] T = 'h6;
    bit Recovery = '1; // If 1, set to 0 if T == 0, else decrement T.
    // When sending a command, this indicates which byte of Command to send
    bit [2:0] CommandIndex;
    
    bit [1:0] ActiveTask = '0;
    
    bit CS = '1;
    assign HyperRAM.CS = CS;

    // =========================
    // = Memory Port Interface =
    // =========================
    // Come up unready for anything
    logic Ready = '0;
    logic DataReady = '0;
    
    assign Initiator.Ready = Ready;
    assign Initiator.DataReady = DataReady;

    // Active Task
    task SendCommand();
        ActiveTask[0] = '1;
        
        // Drive CS low during clock idle 
        if (CS == 1)
        begin
            CommandIndex <= 'h5;
        end
    endtask

    generate
        genvar i;
        var clks [0:1] = {Clk,ClkN};
        for (i=0; i<2; i++)
        begin
            // DDR protocol blocks
            always_ff @(posedge clks[i])
            if (ActiveTask[0])
            begin
                // Task 0:  Transmit
            end
        end
    endgenerate

    always @(posedge Clk)
    if (|ActiveTask == '0)
    begin
        if (Recovery)
        begin
            // Just dec T to zero, then clear the Recovery bit.
            // No commands until then.
            T <= (T == 0) ? '0 : T - 1;
            Recovery <= (T == 0) ? '0 : '1;
        end
        else if (IDR0[15] == '1)
        begin
            // only 00 and 01 are valid die addresses, so bit 15 should always be 0
            if (T == '0)
            begin
                //Set the top byte to 0xE0, the rest to 0
                Read = '1;
                AS <= '1;
                BurstType <= '1;
                CommandAddress <= '0;
                // TODO:  Initiate transaction
                // RWDSin is valid as normal on a register read; it's only ignored on register write.
                T <= '1;
                
            end
            else if (T == '1)
            begin
            end
        end
    end
    
endmodule
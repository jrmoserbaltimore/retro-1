// vim: sw=4 ts=4 et
// Cartridge cache
//
// This caches data.  The controller must:
//
//  - Raise Delay for CATC on a miss (Cache.DataReady == 0 when reading)
//  - Write complete, aligned 128 bytes of cache at once
//  - Extend the address width to include the bank number as MSB
//
// Upon miss, the controller will delay the core; this occurs between standard reference clock
// ticks, and the catch-up counter only increments on standard ticks, so CATC will count the tick.
//
// Cache and Storage must be on the same clock.

// TODO:  Set-associative cache e.g. [CacheIndexBits-1:0][TagLength-1:0][Associativity-1:0]
// TODO:  Way Cache for set-associative caches
module RetroBasicCache
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 1, // Bytes XXX: Needed here?
    parameter int CacheLineBits = 7, // 128-byte cache lines
    parameter int CacheIndexBits = 7 // 16Kio cache, 4 blocks BRAM
)
(
    IRetroMemoryPort.Target Cache,
    IRetroMemoryPort.Initiator Source, // The thing to cache
    IRetroMemoryPort.Initiator Storage // Use this to back the cache
);
    //                         [    Tag      ]   [    Index   ]   [   Offset  ]
    localparam int TagLength = AddressBusWidth - CacheIndexBits - CacheLineBits; 
    bit [CacheIndexBits-1:0][TagLength-1:0] CacheVirtTable;
    bit [CacheIndexBits-1:0] CacheValid;
    bit [CacheIndexBits-1:0] CacheDirty;
    // Count how many bits we've copied in/out
    bit [CacheLineBits-1:0] CachePutCounter = '0;

    wire [CacheIndexBits+CacheLineBits-1:0] PhysicalAddress;
    wire [CacheIndexBits-1:0] Index;
    wire [TagLength-1:0] Tag;

    wire CacheHit;

    // From the index down to the offset
    assign Index = Cache.Address[CacheIndexBits+CacheLineBits-1:CacheLineBits];
    assign Tag = Cache.Address[AddressBusWidth-1:CacheIndexBits+CacheLineBits];

    // Direct mapped, so the index is not remapped
    assign PhysicalAddress = Cache.Address[CacheIndexBits+CacheLineBits-1:0];

    // When there's a cache miss, DataReady remains 0 
    assign Storage.Dout = Cache.Din;
    assign Cache.Dout = Storage.Din;
    assign Storage.Write = Cache.Write && CacheHit;

    // DataReady raised on a cache hit
    assign CacheHit = (CacheValid[Index] && CacheVirtTable[Index] == Tag);
    assign Cache.DataReady = CacheHit && Storage.DataReady; 

    // This has to recognize an ongoing cache miss, write back to the source if dirty, and
    // retrieve a cache line from the source.
    //
    // It also needs to periodically write back dirty cache lines.
    always_ff @(Cache.Clk)
    begin
        if (Cache.Access)
        begin
            if (!CacheHit && Source.Ready)
            begin
                // Increment
                CachePutCounter <= CachePutCounter + '1;

                if (CacheValid[Index] && CacheDirty[Index])
                begin
                    // Need to write back first
                    Source.Address[CacheLineBits-1:0] <= CachePutCounter;
                    Source.Access <= '1;
                end
                else
                begin
                end
            end
        end
    end
endmodule
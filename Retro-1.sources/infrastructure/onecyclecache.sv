// vim: sw=4 ts=4 et
// Cartridge cache
//
// This caches data.  The controller must:
//
//  - Raise Delay for CCCU on a miss (Cache.DataReady == 0 when reading)
//  - Write complete, aligned 128 bytes of cache at once
//  - Extend the address width to include the bank number as MSB
//
// This only works when the reference clock is a multiple of the core's standard reference clock.
// Upon miss, the controller will delay the core; this occurs between standard reference clock
// ticks, and the catch-up counter only increments on standard ticks, so CCCU will count the tick.
//
// Cache and Storage must be on the same clock.

module RetroOneCycleCache
#(
    parameter int AddressBusWidth = 16,
    parameter int DataBusWidth = 8,
    parameter int CacheLineBits = 7,
    parameter int CacheIndexBits = 7 // 16Kio cache, 4 blocks BRAM
)
(
    RetroMemoryPort.Target Cache,
    RetroMemoryPort.Initiator Storage // Use this to back the cache.  Must be single-cycle.
);
    //                         [    Tag      ]   [    Index   ]   [   Offset  ]
    localparam int TagLength = AddressBusWidth - CacheIndexBits - CacheLineBits; 
    bit [CacheIndexBits-1:0][TagLength-1:0] CacheVirtTable;
    bit [CacheIndexBits-1:0] CacheValid;
    // 
    bit [CacheIndexBits-1:0] CachePutCounter;

    // The cache is always ready
    assign Cache.Ready = '1;
    // Setup data.  Unnecessary values will be ignored.
    assign Storage.Dout = Cache.Din;
    assign Cache.Dout = Storage.Din;
    assign Storage.Write = Cache.Write;

    // Directly translates address to a cache entry.  The cache size is 2**(Index+Offset)
    always_comb
    begin
        var bit [CacheIndexBits+CacheLineBits-1:0] PhysicalAddress;
        var bit [CacheIndexBits-1:0] Index;
        var bit [TagLength-1:0] Tag; 
        // From the index down to the offset
        Index = Cache.Address[CacheIndexBits+CacheLineBits-1:CacheLineBits];
        Tag = Cache.Address[AddressBusWidth-1:CacheIndexBits+CacheLineBits];
        
        // Direct mapped, so the index is not remapped
        PhysicalAddress = Cache.Address[CacheIndexBits+CacheLineBits-1:0];
        // Setup addressing
        Storage.Address = PhysicalAddress;

        if (Cache.Access)
        begin
            if (!Cache.Write)
            begin
                // Reading from cache
                if (
                    !CacheValid[Index]
                    || CacheVirtTable[Index] != Tag
                   )
                begin
                    // Cache miss
                    Cache.DataReady = '0;
                    Storage.Access = '0;
                end
                else begin
                    // hit, virtual address translation
                    Cache.DataReady = '1;
                    Storage.Access = '1;
                end
            end
            else // Cache.Write
            begin
                // Immediately do the accounting
                CacheValid[Index] = '1;
                CacheVirtTable[Index] = Tag;
                // Access storage
                Storage.Access = '1;
                Cache.DataReady = '0;
            end
        end
        else
        begin
            Storage.Access = '0; // Cache.Access
            Cache.DataReady = '0;
        end
    end
endmodule
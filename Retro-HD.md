Retro-HD
========

This document explains the Retro-HD standard for updating graphics and sound
on Nintendo Entertainment System and Game Boy Color.

# What is Retro-HD?

Retro-HD describes conditions for modification of hardware output—PPU and
APU—without modification of the underlying game code or system's execution
timing.

# Basic Retro-HD Standard

## Data

*XXX:  This is way more complex than the GB Colorizer*

Data approaches can give data describing the desired outcome.  This data
indicates things like APU loads, memory state, PPU access, and so forth.

```
// Example NES HD-Audio

.Audio(2A03-HD);

// if 0xCF00 were the entry point where the game jumps to play music
.If(RomVersion == 1.0)
  .Set($EntryAddr)(0xCF00);
.EndIf

// A table of music, i.e. imported from files.
// For 2A03-HD, compatible with FamiTracker files
.MusicTable
[
  0xBADC = WoodMan,
  0xBBA0 = FlashMan,
  0xBC00 = MetalMan
];

.OnExecute($EntryAddr)
[
  // Attributes
  .Interrupt
  [
    // Upon interrupt, pause code until RTI, then resume where left off
    Interrupt(RTI),
    PauseOnFollow(0xD0A0), // Music routine not running after following branch
    PauseOnAddress(0xD0FE), // Music routine paused after executing this addr
    Procedure(Data) // this is a data procedure
  ]
]
{
  // There's a table in the ROM, and the ROM's sound engine uses this to look
  // up a song based on a song ID when entering $EntryAddr
  .Set($Song)($TableAddress + $SongIDAddress);

  // Block all sound channels
  .BlockChannel(All);

   // From this table, 
  .Play(MusicTable)($Song)
  [
    // Pass through original if no entry
    NoEntry(Pass)
  ];
}

// Add another to trap SFX
```

Something like the above has to be compiled into a data file.  Data packs can
do several things:

* Identify entry into a certain address, such as a music or SFX routine
* Identify an interrupt exiting the address
* Identify when the music routine is/is not running
* Block/enable audio channels
* Play a FamiTracker file
* Pass the real APU output if no data is in the music table

Identifying when the audio procedure isn't executing on the NES allows the
hardware to wait on the next sound event, essentially emulating audio lag.
There's no reason NES-HD Audio can't be used with Game Boy games, so long as
the data file indicates the correct code events.

## Code Execution

*XXX:  Is this even reasonable?  It'll work, but a non-code approach may be a
better option.*

For many implementations, executable code can readily describe enhancements
by accessing alternate hardware.

Consider an NES HD-Audio extension providing additional sound channels. A
Retro-HD HD-Audio pack can indicate code to execute when the CPU jumps to a
certain address.  The 2A03 would execute the game code; a separate CPU would
instead execute the indicated code clock-for-clock synchronous with the 2A03.
The NES APU would essentially respond to this code and ignore access from the
2A03.

```
// Example NES HD-Audio

.Audio(2A03-HD);

// if 0xCF00 were the entry point where the game jumps to play music
.If(RomVersion == 1.0)
  .Set($EntryAddr)(0xCF00);
.EndIf

.OnExecute($EntryAddr)
[
  // Attributes
  .Interrupt
  [
  	Interrupt(RTI), // Pause code until RTI, then resume where left off
	ExitOnFollow(0xD0A0), // exit if CPU takes a branch here
	ExitAddress(0xD0FE), // exit if this address is executed
	Procedure(Code) // this is a code procedure
  ]
]
{

  // 6502 code goes here:
  //  - Read music pointer
  //  - Read music offset (where positioned)
  //  - Begin executing APU code
  //    
  // Can interrupt code with e.g.:
  // .PassChannel(Square1);
  // .BlockChannel(Square1);
  // to enable and disable the APU channels coming from the game itself

  // .Call(Stage1Music)
}

// No arguments, just a jump target
.Subroutine(Stage1Music)
{
  // Nothing here so just pass original
  .PassChannel(All);
}
```

The above sort of code would have read access to the 6502 registers and
memory, but no write access.  Special notation allows use of this data:

```
  LDA .Host($BC00)   ; load
  LDY .Host(A)       ; load from host's Y register
```

Implementations must *not* allow such code to modify the host memory or
registers in any way; any I/O in any way affecting the state of program
execution;, or timing of any sort.

# Game Boy

## Color Profile

For Game Boy games, a data pack indicates sprite loads and conditions, and
gives palettes to apply.  This allows running regular Game Boy games without
modification with the full Game Boy Color palette capabilities.

Sprites are indicated by two-byte checksum calculated as such:

1.  Begin at line `l=0` of an 8x8 tile, 16-bit accumulator `a=0`
2.  For each line `l` of 16 bits
  1.  Rotate `a` left one bit, with the MSB becoming LSB (`a = a << 1`)
  2.  Add line `l` to `a`
3.  The resulting 16-bit value is your sprite checksum.

# Game Boy color pack

A color pack specifies color names, sprites, and objects made of sprites.
Colors are 15-bit Game Boy Color palette colors, bits 0-4 red, bits 5-9 green,
bits 10-14 blue, bit 15 ignored.

Only 8 back ground and 8 object palettes may be in use at any given time.  A
sprite may only use colors from a given palette.

Color packs handle this simply:  a palette is four colors to replace the four
monochrome colors.  The pack defines a palette as a set of monochrome palettes
and coresponding color palettes.

Objects are listed as collections of sprites which share the same palette, and
are assigned the palette.  The emulator or hardware implementation identifies
a matching palette and uses that, or replaces an unused palette.  Typically,
the same BG or OBJ palette will be used unless two objects originally using the
same monochrome palette are using different color palettes.

This restricts palettes to only what the original hardware, and thus a modified
program, could produce.

```
.Colors
{
  White = 0x7fff;
  DarkBrows = 0x0064,
  Sky = 0x7a89;
  Water = 0x72e6;
  Tree1 = 0x27ac;
  Tree2 = 0x0300;
  Tree3 = 0x0180;
  Earth1 = 0x36fc;
  Earth2 = 0x2a38;
  Earth3 = 0x1151;

  Sky2 = 0x6f77
  Sky3 = 0x6eed;
  Sky4 = 0x6980;
  Sky5 = 0x61e0;
  Black = 0x0000;
  Tree1a = 0x1724;
  Tree2a = 0x0280;
  Tree3a = 0x0100;
  Tree1b = 0x16a0;
  Tree2b = 0x0200;
  Tree3b = 0x0080;

}
.Palettes
{
  Tree =
  {
    0123:{White,Tree1,Tree2,Tree3},
    # Flashing when paused
    3012:{Sky2,Tree1a,Tree2a,Tree3a},
    3123:{Sky3,Tree2a,Tree2b,Tree3b}
}

.Sprites
{
  Tree0 = 0xabff;
  Tree1 = 0xc19a;
  Tree2 = 0xd5b1;
  # ...
}

.Objects
{
  Tree =
  {
    Tree0,
    Tree1,
    Tree2
  }
  DefaultPalette = Tree;
}
```
## Audio Pack

Same as NES.

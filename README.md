This is the core of Moonset Retro.

# Developing Cores for the Retro

Cores should appear in their own repository separate from Retro.  To build a
Retro configuration, create a new `git` repository with the following
structure:

```
./retro/
./cores/mycore/
```

Check out this repository as a submodule at the `retro` subdirectory, and your
core as a subdirectory of `cores`:

```
git submodule --name retro [retro-repo] retro
git submodule --name mycore [mycore-repo] cores/mycore
```

Then create a toplevel module that incorporates the `retro` and `mycore`
toplevels together.  A similar approach can integrate `mycore` with other
platforms, such as MiSTer.

`RetroConsole` will connect a high-latency system RAM DMA IOMMU port, two
HyperRAM ports, cartridge port, controller port, AV port, and expansion port to
the core.  `RetroConsole` can snoop the controller port to trap user commands,
and can access the HyperRAM and cartridge when the core is not running.

`RetroConsole` will instantiate a small RISC-V core running RetrOS to control
the console.  RetrOS sends commands to the core, including commands requesting
information about the core.  The core can report:

* Core name
* Creator
* License
* Build version
* System implemented
* Configuration options and allowable values
  * Common file extensions for options expecting files
  * File header magic numbers for valid files
* Generic information to display
  * e.g. Results of a file header read (fields and their values, or invalid)

When RetrOS initiates boot, the core reads its configuration options.  Files
are given as offsets in system RAM; the IOMMU maps these offsets to DDR
addresses.  When not present in memory, the IOMMU faults to RetrOS, which loads
content into memory and updates IOMMU mappings.  The core determines whether to
read from memory or cartridge bus via its cartridge controller.

RetrOS can also:

* Pause or reset the core
* Affect audio-video out
* Modify real-time configurable options
* Trigger real-time actions exposed by the core
  * Request a complete state dump from the core (save states)
  * Request save file dump from the core
  * Request save file load to the core
  * Enable, disable, and alter cheat engine entries

Each of the above pieces of information comes from the core, and RetrOS
dynamically builds a menu of configuration options and core-specific features.
In effect, each core is its own software driver.

Upon FPGA configuration, RetrOS loads a core initialization file, if present,
so this information need not be embedded in the configuration itself.  This
allows translation packs.

## Multi-Core Configurations

You can provide a core which itself connects to several other cores,
multiplexing them together.  Toplevel modules for each core should be unique
for this reason.  Retro can probe for a core count and retrieve metadata from
each core.

# Targets

* Moonset Retro-1 (Spartan-7)
* Digilent Arty Z7-20 (Zynq-7020)

Primary target is the Moonset Retro platform.  The Arty-Z7 development board
allows rapid prototyping and testing without designing and implementing a
production hardware platform.

The Retro-1 aims to provide a low-cost, mass-production, modular platform below
the cost of a dev board, fully integrated with hardware facilities, and
expandable with low-cost passive ports or moderate-cost processing modules.
The base target should run everything up to and including FPGBA, essentially
anything that can run on MiSTer.  The programmable logic is roughly 50% more
dense than the Cyclone V, and should support larger systems than possible on
the DE10-nano at a similar price.

## Integration

You can integrate the Retro core into other hardware in the manner above, such
as to produce a USB or PCI-Express peripheral.

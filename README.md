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
toplevels together.  Retro has a port to connect to a core.

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

# YaPB for FreeCS

A QuakeC port of [YaPB](https://github.com/yapb/yapb) (Yet another POD Bot) for FreeCS/FTEQW.

This is a 1:1 port of YaPB's bot AI system, reimplemented as a Nuclide `ncBot` subclass in QuakeC. It replaces the basic Nuclide bot AI with YaPB's sophisticated decision-making, combat, and navigation systems.

## Status

Work in progress. Porting ~34,500 lines of C++ to QuakeC.

## Architecture

- Extends `ncBot` from Nuclide's botlib
- Uses Nuclide's waypoint/pathfinding system
- Uses FTEQW's `input_buttons`/`input_movevalues`/`input_angles` for bot control
- Loads YaPB config files via `fopen`/`fgets`

## Original License

YaPB is MIT licensed by the YaPB Project Developers.

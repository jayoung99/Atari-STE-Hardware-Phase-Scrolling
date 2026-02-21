# Project Title

Atari STE Hardware Phase Scrolling

## Description

Hardware scrolling routines and demos for the Atari STE using the Shifter and Blitter chips.

Phase Scrolling is my take on the Scanwalk and Scanwrap methods of tile-based infinite scrolling.

The project is coded entirely in 68000 assembler and tested with Hatari 2.6.1 and on a real STE with TOS 1.62.

## Getting Started

Phase Scroll Methodology and an overview of Infinite Scrolling, Scan Walk and Scan Wrap techniques is documented extensively in the included text files:

- HPSCROLL.TXT - Horizontal Scroll (Scan Walk)
- VPSCROLL.TXT - Vertical Scroll (Scan Wrap)

Fully commented source code files:

- HPSCROLL.S - Horizontal Scroll
- VPSCROLL.S - Vertical Scroll

Prebuilt executables HPSCROLL.TOS and VPSCROLL.TOS are provided.  Launch from TOS to run.

Within each program the following keys are recognized:

- ESC - Exit the program back to Desktop
- SPACEBAR - Reverse direction of the scrolling
- 0 - Pause scrolling
- 1 - Scroll speed 1
- 2 - Scroll speed 2
- 4 - Scroll speed 4
- 8 - Scroll speed 8

Assembling the source is also possible.

Vasm 1.9e was used to assemble the executables with the commands:
```
vasm -m68000 -Ftos -devpac -nosym -o HPSCROLL.TOS HPSCROLL.S
vasm -m68000 -Ftos -devpac -nosym -o VPSCROLL.TOS VPSCROLL.S
```

### Dependencies

The programs require an Atari STE, MegaSTE or emulator such as Hatari set to STE.

If assembling from source, vasm is required or if assembling on STE hardware, devpac 3 should work.

### Installing

Copy the executables HPSCROLL.TOS and VPSCROLL.TOS somewhere on your Atari storage device or on a local PC folder which can be used by the Hatari emulator.

### Executing program

Double-click on the file HPSCROLL.TOS or VPSCROLL.TOS from the Atari Desktop.

## Authors

Jeffrey Young aka TheNameOfTheGame on atari-forum where I can be contacted via pm or email.

## License

Use this code as you see fit.

Copying this archive is allowed, provided *all* files are included and were not modified.


## Acknowledgments
Amiga 8-Way-Tile-Scroller by Gonzo which was the inspiration for this project:
https://aminet.net/package/dev/asm/8wayscroller

STE machine check routine adapted from the Leonard init method:
http://leonard.oxg.free.fr/articles/multi_atari/multi_atari.html

Timer B playfield split method adapted from simonsunnyboy/paradize routine:
https://paradize.final-memory.org/downloads/ahcc/ste_playfld.zip

Timer B playfield split optimization suggestions by evil and thomas3 at atari-forum:
https://atari-forum.com/viewtopic.php?p=489188#p48918

Timer B playfield split end-of-scanline sync method from Klapauzius at atari-forum:
https://atari-forum.com/viewtopic.php?p=210237#p210237        

Hatari team for the indispensable and ever useful Hatari emulator:
https://www.hatari-emu.org/

Big thank you to Eero Tamminen who is always available and patient with my Hatari questions and requests over at atari-forum.
```
'########:'##::::'##::::'###::::'##::: ##:'##:::'##::::'##:::'##::'#######::'##::::'##:'####:
... ##..:: ##:::: ##:::'## ##::: ###:: ##: ##::'##:::::. ##:'##::'##.... ##: ##:::: ##: ####:
::: ##:::: ##:::: ##::'##:. ##:: ####: ##: ##:'##:::::::. ####::: ##:::: ##: ##:::: ##: ####:
::: ##:::: #########:'##:::. ##: ## ## ##: #####:::::::::. ##:::: ##:::: ##: ##:::: ##:: ##::
::: ##:::: ##.... ##: #########: ##. ####: ##. ##::::::::: ##:::: ##:::: ##: ##:::: ##::..:::
::: ##:::: ##:::: ##: ##.... ##: ##:. ###: ##:. ##:::::::: ##:::: ##:::: ##: ##:::: ##:'####:
::: ##:::: ##:::: ##: ##:::: ##: ##::. ##: ##::. ##::::::: ##::::. #######::. #######:: ####:
:::..:::::..:::::..::..:::::..::..::::..::..::::..::::::::..::::::.......::::.......:::....::
```

Screen graphics by Simon Phipps (c) Core Design and are included solely for
demonstration purposes. Thanks Simon for so many great Atari ST games of yesteryear.


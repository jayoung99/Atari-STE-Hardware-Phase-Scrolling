# Project Title

Atari STE Hardware Phase Scrolling

## Description

A horizontal hardware scrolling routine and demo for the Atari STE using the Shifter and Blitter chips.

Phase Scrolling is my take on the Scanwalk method of tile-based infinite scrolling.

The project is coded entirely in 68000 assembler and tested with Hatari 2.6.1 and on a real STE with TOS 1.62.

## Getting Started

Phase Scroll Methodology is documented extensively in the included text file PHSCROLL.TXT along with overviews and analysis of Infinite and Scanwalk scrolling techniques.

Fully commented source code contained in PHSCROLL.S.

The prebuilt executable PHSCROLL.TOS is provided.  Launch from TOS to run the demo program.

Within the program the following keys are recognized:

- ESC - Exit the program back to Desktop
- SPACEBAR - Reverse direction of the scrolling
- 0 - Pause scrolling
- 1 - Scroll speed 1
- 2 - Scroll speed 2
- 4 - Scroll speed 4
- 8 - Scroll speed 8

Assembling the source is also possible.

Vasm 1.9e was used to assemble the executable with the command line:
```
vasm -m68000 -Ftos -devpac -nosym -o PHSCROLL.TOS PHSCROLL.S
```

### Dependencies

The program requires an Atari STE, MegaSTE or emulator such as Hatari set to STE.

If assembling from source, vasm is required or if assembling on STE hardware, devpac 3 should work.

### Installing

Copy the executable PHSCROLL.TOS somewhere on your Atari storage device or on a local PC folder which can be used by the Hatari emulator.

### Executing program

Double-click on the file PHSCROLL.TOS from the Atari Desktop.

## Authors

Jeffrey Young aka TheNameOfTheGame on atari-forum where I can be contacted via pm or email.

## Version History

* 1.0
    * Initial release

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

Optimization suggestions by evil and thomas3 at atari-forum:
https://atari-forum.com/viewtopic.php?p=489188#p48918

End-of-scanline sync method from Klapauzius at atari-forum:
https://atari-forum.com/viewtopic.php?p=210237#p210237        

Hatari team for the indespensible and ever useful Hatari emulator:
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


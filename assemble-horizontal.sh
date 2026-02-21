#!/bin/bash

#Horizontal Phase Scroll Demo
name="Horizontal Phase Scroll"
target=HPSCROLL
#debug=HPSCRL_D
src=HPSCROLL.S

#assemble and link debug version w/external symbol table
#vasm -m68000 -Felf -devpac -o "$target".O "$src"
#vlink -b ataritos "$target".O -o "$debug".TOS		 #debug version
#gst2ascii "$debug".TOS > "$target".SYM	2>/dev/null	 #symbol table file

vasm -m68000 -Ftos -devpac -nosym -o "$target".TOS "$src"	#release version


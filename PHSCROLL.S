;        1         2         3         4         5         6         7         8
;2345678901234567890123456789012345678901234567890123456789012345678901234567890
;*******************************************************************************
;* Title : PHSCROLL.S                                                          *
;*******************************************************************************
;* Description   : Atari STE Phase Scrolling Demonstration                     *
;*                                                                             *
;* Coding        : Jeffrey Young                                               *
;*                                                                             *
;* Adapted Code  : Klapauzius - Timer B end of scanline sync method            *
;*                 Leonard - STE machine detection method                      *
;*                 SimonSunnyBoy - Timer B playfield split method              *
;*                                                                             *
;* Documentation : PHSCROLL.TXT                                                *
;*                                                                             *
;* Include Files : SYSTEM.EQU                                                  *
;*                 LMAP.BIN                                                    *
;*                 TDATA.BIN                                                   *
;*                 BOTBAR.BIN                                                  *
;*                 TOPBAR.BIN                                                  *
;*                                                                             *
;* Inspired by ideas in the Amiga 8-Way-Tile-Scroller by Gonzo/Green Rabbits : *
;* https://aminet.net/package/dev/asm/8wayscroller                             *
;*                                                                             *
;* Screen graphics by Simon Phipps (c) Core Design and are included solely for *
;* demonstration purposes.                                                     *
;*                                                                             *
;* Assembler : vasm 1.9e (c) in 2002-2023 Volker Barthelmann                   *
;*             vasm -m68000 -Ftos -devpac -nosym -o PHSCROLL.TOS PHSCROLL.S    *
;*                                                                             *
;* Revision History :                                                          *
;* Rev #      Date     Who     Comments                                        *
;* -----  -----------  ------  ----------------------------------------------- *
;*  1.0    02-Feb-26   J.Y.    First revision for release                      *
;*******************************************************************************

;DEBUG = 1 will display some timing rasters
DEBUG = 0                           ;0 = DEBUG OFF  1=DEBUG ON

;===============================================================================
;=                                  Equates                                    =
;===============================================================================
    include     SYSTEM.EQU          ;atari ste hardware equates

;raster split structure used in timerb handler to set video state
ScrAdr          equ 0               ;to enable movep to set video count quickly
ScrAdrH         equ 1               ;--+
ScrAdrM         equ 2               ;--|
ScrAdrL         equ 3               ;--+->screen address for shifter video count
LWidth          equ 4               ;line width offset for shifter fine scroll
HScroll         equ 5               ;hscroll value for shifter fine scroll
Colors          equ 6               ;shifter color palette
LSplit          equ 38              ;line count for timer b raster split

;input structure used in ikbd interrupt to capture user input
KeyScancode     equ 0               ;scancode returned on keypress event
Joy0Header      equ 1               ;header returned on joystick 0 event
Joy0Data        equ 2               ;payload returned on joystick 0 event
Joy1Header      equ 3               ;header returned on joystick 1 event
Joy1Data        equ 4               ;payload returned on joystick 1 event

;playfield structure used to manage phase scrolling
pfScrPtr        equ -4              ;start of visible display in buffer
pfCurrX         equ 0               ;playfield current x-position in pixels
pfSpeed         equ 2               ;scroll speed 0,1,2,4,8,-1,-2,-4,-8
pfDir           equ 4               ;scroll direction offset -1,21
pfFG            equ 6               ;update column fill gauge 1-16
pfCS            equ 8               ;coarse scroll flag -1,0,1
pfLMCurrX       equ 10              ;level map current x-position in tiles
pfPrvSpd        equ 12              ;previous scroll speed 0,1,2,4,8,-1,-2,-4,-8
pfCurrY         equ 14              ;playfield current y-pos in pixels
pfLMCurrY       equ 16              ;level map current y position in tiles

;tile data
TD_ADDR     equ $60000              ;address to copy tile data to
                                    ;on 64k boundary for blitter word access
TD_SIZE     equ lm_bin-td_bin       ;size in bytes of the tile set data

;level map
LM_ADDR     equ $68000              ;address to copy level map to
LM_SIZE     equ LM_W*LM_H           ;size in bytes of the level map
LM_W        equ 144                 ;width in tile columns of level map
LM_H        equ 100                 ;height in tiles of level map
LM_STARTX   equ PF_STARTX/16        ;initial x position in level map
LM_STARTY   equ PF_STARTY/16        ;initial y position in level map

;status bars
SB_TADDR    equ PF_ADDR+PF_SIZE     ;address to copy top status bar to
SB_TSIZE    equ sbb_bin-sbt_bin     ;size in bytes of the top status bar
SB_BADDR    equ SB_TADDR+SB_TSIZE   ;address to copy bottom status bar to
SB_BSIZE    equ endtext-sbb_bin     ;size in bytes of the bottom status bar

;playfield
PF_ADDR     equ $70000              ;address of the playfield buffer
                                    ;on 64k boundary for blitter word access
PF_STADDR   equ PF_ADDR+8+(LM_STARTX*8)  ;starting word in playfield buffer
            ;   ^       ^  ^         ^
            ;   |       |  |         '---8 bytes scanwalk offset per tile column
            ;   |       |  '-------------starting column in level map
            ;   |       '----------------leave left update column available
            ;   '------------------------playfield buffer address
PF_SIZE     equ SW_SIZE+SW_EXBYT    ;size in bytes of the playfield buffer
                                    ;(30,424 - 10 tiles high 144 tiles wide)
PF_W        equ 320                 ;width of playfield in pixels
PF_H        equ 160                 ;height of playfield in lines
PF_COLS     equ PF_W/PF_TLW         ;number of playfield tile columns
PF_ROWS     equ PF_H/PF_TLH         ;number of playfield tile rows
PF_TLSIZE   equ PF_TLH*8            ;size in bytes per tile (128)
PF_TLW      equ 16                  ;width in pixels per tile
PF_TLH      equ 16                  ;height in lines per tile
PF_PBH      equ PF_H/16             ;playfield phase block height
PF_TSPLIT   equ 20-1                ;line of screen to start playfield at -1
PF_SPLIT    equ 160-1               ;line of screen to end playfield at - 1
                                    ;is -1 as we need one scanline to sync
PF_BSPLIT   equ 0                   ;not used
PF_LW       equ 12                  ;line width skip bytes for ste shifter
                                    ;12 correlates to 184 byte line width
PF_MINX     equ 0                   ;minimum pixel x-coord to allow
PF_MAXX     equ (LM_W*PF_TLW)-PF_W  ;maximum pixel x-coord to allow
PF_SPEED    equ 1                   ;starting scroll speed 0,1,2,4,8
PF_STARTX   equ 192                 ;starting pixel x-coord
PF_STARTY   equ 352                 ;starting line y-coord

;scanwalk
SW_SIZE     equ SW_W*SW_H*PF_TLSIZE ;size in bytes of the base scanwalk buffer
                                    ;(29,440 - 10 tiles high 160 lines)
SW_EXBYT    equ (LM_W-(PF_COLS+1))*8;extra bytes needed for scanwalk buffer
                                    ;(984 for 144 tile width)
SW_W        equ 1+PF_COLS+1+1       ;width in tile columns of scanwalk screen
            ;   ^ ^       ^ ^
            ;   | |       | '-------right update column
            ;   | |       '---------fine scroll column
            ;   | '-----------------playfield columns
            ;   '-------------------left update column
SW_H        equ PF_ROWS             ;height in tiles of scanwalk screen

            text,text

;===============================================================================
;=                                  Main Loop                                  =
;===============================================================================
;*******************************************************************************
;* name     : main                                                             *
;*                                                                             *
;* purpose  : Setup and main program loop for phase scroller.                  *
;*                                                                             *
;* synopsis : See outline below.                                               *
;*-----------------------------------------------------------------------------*
;*      prologue :                                                             *
;*        - init the environment                                               *
;*          - set up local stack                                               *
;*          - enter supervisor mode                                            *
;*          - hide the mouse                                                   *
;*        - run sanity check on system                                         *
;*          - check machine is either STE or MegaSTE                           *
;*          - check that there is enough memory                                *
;*        - save the current system context to restore on exit                 *
;*          - palette, resolution, physbase and logbase                        *
;*          - vbl, timerb and acia interrupt vectors                           *
;*          - various hardware registers needed by the program                 *
;*        - initialize the program state                                       *
;*          - initialize the blitter                                           *
;*          - copy assets to destination locations                             *
;*          - draw the initial playfield                                       *
;*          - initialize the vectors and interrupts                            *
;*  .-> main loop :                                                            *
;*  |       - wait for vbl finish                                              *
;*  |       - execute phase scroll                                             *
;*  |       - handle user input                                                *
;*  |       - update auto-scroll conditions                                    *
;*  |       - if termination request received                                  *
;*  |         - restore vectors and hardware registers                         *
;*  |         - reset ikbd for mouse control and clear buffer                  *
;*  |         - restore resolution, physbase and logbase                       *
;*  |         - show mouse                                                     *
;*  |         - restore system stack                                           *
;*  |         - terminate via Pterm0 ---> desktop                              *
;*  '-------- continue main loop                                               *
;*******************************************************************************
main:       move.l  a7,ustack          ;save old sp
            move.l  #ustack,a7         ;set local stack
            clr.l   -(sp)              ;cpu to supervisor mode
            move.w  #$20,-(sp)         ;Super()
            trap    #1                 ;call GEMDOS
            addq.l  #6,sp              ;correct stack pointer
            dc.w    $A00A              ;hide mouse

            bsr     sys_check          ;check if running on ste and memory ok
            bsr     sav_state          ;save current context to restore at exit
            bsr     init_all           ;initialize program

main_loop:  lea     vbl_flag,a0        ;flag is set in the vbl
.wait_vbl:  tst.w   (a0)               ;check if it is set
            beq.s   .wait_vbl          ;no, wait for vbl to finish
            clr.w   (a0)               ;clear flag for next vbl

    IFNE DEBUG
;start rasters after top border
            lea     hw_VID_VCOUNTLOW.w,a0 ;$ff8209 - video address counter low
            move.b  (a0),d0            ;get count
.waitstart: cmp.b   (a0),d0            ;has it changed?
            beq.s   .waitstart         ;no, keep checking
.waitend:   move.b  (a0),d0            ;get count
            cmp.b   (a0),d0            ;has it changed?
            bne.s   .waitend           ;yes, keep waiting
    ENDIF

            bsr     phase_scroll       ;process speed and phase updates
            bsr     chk_input          ;check user input
            bsr     scroller           ;process autoscroll conditions


            tst.b   exit_flag          ;see if termination requested
            bne     exit_ps            ;yes, exit phase scroller
            bra.s   main_loop          ;no, continue main loop

            ds.l 512                   ;4k space for local stack
ustack:     ds.l 1                     ;place to save old stack pointer

;===============================================================================
;=                               Support Code                                  =
;===============================================================================
;*******************************************************************************
;* name     : sys_check                                                        *
;*                                                                             *
;* purpose  : Sanity check that machine is STE/MegaSTE and has enough memory.  *
;*                                                                             *
;* synopsis : Will run through cookie jar if it exists and check that the      *
;*            _MCH cookie is set as STE or MegaSTE. Then the ending address of *
;*            program data is checked to ensure it is not past the location    *
;*            where assets will be copied. If any conditions fail the program  *
;*            will terminate.                                                  *
;*-----------------------------------------------------------------------------*
;* STE machine check routine adapted from Leonard init method :                *
;* http://leonard.oxg.free.fr/articles/multi_atari/multi_atari.html            *
;*******************************************************************************
sys_check:  move.l  $5a0.w,d0          ;cookie jar pointer
            beq.s   .terminate         ;if no cookie jar then not ste
            move.l  d0,a0              ;for address indirect
.cookielp:  move.l  (a0)+,d0           ;get cookie id
            beq.s   .terminate         ;if reach the end of jar then not ste
            cmp.l   #'_MCH',d0         ;cookie to search for
            beq.s   .found_mch         ;when found, drop out of this loop
            addq.w  #4,a0              ;ahead to next cookie id
            bra.s   .cookielp          ;continue searching
.found_mch: move.w  (a0)+,d7           ;cookie payload
            beq.s   .terminate         ;ST/MegaST - not STE
            cmpi.w  #1,d7              ;STE will match this
            bne.s   .terminate         ;if not match - not STE
            btst.b  #4,1(a0)           ;bit 4 of low word is STE/MegaSTE flag
            beq.s   .ste_ok            ;bit 4 clear - this is STE
            clr.b   $ffff8e21.w        ;MegaSTE cache/cpu control - set to 8MHz
.ste_ok:    bra.s   .mem_check         ;check if enough memory
.terminate: dc.w    $A009              ;show mouse
            move.l  ustack,a7          ;restore stack pointer
            clr.w   -(sp)              ;Pterm0()
            trap    #1                 ;call GEMDOS
.mem_check: lea     endtext,a0         ;end of text section
            cmpa.l  #TD_ADDR,a0        ;lowest asset location
            bgt.s   .terminate         ;not enough memory, terminate
.mem_ok:    rts

;*******************************************************************************
;* name     : save_state                                                       *
;*                                                                             *
;* purpose  : Save environmental values to restore upon program termination.   *
;*                                                                             *
;* synopsis : Will save the current palette, resolution, physbase and logbase. *
;*            Will save interrupt vectors for vbl, timerb, and acia.           *
;*            Will save various mfp and shifter registers                      *
;*******************************************************************************
sav_state:
;save video context
            lea     hw_VID_COLOR0,a0   ;$ff8240 - shifter palette start
            lea     sav_palette,a1     ;location to save to
            moveq   #7,d0              ;8 longwords = 32 bytes
.savpal:    move.l  (a0)+,(a1)+        ;save palette data
            dbf     d0,.savpal         ;loop until done
            move.w  #$04,-(sp)         ;Getrez() - safe for STE
            trap    #14                ;call XBIOS
            addq.l  #2,sp              ;correct stack pointer
            move.w  d0,sav_rez         ;save resolution
            move.w  #$02,-(sp)         ;Physbase()
            trap    #14                ;call XBIOS
            addq.l  #2,sp              ;correct stack pointer
            move.l  d0,sav_physb       ;save physbase
            move.w  #$03,-(sp)         ;Logbase()
            trap    #14                ;call XBIOS
            addq.l  #2,sp              ;correct stack pointer
            move.l  d0,sav_logb        ;save logbase

;save vectors
            lea     sav_storage,a3     ;storage location
            move.l  vec_VBL.w,(a3)+    ;vertical blank
            move.l  vec_TIMERB.w,(a3)+ ;timer b
            move.l  vec_ACIA.w,(a3)+   ;acia (for ikbd)

;save registers
            move.b  hw_MFP_TBCR.w,(a3)+          ;$fffa1b - timer b control
            move.b  hw_MFP_TBDR.w,(a3)+          ;$fffa21 - timer b data
            move.b  hw_MFP_IERA.w,(a3)+          ;$fffa07 - interrupt enable a
            move.b  hw_MFP_IERB.w,(a3)+          ;$fffa09 - interrupt enable b
            move.b  hw_MFP_IMRA.w,(a3)+          ;$fffa13 - interrupt mask a
            move.b  hw_VID_WIDTHOFF_STE.w,(a3)+  ;$ff820f - line offset words
            move.b  hw_VID_HSCROLL_B.w,(a3)+     ;$ff8265 - horizontal scroll
            rts

;*******************************************************************************
;* name     : init_all                                                         *
;*                                                                             *
;* purpose  : Initialize all elements needed to run the phase scroller.        *
;*                                                                             *
;* synopsis : Will initialize the blitter chip, copy graphics and map assets   *
;*            to their assigned locations, draw the initial playfield, and     *
;*            set up interrupt vectors and registers.                          *
;*******************************************************************************
init_all:   bsr     init_screen        ;initialize screen
            bsr     init_blitter       ;initialize blitter registers
            bsr     init_assets        ;copy assets to assigned addresses
            bsr     init_playfield     ;draw initial playfield
            bsr     init_interrupts    ;install handlers and init hardware
            rts

;*******************************************************************************
;* name     : init_screen                                                      *
;*                                                                             *
;* purpose  : Initialize screen parameters                                     *
;*                                                                             *
;* synopsis : Will initialize screen parameters.  Currently, this simply sets  *
;*            the resolution to low.                                           *
;*******************************************************************************
init_screen:
            clr.w   -(sp)              ;low resolution
            move.l  #-1,-(sp)          ;no change to physbase
            move.l  #-1,-(sp)          ;no change to logbase
            move.w  #5,-(sp)           ;Setscreen
            trap    #14                ;call XBIOS
            lea     12(sp),sp          ;correct stack pointer
            rts

;*******************************************************************************
;* name     : init_blitter                                                     *
;*                                                                             *
;* purpose  : Initialize the blitter chip.                                     *
;*                                                                             *
;* synopsis : Load values into all blitter registers to set up a known state.  *
;*            - source x increment is set to 2 because tiles are 16 pixels     *
;*              and 4-planes which is 2 bytes a plane and 8 bytes total.  This *
;*              means the blitter will copy 1 plane each x-count and each then *
;*              skip 2-bytes to the next plane.                                *
;*            - source y increment is set to 2 to keep up with x increment.    *
;*            - source address stubbed and will be set as needed in routines.  *
;*            - endmask 1-3 are not used so are just stuffed.                  *
;*            - destination x increment is set to 2 just as source x increment *
;*              was explained above.                                           *
;*            - destination y increment is set to 178 because the phase scroll *
;*              routine is using 184 byte shifter screen lines.                *
;*            - destination address is set to the playfield address as that is *
;*              where the blitter will copy. This will be adjusted as needed   *
;*              in code. The playfield is set to a 64k boundary on purpose so  *
;*              in later code, just the low word can be updated with .w access *
;*              which is a little faster.                                      *
;*            - x count is 4 as there are 4-plane words to copy each line.     *
;*            - y count is 0 here, but will be set as needed in routines.      *
;*            - hop (Halftone OPeration) is set to 2 :    BIT 7 6 5 4 3 2 1 0  *
;*                                                            0 0 0 0 0 0 1 0  *
;*                                                                        ^ ^  *
;*                                                                        | |  *
;*                                  copy only source content (1:1 copy)---+-'  *
;*            - op (logical OPeration) is set to 3 :      BIT 7 6 5 4 3 2 1 0  *
;*                                                            0 0 0 0 0 0 1 1  *
;*                                                                    ^ ^ ^ ^  *
;*                                                                    | | | |  *
;*                                     source only (replace copy)-----+-+-+-'  *
;*            - blitter control is set to 0 and will be set as needed in code  *
;*              to activate blitter.                                           *
;*            - blitter skew is not used.                                      *
;*******************************************************************************
init_blitter:
            move.w  #2,hw_BLT_SRC_INC_X.w          ;$ff8a20 source x increment
            move.w  #2,hw_BLT_SRC_INC_Y.w          ;$ff8a22 source y increment
            move.l  #$decafbad,hw_BLT_SRC_ADDR_L.w ;$ff8a24 source address
            move.w  #$ffff,hw_BLT_ENDMASK_1.w      ;$ff8a28 endmask 1
            move.w  #$ffff,hw_BLT_ENDMASK_2.w      ;$ff8a2a endmask 2
            move.w  #$ffff,hw_BLT_ENDMASK_3.w      ;$ff8a2c endmask 3
            move.w  #2,hw_BLT_DST_INC_X.w          ;$ff8a2e dest x increment
            move.w  #178,hw_BLT_DST_INC_Y.w        ;$ff8a30 dest y increment
            move.l  #PF_ADDR,hw_BLT_DST_ADDR_L.w   ;$ff8a32 dest address
            move.w  #4,hw_BLT_COUNT_X.w            ;$ff8a36 x count
            move.w  #0,hw_BLT_COUNT_Y.w            ;$ff8a38 y count
            move.b  #2,hw_BLT_HOP.w                ;$ff8a3a hop
            move.b  #3,hw_BLT_OP.w                 ;$ff8a3b op
            move.b  #0,hw_BLT_CONTROL              ;$ff8a3c blitter control
            move.b  #0,hw_BLT_SKEW.w               ;$ff8a3d skew
            rts

;*******************************************************************************
;* name     : init_assets                                                      *
;*                                                                             *
;* purpose  : Copy tile, graphics and level map data to assigned locations.    *
;*                                                                             *
;* synopsis : Tile data is copied on a 64k boundary so that the blitter can    *
;*            access it by the low word as .w which is a little faster.        *
;*            The byte-array level map is copied in right after the tile data. *
;*            The static top and bottom status bar graphics are copied in      *
;*            immediately past the playfield scanwalk buffer.                  *
;*******************************************************************************
init_assets:
;tile data
            move.l  #TD_ADDR,a0        ;dest for tile data - 64k boundary
            move.l  #td_bin,a1         ;source address
            move.w  #(TD_SIZE/4)-1,d0  ;loop index as longs
.tdloop:    move.l  (a1)+,(a0)+        ;copy data as longs
            dbf     d0,.tdloop         ;loop until done

;level map
            move.l  #LM_ADDR,a0        ;destination for level map
            move.l  #lm_bin,a1         ;source address
            move.w  #(LM_SIZE/4)-1,d0  ;loop index as longs
.lmloop:    move.l  (a1)+,(a0)+        ;copy data as longs
            dbf     d0,.lmloop         ;loop until done

;top status bar
            move.l  #SB_TADDR,a0       ;dest for top status bar graphics
            move.l  #sbt_bin,a1        ;source address
            move.w  #(SB_TSIZE/4)-1,d0 ;loop index as longs
.sbtloop:   move.l  (a1)+,(a0)+        ;copy data as longs
            dbf     d0,.sbtloop        ;loop until done

;bottom status bar
            move.l  #SB_BADDR,a0       ;dest for bottom status bar graphics
            move.l  #sbb_bin,a1        ;source address
            move.w  #(SB_BSIZE/4)-1,d0 ;loop index as longs
.sbbloop:   move.l  (a1)+,(a0)+        ;copy data as longs
            dbf     d0,.sbbloop        ;loop until done
            rts

;*******************************************************************************
;* name     : init_playfield                                                   *
;*                                                                             *
;* purpose  : Populate the playfield with graphics to display at start.        *
;*                                                                             *
;* synopsis : The playfield buffer is undefined and needs a full screen of     *
;*            tiles drawn to display at program start. Further, this routine   *
;*            will populate the left update column and right scroll column in  *
;*            in order to allow fine-scroll in either direction at the onset.  *
;*            The playfield screen is drawn in columns and the blitter chip is *
;*            used to copy the data to memory.                                 *
;*            Summarizing, 22 columns of PF_H tiles will be blitted into the   *
;*            playfield buffer. This is 1 left update column, 20 playfield     *
;*            columns, and 1 scroll column. PF_H is 10 for this program but is *
;*            available to change as a user-defined equate.                    *
;*******************************************************************************
init_playfield:
;get pointer into level map
            lea     LM_ADDR,a0         ;address of level map
            move.w  pf_lm_cx,d0        ;current level map x-position
            move.w  pf_lm_cy,d1        ;current level map y-position
            mulu.w  #LM_W,d1           ;create y-index down to current y-pos
            add.w   d0,d1              ;move over by x-pos for final index
            add.l   d1,a0              ;adjust pointer to level map current pos
            lea     -1(a0),a0          ;back one column for left update column

;get pointer into playfield buffer
            move.l  pf_scrptr,a2       ;address of playfield screen display
            lea     -8(a2),a2          ;back one column for left update column

;get pointer to tile data and set blitter source
            lea     TD_ADDR,a1         ;address of tile graphics data
            move.l  a1,hw_BLT_SRC_ADDR_L.w  ;in 64k block so can use .w in loop

;set loop count
            move.w  #21,d4             ;loop for 22 columns
                                       ;left uc, 20 visible cols, scroll column
;draw playfield columns
.draw_all:  movea.l a0,a5              ;save level map index for next column
            move.w  #PF_ROWS-1,d2      ;loop index for tiles to draw each column
            move.w  a2,hw_BLT_DST_ADDR_L+2.w  ;set blitter destination address
                                              ;to adjusted playfield pointer
                                              ;can use low word of BLT_DST_ADDR
                                              ;as destination is all within 64k
.draw_one:  moveq   #0,d3              ;clear it for byte work
            move.b  (a5),d3            ;copy tile index from level map (0-255)
            lsl.w   #7,d3              ;tile index*128
                                       ;tile graphics each 8 bytes * 16 lines
            movea.l a1,a4              ;address of tile graphics data
            adda.l  d3,a4              ;pointer into tile data for current tile
            move.w  a4,hw_BLT_SRC_ADDR_L+2.w  ;set blitter source address
                                              ;to adjusted tile data address
                                              ;can use low word of BLT_SRC_ADDR
                                              ;as source is all within 64k
            move.w  #PF_TLH,hw_BLT_COUNT_Y.w  ;blitter y-count is tile height
            move.b  #$c0,hw_BLT_CONTROL.w     ;start blitter in HOG mode
            lea     LM_W(a5),a5        ;down in level map for next column tile
            dbf     d2,.draw_one       ;loop until column is done
            lea     1(a0),a0           ;adjust level map index to next column
            lea     8(a2),a2           ;adjust screen address to next column
            dbf     d4,.draw_all       ;loop for all columns
            rts

;*******************************************************************************
;* name     : init_interrupts                                                  *
;*                                                                             *
;* purpose  : Install custom interrupt routines and set interrupt registers.   *
;*                                                                             *
;* synopsis : The vertical blank, timer b, and acia interrupts are needed for  *
;*            various purposes in the program. The system vectors for these    *
;*            need to be redirected to custom routines. Further, various       *
;*            mfp chip registers regarding interrupts need to be set to either *
;*            enable or disable specific interrupts. Lastly, the ikbd mode of  *
;*            operation is set to joystick event mode and the buffer cleared.  *
;*******************************************************************************
init_interrupts:
            move.w  #$2700,sr          ;stop interrupts

;install interrupt handlers
            move.l  #vbl,vec_VBL.w       ;set vertical blank handler
            move.l  #timerb,vec_TIMERB.w ;set timer b handler
            move.l  #ikbd,vec_ACIA.w     ;set acia handler for ikbd

;set interrupt registers
            clr.b   hw_MFP_IERA.w      ;$fffa07 - no timer a, b, et al. irqs
            clr.b   hw_MFP_IERB.w      ;$fffa09 - no timer c, d, et al. irqs
            bset    #6,hw_MFP_IERB.w   ;$fffa09 - enable ikbd irqs
            bset    #6,hw_MFP_IMRB.w   ;$fffa15 - unmask ikbd irqs
            clr.b   hw_MFP_TBCR.w      ;$fffa1b - stop timer b & reset counter
                                       ;          will start-up in first vbl
            ori.b   #1,hw_MFP_IERA.w   ;$fffa07 - enable timer b irqs
            ori.b   #1,hw_MFP_IMRA.w   ;$fffa13 - unmask timer b irqs

;set ikbd mode
            move.b  #$12,hw_ACIA_KEYBD.w ;$fffc02 - disable mouse events
.wait:      btst    #1,hw_ACIA_KEYCTL.w  ;$fffc00 - wait for command to finish
            beq.s   .wait                ;loop until done
            move.b  #$14,hw_ACIA_KEYBD.w ;$fffc02 - enable joystick events
.wait2:     btst    #1,hw_ACIA_KEYCTL.w  ;$fffc00 - wait for command to finish
            beq.s   .wait2               ;loop until done

;clear ikbd buffer
            lea     hw_ACIA_KEYCTL,a0  ;$fffc00 - acia ikbd control
.clear:     btst    #0,(a0)            ;any data waiting?
            beq.s   .cleared           ;exit if none
            tst.b   2(a0)              ;ack data
            bra.s   .clear             ;loop until clear
.cleared:
            move    #$2300,sr          ;enable interrupts
            rts

;*******************************************************************************
;* name     : exit_ps                                                          *
;*                                                                             *
;* purpose  : Terminate the phase scroller and exit to desktop.                *
;*                                                                             *
;* synopsis : When the user requests to terminate the program (in this program *
;*            by pressing the <ESC> key), then the original system state is    *
;*            restored and the program terminated.                             *
;*            - Restore original interrupt vectors for vbl, timerb, and acia.  *
;*            - Restore original various mfp and shifter registers.            *
;*            - Reset ikbd to mouse mode and flush buffer.                     *
;*            - Restore original palette, resolution, physbase and logbase.    *
;*            - Show the mouse                                                 *
;*            - Restore original stack pointer                                 *
;*            - Call Pterm0 to terminate program                               *
;*******************************************************************************
exit_ps:    move    #$2700,sr          ;stop interrupts

;restore vectors
            lea     sav_storage,a3     ;storage location
            move.l  (a3)+,vec_VBL.w    ;vertical blank
            move.l  (a3)+,vec_TIMERB.w ;timer b
            move.l  (a3)+,vec_ACIA.w   ;acia

;restore registers
            move.b  (a3)+,hw_MFP_TBCR.w         ;$fffa1b - timer b control
            move.b  (a3)+,hw_MFP_TBDR.w         ;$fffa21 - timer b data
            move.b  (a3)+,hw_MFP_IERA.w         ;$fffa07 - interrupt enable a
            move.b  (a3)+,hw_MFP_IERB.w         ;$fffa09 - interrupt enable b
            move.b  (a3)+,hw_MFP_IMRA.w         ;$fffa13 - interrupt mask a
            move.b  (a3)+,hw_VID_WIDTHOFF_STE.w ;$ff820f - line offset words
            move.b  (a3)+,hw_VID_HSCROLL_B.w    ;$ff8265 - horizontal scroll

;set ikbd mode
            move.b  #8,hw_ACIA_KEYBD.w  ;$fffc02 - enable mouse events
.wait:      btst    #1,hw_ACIA_KEYCTL.w ;$fffc00 - wait for command to finish
            beq.s   .wait

;clear ikbd buffer
            lea     hw_ACIA_KEYCTL,a0  ;$fffc00 - acia ikbd control
.clear:     btst    #0,(a0)            ;any data waiting?
            beq.s   .cleared           ;exit if none
            tst.b   2(a0)              ;ack data
            bra.s   .clear             ;loop until clear
.cleared:

;restore original screen state
            lea     sav_palette,a1     ;original palette
            lea     hw_VID_COLOR0,a2   ;shifter palette start
            move.w  #7,d1              ;7 longwords = 32 bytes
.palette:   move.l  (a1)+,(a2)+        ;copy palette data
            dbf     d1,.palette        ;loop until done

            move.w  sav_rez,-(sp)      ;original resolution
            move.l  sav_physb,-(sp)    ;original physbase
            move.l  sav_logb,-(sp)     ;original logbase
            move.w  #5,-(sp)           ;Setscreen - safe for STE/MegaSTE
            trap    #14                ;call XBIOS
            lea     12(sp),sp          ;correct stack pointer

;show mouse
            dc.w    $A009              ;show mouse

;restore stack pointer
            move.l  ustack,a7          ;restore stack

;terminate program
            move    #$2300,sr          ;enable interrupts
            clr.w   -(sp)              ;Pterm0
            trap    #1                 ;call GEMDOS

;*******************************************************************************
;* name     : chk_input                                                        *
;*                                                                             *
;* purpose  : Check for keyboard or joystick data from ikbd and respond.       *
;*                                                                             *
;* synopsis : The user may press any of several keys to interact with the      *
;*            program. Here a check is made to see if a keypress or joystick   *
;*            event from the ikbd was captured via the acia interrupt handler. *
;*            For this program joystick events are captured but are not used.  *
;*            Keypresses are checked to see if they are 'make' (press) or      *
;*            'break'(release) events.  Only 'make' events are acted upon.     *
;*            The following keypresses are recognized:                         *
;*            - ESC      : terminate the program                               *
;*            - SPACEBAR : toggle auto-scroll direction                        *
;*            - 0        : change speed to 0 (no scroll)                       *
;*            - 1        : change speed to 1                                   *
;*            - 2        : change speed to 2                                   *
;*            - 4        : change speed to 4                                   *
;*            - 8        : change speed to 8                                   *
;*******************************************************************************
chk_input:  moveq   #0,d0
            move.b  key_scancode,d0    ;scancode as make/break (press/release)
            beq     chk_joy1           ;check joysticks otherwise

;key press
            clr.b   key_scancode       ;clear for next key event
            move.b  d0,d1              ;need to check if we are make or break
            andi.b  #$80,d1            ;will be zero if it was key make (press)
            bne.s   .chk_done          ;if key break (release) then simply exit
.chk_exit:  cmp.b   #$01,d0            ;'<esc>' keypress?
            bne.s   .chk_space
            st.b    exit_flag          ;yes, request to terminate, set exit flag
            bra.s   .chk_done
.chk_space: cmp.b   #$39,d0            ;'<space>' keypress?
            bne.s   .chk_speed
            tst.w   pf_speed           ;yes, but only change direction if moving
            beq.s   .chk_done          ;not moving, so exit
            neg.w   pf_speed           ;reverse speed
            bra.s   .chk_done
.chk_speed: cmp.b   #$0B,d0            ;'0' keypress?
            bne.s   .chk_sped1
            move.b  #0,d0              ;yes, speed=0
            bra.s   .set_speed         ;process new speed setting
.chk_sped1: cmp.b   #$02,d0            ;'1' keypress?
            bne.s   .chk_sped2
            move.b  #1,d0              ;yes, speed=1
            bra.s   .set_speed         ;process new speed setting
.chk_sped2: cmp.b   #$03,d0            ;'2' keypress?
            bne.s   .chk_sped4
            move.b  #2,d0              ;yes, speed=2
            bra.s   .set_speed         ;process new speed setting
.chk_sped4: cmp.b   #$05,d0            ;'4' keypress?
            bne.s   .chk_sped8
            move.b  #4,d0              ;yes, speed=4
            bra.s   .set_speed         ;process new speed setting
.chk_sped8: cmp.b   #$09,d0            ;'8' keypress?
            bne.s   .chk_done
            move.b  #8,d0              ;yes, speed=8
.set_speed: tst.w   pf_speed           ;test previous recorded speed
            bgt.s   .pos_speed         ;positive speed
            bmi.s   .neg_speed         ;negative speed
.zero_sped: tst.w   pf_dir             ;what direction is current scroll?
            bpl.s   .pos_speed         ;positive
.neg_speed: neg.b   d0                 ;negative dir so negate speed
            ext.w   d0                 ;extend sign as speed value is word
.pos_speed: move.w  d0,pf_speed        ;store new speed value
.chk_done:  rts

;joystick 1
chk_joy1:   tst.b   joy1_data          ;was event from joystick 1?
            beq.s   chk_joy0           ;no, check joystick 0
            clr.b   joy1_data          ;simply clear for next joystick 1 event
            rts

;joystick 0
chk_joy0:   clr.b   joy0_data          ;simply clear for next joystick 0 event
            rts

;*******************************************************************************
;* name     : scroller                                                         *
;*                                                                             *
;* purpose  : Apply a simple auto-scroll to demonstrate phase scrolling.       *
;*                                                                             *
;* synopsis : To demonstrate phase-scrolling, here there is an auto-scroll     *
;*            routine that checks which way the scroll is going and based on   *
;*            that will perform edge checking against the current x-position.  *
;*            When edges of the playfield are reached, the scroll direction is *
;*            reversed. If speed is 0, the routine is ended so that the scroll *
;*            direction is kept as the last 'moving' or scrolling direction.   *
;*******************************************************************************
scroller:   move.w  pf_speed,d0        ;current scroll speed
            beq.s   .done              ;if speed=0, simply exit
            move.w  pf_currx,d1        ;playfield x-pos
            tst.w   d0                 ;which way is scrolling?
            bgt.s   .chk_max           ;positive, check right edge
.chk_min:   cmp.w   #PF_MINX,d1        ;negative, check left edge
            bgt.s   .done              ;not there, so exit
            bra.s   .reverse           ;otherwise, reverse scrolling
.chk_max:   cmp.w   #PF_MAXX,d1        ;at the farthest edge?
            blt.s   .done              ;not there, so exit
.reverse:   neg.w   d0                 ;otherwise, reverse scrolling
            move.w  d0,pf_speed        ;save reversed speed
.done:      rts

;===============================================================================
;=                             Interrupt Handlers                              =
;===============================================================================
;*******************************************************************************
;* name     : vbl                                                              *
;*                                                                             *
;* purpose  : Interrupt handler to set video parameters for phase scroll and   *
;*            playfield splits.                                                *
;*                                                                             *
;* synopsis : Each vertical blank interrupt, the video state parameters must   *
;*            be reset for the screen raster split, timer b programmed for     *
;*            for the line split, the shifter scroll vbl portion of code run,  *
;*            and then vbl flag set indicating the routine is finished. This   *
;*            is used in the main loop to synchronize the scrolling with the   *
;*            start of the display refresh.                                    *
;*******************************************************************************
vbl:        movem.l d0-d7/a0-a1,-(sp)  ;interrupt routine so save registers

;stop timer b
            clr.b   hw_MFP_TBCR.w      ;$fffa1b - stop timer b & reset counter

;set video registers for the top status bar
            lea     splits(pc),a0      ;raster splits attribute table
            move.w  #1,(a0)+           ;reset split count
            move.b  ScrAdrH(a0),hw_VID_DBASEHI       ;$ff8201 - DBASEHI
            move.b  ScrAdrM(a0),hw_VID_DBASEMID      ;$ff8203 - DBASEMID
            move.b  ScrAdrL(a0),hw_VID_DBASELO_STE   ;$ff820d - DBASELO_STE

            ;STE shifter bug patch!
            ;reinit internal shifter timing by writing video count
            move.b  ScrAdrH(a0),hw_VID_VCOUNTHI      ;$ff8205 - VCOUNTHI
            move.b  ScrAdrM(a0),hw_VID_VCOUNTMID     ;$ff8207 - VCOUNTMID
            move.b  ScrAdrL(a0),hw_VID_VCOUNTLOW     ;$ff8209 - VCOUNTLOW

            move.b  HScroll(a0),hw_VID_HSCROLL_B.w   ;$ff8265 - hscroll
            move.b  LWidth(a0),hw_VID_WIDTHOFF_STE.w ;$ff820f - linewidth offset
            movem.l Colors(a0),d0-d7                 ;palette for top status bar
            movem.l d0-d7,hw_VID_COLOR0.w            ;set shifter palette

;set timer b to fire at line where playfield will start (1 line before please)
            move.b  LSplit(a0),hw_MFP_TBDR.w ;$fffa21 - timer b interrupt line
            move.b  #8,hw_MFP_TBCR.w         ;$fffa1b - start timer b
                                             ;8 = event (line) count mode

;update hscroll and screen address for playfield shifter scroll
            bsr     shifter_scroll_vbl ;vbl part of phase scroll

;set flag to indicate vbl has finished
            move.w  #$ff,vbl_flag      ;set flag

            movem.l (sp)+,d0-d7/a0-a1  ;restore registers
            rte

;*******************************************************************************
;* name     : timerb                                                           *
;*                                                                             *
;* purpose  : Interrupt handler to set screen split video parameters.          *
;*                                                                             *
;* synopsis : Timer B can interrupt when a certain number of scanlines have    *
;*            been drawn. This is called 'event mode' and is a method of       *
;*            counting screen lines.  Here we use this mode to set a number    *
;*            of video parameters when a split is triggered, allowing each     *
;*            split to present a different playfield or screen graphics with   *
;*            its own screen address, palette and scroll and line width offset *
;*            values. To facilitate multiple splits within a single screen     *
;*            refresh, a table of video state values is provided along with a  *
;*            counter variable to indicate which table entry is to be used.    *
;*            The table is named 'splits' and can be seen in the data section  *
;*            of the code. Because of the limited time in this interrupt to    *
;*            update several video registers without glitches it must be done  *
;*            very quickly and at the very start of a scanline. Because of the *
;*            setup procedure, the interrupt must be set for the line before   *
;*            the target scanline. This gives time to set up the variables     *
;*            to then push quickly into the video registers when the target    *
;*            scanline starts. The method to sync to end of scanline as well   *
;*            as the method to change video registers at timer b interrupt     *
;*            were adapted from existing code. Credits and references below.   *
;*-----------------------------------------------------------------------------*
;* timer b playfield split method adapted from simonsunnyboy/paradize routine :*
;* https://paradize.final-memory.org/downloads/ahcc/ste_playfld.zip            *
;* optimization suggestions by evil and thomas3 at atari-forum :               *
;* https://atari-forum.com/viewtopic.php?p=489188#p489188                      *
;* wait end-of-scanline method from Klapauzius at atari-forum :                *
;* https://atari-forum.com/viewtopic.php?p=210237#p210237                      *
;*******************************************************************************
timerb:
    IFNE DEBUG
            move.w  #$070,hw_VID_COLOR0.w ;rasters enable
    ENDIF
            movem.l d0-d7/a0-a6,-(sp)     ;interrupt so must save registers

;stop timer b and reset the internal counter
            clr.b   hw_MFP_TBCR.w         ;$fffa1b - stop timerb & reset counter

;we'll have to wait for the new scanline anyway so use the time to prepare the
;data that needs to be written quickly into HW registers with start of the new
;scanline
            lea     splits(pc),a1         ;raster splits attribute table
            moveq   #0,d0                 ;for adda.l below
            move.w  (a1),d0               ;split count
            add.w   #1,(a1)+              ;increment split count
            lsl.w   #6,d0                 ;64 bytes each split
            adda.l  d0,a1                 ;pointer to video state vars
            move.l  (a1)+,d1              ;d1 - ScrAdr
            move.b  (a1)+,d2              ;d2 - LWidth
            move.b  (a1)+,d3              ;d3 - HScroll
            beq.s   .no_scroll            ;is there any fine scroll?
            subq.w  #4,d2                 ;yes, adjust LWidth
.no_scroll: movem.l (a1)+,d4-d7/a3-a6     ;d4-d7/a3-a6 - Colors
            move.b  (a1),hw_MFP_TBDR.w    ;$fffa21 - lines until next split
            lea     hw_VID_WIDTHOFF_STE.w,a1 ;$ff820f - use as base for offsets
            lea     hw_VID_COLOR0.w,a2    ;$ff8240 - shifter palette start
    IFNE DEBUG
            move.w  #$700,(a2)            ;rasters enable
    ENDIF

;wait for scanline end (Klapauzius  style)
            lea     hw_VID_VCOUNTLOW.w,a0 ;$ff8209 - video address counter low
            move.b  (a0),d0               ;get count
.waitstart: cmp.b   (a0),d0               ;has it changed?
            beq.s   .waitstart            ;no, keep checking
.waitend:   move.b  (a0),d0               ;get count
            cmp.b   (a0),d0               ;has it changed?
            bne.s   .waitend              ;yes, keep waiting

;push new video state values into registers
            movep.l d1,-12(a1)            ;DBASEMID,VCOUNTHI,VCOUNTMID,VCOUNTLOW
            move.b  d2,(a1)               ;line width offset
            move.b  d3,hw_VID_HSCROLL_B.w ;hscroll data
            movem.l d4-d7/a3-a6,(a2)      ;16 word palette

;turn on timer b for next split
            move.b  #8,hw_MFP_TBCR.w      ;$fffa1b - start timer b
                                          ;8 = event (line) count mode

            movem.l (sp)+,d0-d7/a0-a6     ;restore registers

;acknowledge interrupt to allow new latching
            move.b  #$fe,hw_MFP_ISRA.w    ;$fffa0f - acknowledge timer b
            rte

;*******************************************************************************
;* name     : ikbd                                                             *
;*                                                                             *
;* purpose  : Capture ikbd events representing user input.                     *
;*                                                                             *
;* synopsis : The ikbd will request an interrupt via the acia chip when it has *
;*            received keyboard or joystick input or state changes. Here those *
;*            inputs are recorded for use as user input in the main loop.      *
;*            For keyboard events, there are two states, 'make' which is when  *
;*            a key is pressed down, and 'break' for when key is released.     *
;*            The 'break' state has the scancode byte ORed with #$80. This     *
;*            is stored as-is here and it is the responsibility of the program *
;*            code to handle the 'make' and 'break' events. The joystick has   *
;*            been initialized to joystick event reporting mode previously     *
;*            and in this mode ikbd will first present a 'header' byte that    *
;*            indicate which joystick was used and to expect a following byte  *
;*            containing the 'payload' or bitfield data byte of the actual     *
;*            joystick state as of the event.                                  *
;*******************************************************************************
ikbd:
    IFNE DEBUG
            movem.l d0-d1/a0,-(sp)     ;interrupt so must save registers
            move.w  hw_VID_COLOR0.w,d1 ;rasters enable
            move.w  #4444,hw_VID_COLOR0.w ;rasters enable
    ELSE
            movem.l d0/a0,-(sp)        ;interrupt so must save registers
    ENDIF
            lea     key_scancode(pc),a0 ;address indirect quicker here

;grab transmitted data byte
            move.b  hw_ACIA_KEYBD.w,d0 ;$fffc02 - ikbd data byte

;check if joystick payload delivery, i.e. if header received previously
.tst_joy1:  tst.b   Joy1Header(a0)     ;are we waiting for joystick 1 payload?
            beq.s   .tst_joy0          ;no, check joystick 0
            move.b  d0,Joy1Data(a0)    ;save payload
            clr.b   Joy1Header(a0)     ;joystick event done
            bra.s   .ikbd_done
.tst_joy0:  tst.b   Joy0Header(a0)     ;are we waiting for joystick 0 payload?
            beq.s   .chk_headr         ;no, check if new data is for a header
            move.b  d0,Joy0Data(a0)    ;save payload
            clr.b   Joy0Header(a0)     ;joystick event done
            bra.s   .ikbd_done

;check if joystick header received
.chk_headr: cmp.b   #$f6,d0            ;packet headers range $f6-$ff
            bcs.s   .get_key           ;not a header, get the scancode
            cmp.b   #$ff,d0            ;joystick 1 event?
            bne.s   .chk_hedr0         ;no, check joystick 0
            st.b    Joy1Header(a0)     ;mark that we expect payload data next
            bra.s   .ikbd_done
.chk_hedr0: cmp.b   #$fe,d0            ;joystick 0 event?
            bne.s   .ikbd_done         ;no, exit
            st.b    Joy0Header(a0)     ;mark that we expect payload data next
            bra.s   .ikbd_done

;store key press scancode byte
.get_key:   move.b  d0,(a0)            ;save scancode

.ikbd_done:
    IFNE DEBUG
            move.w  d1,hw_VID_COLOR0.w ;rasters enable
            movem.l (sp)+,d0-d1/a0     ;restore registers
    ELSE
            movem.l (sp)+,d0/a0        ;restore registers
    ENDIF

;acknowledge interrupt to allow new latching
            move.b  #$bf,hw_MFP_ISRB.w ;$fffa11 - acknowledge ikbd interrupt
            rte

;===============================================================================
;=                                Phase Scroll                                 =
;===============================================================================
;*******************************************************************************
;* name     : phase_scroll                                                     *
;*                                                                             *
;* purpose  : Run constituent parts of the phase scrolling process.            *
;*                                                                             *
;* synopsis : Phase scroll has two aspects :                                   *
;*            - There is a shifter scroll which handles the fine and coarse    *
;*              scrolling based on the current playfield x-position and the    *
;*              speed or x-delta change which can be positive or negative. The *
;*              shifter scroll also has a small component to be run in the     *
;*              vertical blank interrupt to set the current hscroll and screen *
;*              address values in the playfield raster split table so they can *
;*              be used in the following screen refresh's playfield raster     *
;*              split to set the hscroll and screen address registers of the   *
;*              shifter.                                                       *
;*            - There is also a blitter scroll component which is tasked with  *
;*              phase-wise construction of the scanwalk update columns so that *
;*              they are ready and available to display upon a coarse scroll   *
;*              irregardless of speed or directional changes. The blitter is   *
;*              used for the copying of tile graphics data during the update   *
;*              column construction.                                           *
;*******************************************************************************
phase_scroll:
            bsr     shifter_scroll     ;shifter fine and coarse scroll
            bsr     blitter_scroll     ;blitter update phase processing
            rts

;*******************************************************************************
;* name     : shifter_scroll                                                   *
;*                                                                             *
;* purpose  : Update fine and coarse scroll variables used by the shifter.     *
;*                                                                             *
;* synopsis : The fine and coarse scrolling is based on the current playfield  *
;*            x-position and speed or x-delta changes which can be positive    *
;*            or negative. This also involves range checking to ensure that    *
;*            min/max limits of the playfield are not exceeded. If x-position  *
;*            changes result in a column change then the appropriate variables *
;*            are updated to allow a coarse scroll. The previous x-position is *
;*            stored to allow column changes to be detected. The x-position    *
;*            value is pixel oriented so ANDing these values with $FFF0 will   *
;*            give the column number as the STE shifter uses word-size planes  *
;*            representing 16 pixels. There is a small ancillary component to  *
;*            be run in the vertical blank interrupt. Details below in the     *
;*            header for that subroutine.                                      *
;*******************************************************************************
shifter_scroll:
            lea     pf_currx,a0        ;address register indirect quicker

;handle speed 0
            move.w  pfSpeed(a0),d0     ;current playfield speed +/-
            beq.s   .get_xpos          ;keep prev speed if current is 0
            move.w  d0,pfPrvSpd(a0)    ;prev speed for phase scroll idling
                                       ;if current speed is 0 then prev
                                       ;speed is used to 'idle' so that
                                       ;phase block update keeps the
                                       ;resource use more consistent

;fine scroll range check
.get_xpos:  move.w  pfCurrX(a0),d1     ;current playfield x-position
            move.w  d1,d2              ;to compare if column change later
            add.w   d0,d1              ;change x-pos according to speed +/-
            tst.w   d0                 ;check speed
            beq.s   .rchk_done         ;if speed = 0, no range check needed
            bpl.s   .chk_redge         ;if positive, check right edge

.chk_ledge: cmp.w   #PF_MINX-1,d1      ;check pos just past left edge
            bgt.s   .rchk_done         ;if not there, then all is ok
            moveq   #PF_MINX,d1        ;otherwise, set x-pos to left edge
            bra.s   .rchk_done         ;and continue

.chk_redge: cmp.w   #PF_MAXX+1,d1      ;check pos just past right edge
            blt.s   .rchk_done         ;if not there, then all is ok
            move.w  #PF_MAXX,d1        ;otherwise, set x-pos to right edge

;coarse scroll check
.rchk_done: move.w  d1,pfCurrX(a0)     ;save new playfield x-position
            moveq   #0,d3              ;coarse scroll flag cleared to start
                                       ;used to flag whether coarse scroll
                                       ;happens and if it is left or right
                                       ;valid flag values are -1,0,1
            andi.w  #$fff0,d1          ;new tile column from current x-pos
            andi.w  #$fff0,d2          ;old tile column from previous x-pos
            cmp.w   d2,d1              ;are the columns different?
            beq.s   .cs_done           ;no, skip coarse scroll adjustment
            bgt.s   .cs_right          ;new column greater so going right

;coarse scroll left
.cs_left:   sub.l   #8,pfScrPtr(a0)    ;adjust playfield screen ptr back
            sub.w   #1,pfLMCurrX(a0)   ;adjust level map ptr back
            moveq   #-1,d3             ;set coarse scroll flag to -1
            tst.w   pfDir(a0)          ;which direction is scroll atm?
            bmi.s   .cs_done           ;already going left so done
            move.w  #-1,pfDir(a0)      ;set new direction
            move.w  #16,pfFG(a0)       ;mark fill gauge as full
            bra.s   .cs_done

;coarse scroll right
.cs_right:  add.l   #8,pfScrPtr(a0)    ;adjust playfield screen ptr forward
            add.w   #1,pfLMCurrX(a0)   ;adjust level map ptr forward
            moveq   #1,d3              ;set coarse scroll flag to 1
            tst.w   pfDir(a0)          ;which direction is scroll atm?
            bpl.s   .cs_done           ;already going right so done
            move.w  #21,pfDir(a0)      ;set new direction
            move.w  #16,pfFG(a0)

;update coarse scroll flag and exit
.cs_done:   move.w  d3,pfCS(a0)        ;update coarse scroll flag
            rts

;*******************************************************************************
;* name     : shifter_scroll_vbl                                               *
;*                                                                             *
;* purpose  : Copy scroll variables to the raster split table for the shifter. *
;*                                                                             *
;* synopsis : The fine and coarse scroll values updated in the shifter_scroll  *
;*            routine have to be copied into the raster split table during     *
;*            the vertical blank interrupt so that they can be ready during    *
;*            the following screen refresh to be moved into the shifter's      *
;*            hscroll and screen address registers when the playfield raster   *
;*            split line is reached and the playfield is ready is to be shown. *
;*            This is done in this routine and a 'bsr shifter_scroll_vbl' is   *
;*            run in the vertical blank interrupt to reach and execute this    *
;*            code every screen refresh interval.                              *
;*******************************************************************************
shifter_scroll_vbl:
            movem.l d0/a0-a1,-(sp)     ;as called from interrupt handler
            lea     pf_vars(pc),a0     ;playfield shifter state vars
            lea     pf_scrptr,a1       ;pf_scrptr, pf_currx
            move.w  4(a1),d0           ;pf_currx - playfield current x-pos
            and.w   #$000f,d0          ;scroll bits in low nibble (0-15)
            move.b  d0,HScroll(a0)     ;store the hscroll value
            move.l  (a1),ScrAdr(a0)    ;pf_scrptr - playfield screen address
            movem.l (sp)+,d0/a0-a1     ;restore registers
            rts

;*******************************************************************************
;* name     : blitter_scroll                                                   *
;*                                                                             *
;* purpose  : Keep update columns in-phase and ready to display.               *
;*                                                                             *
;* synopsis : This routine is tasked with phase-wise construction of the       *
;*            scanwalk update columns so that they are ready and available to  *
;*            display upon a coarse scroll. They should ready irregardless of  *
;*            speed or directional changes. The blitter is used for fast copy  *
;*            of tile graphics data during the update column construction.     *
;*            The process of update column construction is multi-step. Details *
;*            are in the documentation provided with this code : PHSCROLL.TXT  *
;*            and the reader is directed there for full explanation. The steps *
;*            will be summarized here:                                         *
;*            - Check for speed 0 and if so, load the previous speed to use.   *
;*              This is so that phase processing is consistent and there is    *
;*              the same processing time taken as was the previous interval.   *
;*            - Normalize the conditions. Here we are normalizing the
;*              - Speed is normalized as an absolute value since the phase     *
;*                processing is the same whether the speed is positive or      *
;*                negative. Speed polarity can determine which update column   *
;*                is used, but only on a column change. During inter-column    *
;*                speed changes this does not come into play.                  *
;*              - Update column phase block is normalized to 0->15 direction.  *
;*                This is because on a phase change for negative coarse scroll *
;*                the phase block orientation would be going in a 15->0 manner *
;*                due to the way left fine-scrolling updates the scroll bits.  *
;*                Normalizing this makes the code more efficient and smaller.  *
;*              - Phase block is normalized. Here we address the situation     *
;*                where we have a speed change which results in the new pixel  *
;*                x-position lying within the boundaries of a phase block with *
;*                regards to speed. For example, the pixel position is 1 at    *
;*                speed 1 and then is a change to speed 4. This would result   *
;*                in a new pixel position of 5 with is withing the second      *
;*                phase block of the speed, which are 0,4,8 and 12. So by      *
;*                normalizing the phase, the phase block number is set to the  *
;*                start of the appropriate phase block irregardless of the     *
;*                pixel position within the block.                             *
;*            - Process the fill gauge. Because of the nature of speed changes *
;*              and bi-directional 'infinite' scrolling, certain conditions    *
;*              can leave a 'gap' in the update column. This situation and the *
;*              case of preventing bi-directional fine scrolling within a      *
;*              column triggering unneeded gap fills are handled by use of a   *
;*              fill gauge which keeps track of how 'full' the current update  *
;*              column is at any given time.                                   *
;*            - Process gaps. There are two types of gaps. The first results   *
;*              from inter-column speed increases and the second can come from *
;*              speed changes resulting in a coarse scroll. In the event a gap *
;*              results due to the above situations, either 'gap compensation' *
;*              of 'gap completion' are run, respectively.                     *
;*            - Draw the phase block into the update column. Copying the tile  *
;*              graphics data is done with the blitter for faster completion.  *
;*              Drawing the phase block has multiple steps :                   *
;*              - Determine the number of lines to draw based on speed.        *
;*              - Calculate the tile number for the update column position.    *
;*              - Calculate the line skip for the phase and tile needed.       *
;*              - Get the level map pointer for the tile number and position.  *
;*              - Get the tile data pointer for the level map position.        *
;*              - Calculate the playfield buffer position for the required     *
;*                update column (left or right).                               *
;*              - Copy tile graphics data to the phase block via the blitter.  *
;*******************************************************************************
blitter_scroll:
    IFNE DEBUG
            move.w  #227,hw_VID_COLOR0.w ;rasters enable
    ENDIF
            lea     pf_currx,a0        ;address indirect quicker
            movem.w (a0),d0-d4         ;d0 pf_currx - current x-position
                                       ;d1 pf_speed - scroll speed
                                       ;d2 pf_dir - scroll direction
                                       ;d3 pf_fg - update column fill gauge
                                       ;d4 pf_cs - coarse scroll flag

;handle speed 0
speed0:     tst.w   d1                 ;is speed=0?
            bne.s   normalize          ;no, skip ahead
            move.w  pfPrvSpd(a0),d1    ;yes, use previous non-zero speed
                                       ;this allows smoother 'idling'
            beq     done_bs            ;but if prevspeed was 0, exit

;normalize conditions
normalize:  tst.w   d1                 ;check speed
            bpl.s   .n_ucb             ;positive so skip ahead
.n_speed:   neg.w   d1                 ;normalize speed (absolute)
.n_ucb:     tst.w   d2                 ;check scroll direction
            bpl.s   .n_phase           ;positive so skip ahead
            eor.w   #15,d0             ;normalize update column block 0->15
.n_phase:   moveq   #16,d7             ;for phase masking
            sub.w   d1,d7              ;subtract speed for phase mask
            and.w   d7,d0              ;normalize phase block
                                       ;ex: speed 4 x-pos 4 -> phase block 4
                                       ;    speed 4 x-pos 5 -> phase block 4
                                       ;    speed 4 x-pos 6 -> phase block 4
                                       ;    speed 4 x-pos 7 -> phase block 4

;process fill gauge
fillgauge:  move.w  d0,d7              ;normalized phase block
            add.w   d1,d7              ;get bottom of phase block
            tst.w   d4                 ;was there a coarse scroll?
            beq.s   .no_cs             ;no, skip ahead
            move.w  d7,pfFG(a0)        ;yes, reset fill gauge for new uc
            cmpi.w  #16,d3             ;was previous uc totally filled?
            blt.s   gap_completion     ;no, process the gap
            bra.s   draw_pb            ;yes, no gap so process phase block
.no_cs:     cmp.w   d3,d0              ;is there a gap?
            bgt.s   gap_compensation   ;yes, process the gap
.no_gap:    cmp.w   d3,d7              ;new high water mark?
            ble.s   draw_pb            ;no, process phase block
            move.w  d7,pfFG(a0)        ;yes, save new fill gauge value
            bra.s   draw_pb            ;process phase block

;process gaps
gap_completion:
;-------------------------------------------------------------------------------
;here there was a gap on a previous update column before a coarse scroll
;so we will run a separate draw phase block for the previous update column
;and then come back and do a normal draw phase block.
;-------------------------------------------------------------------------------
            move.w  d0,a4              ;save normalized phase for return
            move.w  d1,a5              ;save normalized speed for return
            move.w  d2,a6              ;save scroll direction for return
            move.w  d3,d0              ;fill gauge is pseudo-phase
            moveq   #16,d1             ;for gap size calc
            sub.w   d3,d1              ;gap size is pseudo-speed
;-------------------------------------------------------------------------------
;normally the update column offset is the same as the scroll direction:
;-1 for left scrolling and 21 for right scrolling
;this is the column offset to draw in the correct column for the direction
;here we need to work on the previous update column so it would change to:
;0 for left scrolling and 20 for right scrolling
;-------------------------------------------------------------------------------
            subq    #1,d2              ;-2 or 20
            tst.w   d2                 ;what scroll direction actually?
            bpl.s   .gap_fill          ;if positive, ready to fill gap
            addq    #2,d2              ;negative, so uc forward to 0
.gap_fill:  bsr     draw_pb            ;process pseudo-phase block
    IFNE DEBUG
            move.w  #227,hw_VID_COLOR0.w ;rasters enable
    ENDIF
            move.w  a4,d0              ;restore normalized phase
            move.w  a5,d1              ;restore normalized speed
            move.w  a6,d2              ;restore scroll direction
            bra.s   draw_pb            ;process phase block

gap_compensation:
;-------------------------------------------------------------------------------
;here there was a gap in the current update column resulting from a fine scroll
;so we will adjust the phase block to account for the gap and drop through to
;normal draw phase block.
;-------------------------------------------------------------------------------
            move.w  d0,d6              ;normalized phase
            move.w  d3,d0              ;new psuedo-phase block
            sub.w   d3,d6              ;gap size
            add.w   d6,d1              ;new psuedo-speed
            add.w   d1,d3              ;new fill gauge value
            move.w  d3,pfFG(a0)        ;save it

;calculate phase block draw parameters
draw_pb:    mulu.w  #PF_PBH,d1         ;lines to draw
            move.w  d0,d4              ;save current phase - needed later
            mulu.w  #PF_PBH,d4         ;line phase starts on
            move.w  d4,d5              ;need both
            lsr.w   #4,d5              ;phase tile number
            andi.w  #$000f,d4          ;phase tile line skip

;get pointer into level map for phase tile
            lea     LM_ADDR,a0         ;level map address
            move.w  pf_lm_cx,d6        ;level map current x-pos
            move.w  pf_lm_cy,d7        ;level map current y-pos
            add.w   d5,d7              ;add current phase tile to y-pos
            mulu.w  #LM_W,d7           ;vertical offset into level map
            add.w   d6,d7              ;add horizontal offset
            add.w   d2,d7              ;adjust left or right update column
            adda.l  d7,a0              ;final pointer into level map

;get pointer into tile data for phase tile
            lea     TD_ADDR,a1         ;tile data address
            moveq   #0,d7              ;for adda.l below
            move.b  (a0),d7            ;tile index from level map
            lsl.w   #7,d7              ;tiles are 128 bytes each
            move.w  d4,d6              ;phase tile line skip
            lsl.w   #3,d6              ;tile lines are 8 bytes each
            add.w   d6,d7              ;tile data offset
            adda.l  d7,a1              ;final pointer into tile data

;get pointer into playfield buffer for phase tile
            move.l  pf_scrptr,a2       ;current playfield screen pointer
            mulu.w  #184*PF_PBH,d0     ;lines down that phase block starts
            adda.l  d0,a2              ;adjust pointer to phase block start
            ext.l   d2                 ;phase direction is signed
            lsl.l   #3,d2              ;update column offset * 8 bytes
            adda.l  d2,a2              ;final pointer into playfield buffer

;draw phase block tile(s) with blitter
            move.l  a1,hw_BLT_SRC_ADDR_L.w   ;set blitter source address
            move.w  a2,hw_BLT_DST_ADDR_L+2.w ;set blitter destination address
                                             ;to adjusted playfield pointer
                                             ;can use low word of BLT_DST_ADDR
                                             ;as destination is all within 64k
            moveq   #16,d6                   ;tiles are 16 lines high
            sub.w   d4,d6                    ;subtract line skip = lines to draw
.draw_tile: cmp.w   d1,d6                    ;do we have enough lines left?
            ble.s   .blit                    ;yes, blit them
            move.w  d1,d6                    ;no, use what's left

.blit:      move.w  d6,hw_BLT_COUNT_Y.w      ;blitter y-count is lines to draw
            move.b  #$c0,hw_BLT_CONTROL.w    ;start blitter in HOG mod

            sub.w   d6,d1                    ;update lines to draw
            beq.s   done_bs                  ;if no lines left, then exit
            moveq   #16,d6                   ;tiles are 16 lines high
            lea     LM_W(a0),a0              ;next tile location in level map
            lea     TD_ADDR,a1               ;tile data address
            moveq   #0,d7                    ;for adda.l below
            move.b  (a0),d7                  ;tile index from level map
            lsl.w   #7,d7                    ;tiles are 128 bytes each
            adda.l  d7,a1                    ;final pointer into tile data
            move.w  a1,hw_BLT_SRC_ADDR_L+2.w ;set blitter source address
                                             ;to adjusted tile data address
                                             ;can use low word of BLT_SRC_ADDR
                                             ;as source is all within 64k
            bra.s   .draw_tile               ;draw next tile
done_bs:
    IFNE DEBUG
            move.w  #$000,hw_VID_COLOR0.w    ;rasters enable
    ENDIF
            rts

    data,data

;===============================================================================
;=                                Data Section                                 =
;===============================================================================
;-------------------------------------------------------------------------------
;program variables and storage
;-------------------------------------------------------------------------------
sav_rez:       dc.w   0                ;old resolution
sav_physb:     dc.l   0                ;old physbase
sav_logb:      dc.l   0                ;old logbase
sav_palette:   dcb.w  16               ;old palette
sav_storage:   dcb.b  19               ;old vectors/registers
    even

key_scancode:  dc.b   0                ;scancode returned on keypress event
joy0_header:   dc.b   0                ;header returned on joystick 0 event
joy0_data:     dc.b   0                ;payload returned on joystick 0 event
joy1_header:   dc.b   0                ;header returned on joystick 1 event
joy1_data:     dc.b   0                ;payload returned on joystick 1 event
exit_flag:     dc.b   0                ;set to request program termination

vbl_flag:      dc.w   0                ;to sync with vbl

pf_ramptr:     dc.l   PF_ADDR          ;start of buffer
pf_scrptr:     dc.l   PF_STADDR        ;start of visible display in buffer
pf_currx:      dc.w   PF_STARTX        ;playfield current x-position in pixels
pf_speed:      dc.w   PF_SPEED         ;scroll speed 0,1,2,4,8,-1,-2,-4,-8
pf_dir:        dc.w   21               ;scroll direction offset -1,21
pf_fg:         dc.w   1                ;update column fill gauge 1-16
pf_cs:         dc.w   0                ;coarse scroll flag -1,0,1
pf_lm_cx:      dc.w   LM_STARTX        ;level map current x-position in tiles
pf_prvspd:     dc.w   PF_SPEED         ;prev scroll speed 0,1,2,4,8,-1,-2,-4,-8
pf_curry:      dc.w   PF_STARTY        ;playfield current y-pos in pixels
pf_lm_cy:      dc.w   LM_STARTY        ;level map current y position in tiles

;-------------------------------------------------------------------------------
;table for raster splits - each playfield has the following attributes
;-------------------------------------------------------------------------------
;   1 long    ScrAdr    shifter - video count hi,mid,low screen address
;   1 byte    LWidth    shifter - line width offset
;   1 byte    HScroll   shifter - horizontal scroll value (0-15)
;  16 words   Colors    shifter - palette
;   1 byte    LSplit    timer b - number of lines to count to next split
;  25 bytes   unused    fill bytes to round to 64 for indexing
;-------------------------------------------------------------------------------
splits:     dc.w    0               ;split counter
sbt_vars:   dc.l    SB_TADDR        ;-,ScrAdrH,ScrAdrM,ScrAdrL
            dc.b    0               ;LWidth
            dc.b    0               ;HScroll
            dc.w    $000,$000,$200,$310,$521,$211,$420,$531
            dc.w    $642,$012,$122,$233,$344,$455,$566,$fff     ;Colors
            dc.b    PF_TSPLIT       ;LSplit
            dcb.b   25              ;round up to 64 bytes
pf_vars:    dc.l    PF_STADDR       ;-,ScrAdrH,ScrAdrM,ScrAdrL
            dc.b    PF_LW           ;LWidth
            dc.b    0               ;HScroll
            dc.w    $000,$000,$111,$222,$333,$334,$556,$322
            dc.w    $f65,$643,$f54,$433,$543,$444,$555,$fff     ;Colors
            dc.b    PF_SPLIT        ;LSplit
            dcb.b   25              ;round up to 64 bytes
sbb_vars:   dc.l    SB_BADDR        ;-,ScrAdrH,ScrAdrM,ScrAdrL
            dc.b    0               ;LWidth
            dc.b    0               ;HScroll
            dc.w    $000,$000,$200,$310,$521,$211,$420,$531
            dc.w    $642,$012,$122,$233,$344,$455,$566,$fff     ;Colors
            dc.b    $ff             ;LSplit - end of table
            dcb.b   25              ;round up to 64 bytes

;external assets for testing purposes
td_bin:
    incbin TDATA.BIN
  even
lm_bin:
    incbin LMAP.BIN
  even
sbt_bin:
    incbin TOPBAR.BIN
  even
sbb_bin:
    incbin BOTBAR.BIN
endtext:


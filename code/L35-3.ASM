; Fast assembler implementation of Bresenham's line drawing algorithm
; for the EGA and VGA. Works in modes 0Eh, 0Fh, 10h, and 12h.
; C near-callable.
; Bit mask accumulation technique when |DeltaX| >= |DeltaY|
;  suggested by Jim Mackraz.
;
; Assembled with TASM
;
; By Michael Abrash
;
;****************************************************************
; C-compatible line-drawing entry point at _EVGALine.           *
; Near C-callable as:                                           *
;       EVGALine(X0, Y0, X1, Y1, Color);                        *
;****************************************************************
;
        model small
        .code
;
; Equates.
;
EVGA_SCREEN_WIDTH_IN_BYTES equ  80      ;memory offset from start of
                                        ; one row to start of next
                                        ; in display memory
EVGA_SCREEN_SEGMENT     equ     0a000h  ;display memory segment
GC_INDEX                equ     3ceh    ;Graphics Controller
                                        ; Index register port
SET_RESET_INDEX         equ     0       ;indexes of needed
ENABLE_SET_RESET_INDEX  equ     1       ; Graphics Controller
BIT_MASK_INDEX          equ     8       ; registers

;
; Stack frame.
;
EVGALineParms   struc
        dw      ?               ;pushed BP
        dw      ?               ;pushed return address (make double
                                ; word for far call)
X0      dw      ?               ;starting X coordinate of line
Y0      dw      ?               ;starting Y coordinate of line
X1      dw      ?               ;ending X coordinate of line
Y1      dw      ?               ;ending Y coordinate of line
Color   db      ?               ;color of line
        db      ?               ;dummy to pad to word size
EVGALineParms   ends

;****************************************************************
; Line drawing macros.                                          *
;****************************************************************

;
; Macro to loop through length of line, drawing each pixel in turn.
; Used for case of |DeltaX| >= |DeltaY|.
; Input:
;       MOVE_LEFT: 1 if DeltaX < 0, 0 else
;       AL: pixel mask for initial pixel
;       BX: |DeltaX|
;       DX: address of GC data register, with index register set to
;               index of Bit Mask register
;       SI: DeltaY
;       ES:DI: display memory address of byte containing initial
;               pixel
;
LINE1   macro   MOVE_LEFT
        local   LineLoop, MoveXCoord, NextPixel, Line1End
        local   MoveToNextByte, ResetBitMaskAccumulator
        mov     cx,bx           ;# of pixels in line
        jcxz    Line1End        ;done if there are no more pixels
                                ; (there's always at least the one pixel
                                ; at the start location)
        shl     si,1            ;DeltaY * 2
        mov     bp,si           ;error term
        sub     bp,bx           ;error term starts at DeltaY * 2 - DeltaX
        shl     bx,1            ;DeltaX * 2
        sub     si,bx           ;DeltaY * 2 - DeltaX * 2 (used in loop)
        add     bx,si           ;DeltaY * 2 (used in loop)
        mov     ah,al           ;set aside pixel mask for initial pixel
                                ; with AL (the pixel mask accumulator) set
                                ; for the initial pixel
LineLoop:
;
; See if it's time to advance the Y coordinate yet.
;
        and     bp,bp           ;see if error term is negative
        js      MoveXCoord      ;yes, stay at the same Y coordinate
;
; Advance the Y coordinate, first writing all pixels in the current
; byte, then move the pixel mask either left or right, depending
; on MOVE_LEFT.
;
        out     dx,al           ;set up bit mask for pixels in this byte
        xchg    byte ptr [di],al
                                ;load latches and write pixels, with bit mask
                                ; preserving other latched bits. Because
                                ; set/reset is enabled for all planes, the
                                ; value written actually doesn't matter
        add     di,EVGA_SCREEN_WIDTH_IN_BYTES   ;increment Y coordinate
        add     bp,si           ;adjust error term back down
;
; Move pixel mask one pixel (either right or left, depending
; on MOVE_LEFT), adjusting display memory address when pixel mask wraps.
;
if MOVE_LEFT
        rol     ah,1            ;move pixel mask 1 pixel to the left
else
        ror     ah,1            ;move pixel mask 1 pixel to the right
endif
        jnc     ResetBitMaskAccumulator ;didn't wrap to next byte
        jmp     short MoveToNextByte    ;did wrap to next byte
;
; Move pixel mask one pixel (either right or left, depending
; on MOVE_LEFT), adjusting display memory address and writing pixels
; in this byte when pixel mask wraps.
;
MoveXCoord:
        add     bp,bx           ;increment error term & keep same
if MOVE_LEFT
        rol     ah,1            ;move pixel mask 1 pixel to the left
else
        ror     ah,1            ;move pixel mask 1 pixel to the right
endif
        jnc     NextPixel       ;if still in same byte, no need to
                                ; modify display memory yet
        out     dx,al           ;set up bit mask for pixels in this byte.
        xchg    byte ptr [di],al
                                ;load latches and write pixels, with bit mask
                                ; preserving other latched bits. Because
                                ; set/reset is enabled for all planes, the
                                ; value written actually doesn't matter
MoveToNextByte:
if MOVE_LEFT
        dec     di              ;next pixel is in byte to left
else
        inc     di              ;next pixel is in byte to right
endif
ResetBitMaskAccumulator:
        sub     al,al           ;reset pixel mask accumulator
NextPixel:
        or      al,ah           ;add the next pixel to the pixel mask
                                ; accumulator
        loop    LineLoop
;
; Write the pixels in the final byte.
;
Line1End:
        out     dx,al           ;set up bit mask for pixels in this byte.
        xchg    byte ptr [di],al
                                ;load latches and write pixels, with bit mask
                                ; preserving other latched bits. Because
                                ; set/reset is enabled for all planes, the
                                ; value written actually doesn't matter
        endm

;
; Macro to loop through length of line, drawing each pixel in turn.
; Used for case of DeltaX < DeltaY.
; Input:
;       MOVE_LEFT: 1 if DeltaX < 0, 0 else
;       AL: pixel mask for initial pixel
;       BX: |DeltaX|
;       DX: address of GC data register, with index register set to
;               index of Bit Mask register
;       SI: DeltaY
;       ES:DI: display memory address of byte containing initial
;               pixel
;
LINE2   macro   MOVE_LEFT
        local   LineLoop, MoveYCoord, ETermAction, Line2End
        mov     cx,si           ;# of pixels in line
        jcxz    Line2End        ;done if there are no more pixels
        shl     bx,1            ;DeltaX * 2
        mov     bp,bx           ;error term
        sub     bp,si           ;error term starts at DeltaX * 2 - DeltaY
        shl     si,1            ;DeltaY * 2
        sub     bx,si           ;DeltaX * 2 - DeltaY * 2 (used in loop)
        add     si,bx           ;DeltaX * 2 (used in loop)
;
; Set up initial bit mask & write initial pixel.
;
        out     dx,al
        xchg    byte ptr [di],ah
                                ;load latches and write pixel, with bit mask
                                ; preserving other latched bits. Because
                                ; set/reset is enabled for all planes, the
                                ; value written actually doesn't matter
LineLoop:
;
; See if it's time to advance the X coordinate yet.
;
        and     bp,bp           ;see if error term is negative
        jns     ETermAction     ;no, advance X coordinate
        add     bp,si           ;increment error term & keep same
        jmp     short MoveYCoord; X coordinate
ETermAction:
;
; Move pixel mask one pixel (either right or left, depending
; on MOVE_LEFT), adjusting display memory address when pixel mask wraps.
;
if MOVE_LEFT
        rol     al,1
        sbb     di,0
else
        ror     al,1
        adc     di,0
endif
        out     dx,al           ;set new bit mask
        add     bp,bx           ;adjust error term back down
;
; Advance Y coordinate.
;
MoveYCoord:
        add     di,EVGA_SCREEN_WIDTH_IN_BYTES
;
; Write the next pixel.
;
        xchg    byte ptr [di],ah
                                ;load latches and write pixel, with bit mask
                                ; preserving other latched bits. Because
                                ; set/reset is enabled for all planes, the
                                ; value written actually doesn't matter
;
        loop    LineLoop
Line2End:
        endm

;****************************************************************
; Line drawing routine.                                         *
;****************************************************************

        public  _EVGALine
_EVGALine       proc    near
        push    bp
        mov     bp,sp
        push    si              ;preserve register variables
        push    di
        push    ds
;
; Point DS to display memory.
;
        mov     ax,EVGA_SCREEN_SEGMENT
        mov     ds,ax
;
; Set the Set/Reset and Set/Reset Enable registers for
; the selected color.
;
        mov     dx,GC_INDEX
        mov     al,SET_RESET_INDEX
        out     dx,al
        inc     dx
        mov     al,[bp+Color]
        out     dx,al
        dec     dx
        mov     al,ENABLE_SET_RESET_INDEX
        out     dx,al
        inc     dx
        mov     al,0ffh
        out     dx,al
;
; Get DeltaY.
;
        mov     si,[bp+Y1]      ;line Y start
        mov     ax,[bp+Y0]      ;line Y end, used later in
                                ;calculating the start address
        sub     si,ax           ;calculate DeltaY
        jns     CalcStartAddress;if positive, we're set
;
; DeltaY is negative -- swap coordinates so we're always working
; with a positive DeltaY.
;
        mov     ax,[bp+Y1]      ;set line start to Y1, for use
                                ; in calculating the start address
        mov     dx,[bp+X0]
        xchg    dx,[bp+X1]
        mov     [bp+X0],dx      ;swap X coordinates
        neg     si              ;convert to positive DeltaY
;
; Calculate the starting address in display memory of the line.
; Hardwired for a screen width of 80 bytes.
;
CalcStartAddress:
        shl     ax,1    ;Y0 * 2 ;Y0 is already in AX
        shl     ax,1    ;Y0 * 4
        shl     ax,1    ;Y0 * 8
        shl     ax,1    ;Y0 * 16
        mov     di,ax
        shl     ax,1    ;Y0 * 32
        shl     ax,1    ;Y0 * 64
        add     di,ax   ;Y0 * 80
        mov     dx,[bp+X0]
        mov     cl,dl           ;set aside lower 3 bits of column for
        and     cl,7            ; pixel masking
        shr     dx,1
        shr     dx,1
        shr     dx,1            ;get byte address of column (X0/8)
        add     di,dx           ;offset of line start in display segment
;
; Set up GC Index register to point to the Bit Mask register.
;
        mov     dx,GC_INDEX
        mov     al,BIT_MASK_INDEX
        out     dx,al
        inc     dx              ;leave DX pointing to the GC Data register
;
; Set up pixel mask (in-byte pixel address).
;
        mov     al,80h
        shr     al,cl
;
; Calculate DeltaX.
;
        mov     bx,[bp+X1]
        sub     bx,[bp+X0]
;
; Handle correct one of four octants.
;
        js      NegDeltaX
        cmp     bx,si
        jb      Octant1
;
; DeltaX >= DeltaY >= 0.
;
        LINE1   0
        jmp     EVGALineDone
;
; DeltaY > DeltaX >= 0.
;
Octant1:
        LINE2   0
        jmp     short EVGALineDone
;
NegDeltaX:
        neg     bx      ;|DeltaX|
        cmp     bx,si
        jb      Octant2
;
; |DeltaX| >= DeltaY and DeltaX < 0.
;
        LINE1   1
        jmp     short EVGALineDone
;
; |DeltaX| < DeltaY and DeltaX < 0.
;
Octant2:
        LINE2   1
;
EVGALineDone:
;
; Restore EVGA state.
;
        mov     al,0ffh
        out     dx,al           ;set Bit Mask register to 0ffh
        dec     dx
        mov     al,ENABLE_SET_RESET_INDEX
        out     dx,al
        inc     dx
        sub     al,al
        out     dx,al           ;set Enable Set/Reset register to 0
;
        pop     ds
        pop     di
        pop     si
        pop     bp
        ret
_EVGALine       endp

        end

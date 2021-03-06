; Mode X (320x240, 256 colors) rectangle fill routine. Works on all
; VGAs. Uses medium-speed approach that selects each plane only once
; per rectangle; this results in a fade-in effect for large
; rectangles. Fills up to but not including the column at EndX and the
; row at EndY. No clipping is performed.
; C near-callable as:
;
;    void FillRectangleX(int StartX, int StartY, int EndX, int EndY,
;       unsigned int PageBase, int Color);

SC_INDEX        equ     03c4h   ;Sequence Controller Index
MAP_MASK        equ     02h     ;index in SC of Map Mask register
SCREEN_SEG      equ     0a000h  ;segment of display memory in mode X
SCREEN_WIDTH    equ     80      ;width of screen in bytes from one scan line
                                ; to the next
parms struc
        dw      2 dup (?)       ;pushed BP and return address
StartX  dw      ?               ;X coordinate of upper left corner of rect
StartY  dw      ?               ;Y coordinate of upper left corner of rect
EndX    dw      ?               ;X coordinate of lower right corner of rect
                                ; (the row at EndX is not filled)
EndY    dw      ?               ;Y coordinate of lower right corner of rect
                                ; (the column at EndY is not filled)
PageBase dw     ?               ;base offset in display memory of page in
                                ; which to fill rectangle
Color   dw      ?               ;color in which to draw pixel
parms ends

StartOffset equ  -2             ;local storage for start offset of rectangle
Width    equ     -4             ;local storage for address width of rectangle
Height   equ     -6             ;local storage for height of rectangle
PlaneInfo equ    -8             ;local storage for plane # and plane mask
STACK_FRAME_SIZE equ 8

        .model  small
        .code
        public  _FillRectangleX
_FillRectangleX proc    near
        push    bp              ;preserve caller's stack frame
        mov     bp,sp           ;point to local stack frame
        sub     sp,STACK_FRAME_SIZE ;allocate space for local vars
        push    si              ;preserve caller's register variables
        push    di

        cld
        mov     ax,SCREEN_WIDTH
        mul     [bp+StartY]     ;offset in page of top rectangle scan line
        mov     di,[bp+StartX]
        shr     di,1
        shr     di,1            ;X/4 = offset of first rectangle pixel in scan
                                ; line
        add     di,ax           ;offset of first rectangle pixel in page
        add     di,[bp+PageBase] ;offset of first rectangle pixel in
                                ; display memory
        mov     ax,SCREEN_SEG
        mov     es,ax           ;point ES:DI to the first rectangle pixel's
        mov     [bp+StartOffset],di ; address
        mov     dx,SC_INDEX     ;set the Sequence Controller Index to
        mov     al,MAP_MASK     ; point to the Map Mask register
        out     dx,al
        mov     bx,[bp+EndY]
        sub     bx,[bp+StartY]  ;BX = height of rectangle
        jle     FillDone        ;skip if 0 or negative height
        mov     [bp+Height],bx
        mov     dx,[bp+EndX]
        mov     cx,[bp+StartX]
        cmp     dx,cx
        jle     FillDone        ;skip if 0 or negative width
        dec     dx
        and     cx,not 011b
        sub     dx,cx
        shr     dx,1
        shr     dx,1
        inc     dx              ;# of addresses across rectangle to fill
        mov     [bp+Width],dx
        mov     word ptr [bp+PlaneInfo],0001h
                                ;lower byte = plane mask for plane 0,
                                ; upper byte = plane # for plane 0
FillPlanesLoop:
        mov     ax,word ptr [bp+PlaneInfo]
        mov     dx,SC_INDEX+1   ;point DX to the SC Data register
        out     dx,al           ;set the plane for this pixel
        mov     di,[bp+StartOffset] ;point ES:DI to rectangle start
        mov     dx,[bp+Width]
        mov     cl,byte ptr [bp+StartX]
        and     cl,011b         ;plane # of first pixel in initial byte
        cmp     ah,cl           ;do we draw this plane in the initial byte?
        jae     InitAddrSet ;yes
        dec     dx              ;no, so skip the initial byte
        jz      FillLoopBottom ;skip this plane if no pixels in it
        inc     di
InitAddrSet:
        mov     cl,byte ptr [bp+EndX]
        dec     cl
        and     cl,011b         ;plane # of last pixel in final byte
        cmp     ah,cl           ;do we draw this plane in the final byte?
        jbe     WidthSet        ;yes
        dec     dx              ;no, so skip the final byte
        jz      FillLoopBottom  ;skip this planes if no pixels in it
WidthSet:
        mov     si,SCREEN_WIDTH
        sub     si,dx           ;distance from end of one scan line to start
                                ; of next
        mov     bx,[bp+Height]  ;# of lines to fill
        mov     al,byte ptr [bp+Color] ;color with which to fill
FillRowsLoop:
        mov     cx,dx           ;# of bytes across scan line
        rep     stosb           ;fill the scan line in this plane
        add     di,si           ;point to the start of the next scan
                                ; line of the rectangle
        dec     bx              ;count down scan lines
        jnz     FillRowsLoop
FillLoopBottom:
        mov     ax,word ptr [bp+PlaneInfo]
        shl     al,1            ;set the plane bit to the next plane
        inc     ah              ;increment the plane #
        mov     word ptr [bp+PlaneInfo],ax
        cmp     ah,4            ;have we done all planes?
        jnz     FillPlanesLoop  ;continue if any more planes
FillDone:
        pop     di              ;restore caller's register variables
        pop     si
        mov     sp,bp           ;discard storage for local variables
        pop     bp              ;restore caller's stack frame
        ret
_FillRectangleX endp
        end

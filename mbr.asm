  .inesprg 1   ; 1x 16KB PRG code
  .ineschr 1   ; 1x  8KB CHR data
  .inesmap 0   ; mapper 0 = NROM, no bank swapping
  .inesmir 1   ; background mirroring

;;;;;;;;;;;;;;;

  .rsset $0000                ; Put pointers in Zero Page
pointerLo           .rs 1     ; Low byte first
pointerHi           .rs 1     ; High byte immediately after

numerator           .rs 1
denominator         .rs 1
quotient            .rs 1
remainder           .rs 1

gameState           .rs 1
buttons             .rs 1

; Player sprite positions
playerTopY          .rs 1
playerBottomY       .rs 2
playerLeftX         .rs 1
playerRightX        .rs 1

; Player hitbox
playerHitboxTop     .rs 1
playerHitboxBottom  .rs 1
playerHitboxLeft    .rs 1
playerHitboxRight   .rs 1

playerXSpeed        .rs 1
playerYSpeed        .rs 1
playerFacing        .rs 1     ; 0 = Left. 1 = Right

playerTile          .rs 1
animationIndex      .rs 1

grounded            .rs 1

frameCounter        .rs 1
targetFrame         .rs 1

temp                .rs 1

; CONSTANTS
STATETITLE     = $00  ; Displaying title screen
STATEPLAYING   = $01  ; Move player, check for collisions
STATEGAMEOVER  = $02  ; Displaying game over screen

GRAVITY        = $01  ; Y-axis deceleration
ACCELERATION   = $01  ; X-axis acceleration
XMAXSPEED      = $02  ; Player speed limit along the X axis
YMAXSPEED      = $09  ; Player speed limit along the Y axis

BUTTON_A       = 1 << 7 ; Bit flags for simplified controller polling
BUTTON_B       = 1 << 6 ; For example...
BUTTON_SELECT  = 1 << 5 ;   LDA buttons
BUTTON_START   = 1 << 4 ;   AND #BUTTON_A
BUTTON_UP      = 1 << 3 ;   BEQ NotPressingA
BUTTON_DOWN    = 1 << 2 ;   -- Handle button press --
BUTTON_LEFT    = 1 << 1 ; NotPressingA:
BUTTON_RIGHT   = 1 << 0

  .bank 0
  .org $C000 
RESET:
  SEI          ; disable IRQs
  CLD          ; disable decimal mode
  LDX #$40
  STX $4017    ; disable APU frame IRQ
  LDX #$FF
  TXS          ; Set up stack
  INX          ; now X = 0
  STX $2000    ; disable NMI
  STX $2001    ; disable rendering
  STX $4010    ; disable DMC IRQs

vblankwait1:   ; First wait for vblank to make sure PPU is ready
  BIT $2002
  BPL vblankwait1

clrmem:
  LDA #$00
  STA $0000, x
  STA $0100, x
  STA $0300, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE
  STA $0200, x    ; Move all sprites off screen
  INX
  BNE clrmem
   
vblankwait2:      ; Second wait for vblank, PPU is ready after this
  BIT $2002
  BPL vblankwait2

LoadPalettes:
  LDA $2002    ; read PPU status to reset the high/low latch
  LDA #$3F
  STA $2006    ; write the high byte of $3F00 address
  LDA #$00
  STA $2006    ; write the low byte of $3F00 address
  LDX #$00

LoadPalettesLoop:
  LDA palette, X        ; load palette byte
  STA $2007             ; write to PPU
  INX                   ; set index to next byte
  CPX #$20            
  BNE LoadPalettesLoop  ; if x = $20, 32 bytes copied, all done

LoadSprites:
  LDX #$00             ; Start at 0

LoadSpritesLoop:
  LDA sprites, X       ; Load data from address (sprites + X)
  STA $0200, X         ; Store into RAM address ($0200 + X)
  INX                  ; X++
  CPX #$10             ; Compare X to 10H (16D)
  BNE LoadSpritesLoop  ; Loop until X == 16, then continue

  LDA #$00
  STA $2005
  STA $2005

LoadBackground:
  LDA $2002             ; read PPU status to reset the high/low latch
  LDA #$20
  STA $2006             ; write the high byte of $2000 address
  LDA #$00
  STA $2006             ; write the low byte of $2000 address

  LDA #$00
  STA pointerLo
  LDA #HIGH(background)
  STA pointerHi

  LDX #$00               ; Set X = 0
  LDY #$00               ; Set Y = 0

LoadBackgroundLoop:
  InnerLoop:
    LDA [pointerLo], Y    ; Copy one background byte from address in pointer + YPOS
    STA $2007

    INY
    CPY #$00
    BNE InnerLoop

    INC pointerHi

    INX
    CPX #$04
    BNE LoadBackgroundLoop

SetInitialValues:
  LDA #$00
  STA playerXSpeed
  STA playerYSpeed

  LDA #$01
  STA grounded

; Set player starting position
  LDA #$10
  STA playerLeftX
  LDA #$18
  STA playerRightX
  LDA #$BF
  STA playerTopY
  LDA #$C7
  STA playerBottomY

; Align player hitbox
  JSR AlignPlayerHitbox

; Set starting animation index
  LDA #$36
  STA animationIndex

; Set starting game state
  LDA #STATEPLAYING
  STA gameState
  
  LDA #%10010000   ; Enable NMI, Sprites from Pattern Table 0, BG from Pattern Table 1
  STA $2000

  LDA #%00011110   ; Enable sprites and background
  STA $2001

Forever:
  JMP Forever     ; Jump back to Forever, infinite loop

NMI:
  LDA #$00
  STA $2003  ; set the low byte (00) of the RAM address
  LDA #$02
  STA $4014  ; set the high byte (02) of the RAM address, start the transfer

                    ; PPU Cleanup
  LDA #%10010000    ; Enable NMI, Sprites from Pattern Table 0, Background from Pattern Table 1
  STA $2000

  LDA #%00011110    ; Enable sprites, Enable background, No clipping on left side
  STA $2001

  LDA #$00          ; Tell the ppu there is no background scrolling
  STA $2005
  STA $2005

  ; At this point, all graphics updates have completed. Run game engine.

  JSR ReadController

GameEngine:
  LDA gameState
  CMP #STATETITLE
  BEQ EngineTitle     ; Game is displaying the title screen

  LDA gameState
  CMP #STATEGAMEOVER
  BEQ EngineGameOver  ; Game is displaying ending screen

  LDA gameState
  CMP #STATEPLAYING
  BEQ EnginePlaying   ; Game is playing

GameEngineDone:
  JSR StartUpdate
  RTI                 ; Return from interrupt

EngineTitle:
  ; Incomplete for now
  JMP GameEngineDone

EngineGameOver:
  ; Incomplete for now
  JMP GameEngineDone

EnginePlaying:

ReadController:
  LDA #$01                  ; Latch controllers
  STA $4016
  LDA #$00
  STA $4016

  LDX #$08

ReadControllerLoop:
  LDA $4016
  LSR A                     ; Bit 0 -> Carry
  ROL buttons               ; Bit 0 <- Carry
  DEX
  BNE ReadControllerLoop

HandleZeroInput:
  LDA buttons
  BNE HandleButtonA
  LDA #$00
  STA playerXSpeed
  JMP FinishButtonHandling

HandleButtonA:
  LDA buttons
  AND #BUTTON_A
  BEQ HandleButtonB

  LDA grounded              ; Allow jumping only if player is grounded
  BEQ HandleButtonB
  JSR StartJump

HandleButtonB:
HandleButtonSelect:
HandleButtonStart:
HandleButtonUp:
HandleButtonDown:

HandleButtonLeft:
  LDA buttons
  AND #BUTTON_LEFT
  BEQ HandleButtonRight

  JSR MovePlayerLeft

HandleButtonRight:
  LDA buttons
  AND #BUTTON_RIGHT
  BEQ FinishButtonHandling

  JSR MovePlayerRight

FinishButtonHandling:
  JMP MovePlayerVertically

AlignPlayerHitbox:
  LDA playerLeftX
  CLC
  ADC #$01
  STA playerHitboxLeft

  LDA playerRightX
  CLC
  ADC #$06
  STA playerHitboxRight

  LDA playerTopY
  CLC
  ADC #$01
  STA playerHitboxTop

  LDA playerBottomY
  CLC
  ADC #$07
  STA playerHitboxBottom

  RTS

CheckFrame:             ; Checks if the current frame is divisible by the target frame.
  LDA frameCounter
  CLC

CheckFrameLoop:
  LSR A
  BCS CheckFrameDone
  LSR targetFrame
  BNE CheckFrameLoop
  LDA #$01
  STA targetFrame
  RTS

CheckFrameDone:
  LDA #$00
  STA targetFrame
  RTS

CheckAcceleration:
  LDA playerXSpeed
  CMP #XMAXSPEED
  BCC Accelerate
  RTS

Accelerate:
  ADC #ACCELERATION
  STA playerXSpeed
  RTS

GetPlayerTileLeft:
  LDA playerHitboxLeft
  AND #%11110000
  LSR A
  LSR A
  LSR A
  LSR A
  STA playerTile

  LDA playerHitboxTop           ; First tile checked is stored in Y
  AND #%11110000
  CLC
  ADC playerTile
  TAY

  LDA playerHitboxBottom        ; Second tile checked is stored in playerTile
  AND #%11110000
  CLC
  ADC playerTile
  STA playerTile

  RTS

CheckCollisionLeft:
  JSR AlignPlayerHitbox
  JSR GetPlayerTileLeft

  LDX playerTile
  LDA collisionMap, X
  BNE HandleCollisionLeft

  LDA collisionMap, Y
  BNE HandleCollisionLeft

  RTS

HandleCollisionLeft:
  LDA playerRightX
  CLC
  ADC #$01
  STA playerRightX

  LDA playerLeftX
  CLC
  ADC #$01
  STA playerLeftX

  JMP CheckCollisionLeft

GetPlayerTileRight:
  LDA playerHitboxRight
  AND #%11110000
  LSR A
  LSR A
  LSR A
  LSR A
  STA playerTile

  LDA playerHitboxTop           ; First tile checked is stored in Y
  AND #%11110000
  CLC
  ADC playerTile
  TAY

  LDA playerHitboxBottom        ; Second tile checked is stored in playerTile
  AND #%11110000
  CLC
  ADC playerTile
  STA playerTile

  RTS

CheckCollisionRight:
  JSR AlignPlayerHitbox
  JSR GetPlayerTileRight

  LDX playerTile
  LDA collisionMap, X
  BNE HandleCollisionRight

  LDA collisionMap, Y
  BNE HandleCollisionRight

  RTS

HandleCollisionRight:
  LDA playerRightX
  SEC
  SBC #$01
  STA playerRightX

  LDA playerLeftX
  SEC
  SBC #$01
  STA playerLeftX

  JMP CheckCollisionRight

MovePlayerLeft:
  LDA #$08
  STA targetFrame
  JSR CheckFrame
  LDA targetFrame
  BEQ ContinueMovePlayerLeft
  JSR CheckAcceleration
  
ContinueMovePlayerLeft:
  LDA playerLeftX
  SEC
  SBC playerXSpeed
  STA playerLeftX

  LDA playerRightX
  SEC
  SBC playerXSpeed
  STA playerRightX

  JSR CheckCollisionLeft

MovePlayerLeftDone:
  RTS

FaceLeft:
  LDA playerFacing            ; If the player is already facing left, we don't need to
  BEQ EndSwap                 ; do anything.

  LDA #$00
  STA playerFacing            ; Change player facing to 'Left'
  
  LDA #$40
  STA $0202
  STA $0206
  STA $020A
  STA $020E

SwapXPositions:
  LDA playerLeftX
  STA temp
  LDA playerRightX
  STA playerLeftX
  LDA temp
  STA playerRightX

  RTS

EndSwap:
  RTS

MovePlayerRight:
  LDA #$07
  STA targetFrame
  JSR CheckFrame
  LDA targetFrame
  BEQ ContinueMovePlayerRight
  JSR CheckAcceleration

ContinueMovePlayerRight:
  LDA playerRightX
  CLC
  ADC playerXSpeed
  STA playerRightX

  LDA playerLeftX
  CLC
  ADC playerXSpeed
  STA playerLeftX

  JSR CheckCollisionRight

MovePlayerRightDone:
  RTS

FaceRight:
  LDA playerFacing            ; If the player is already facing right, we don't need
  BNE EndSwap                 ; to do anything.

  LDA #$01
  STA playerFacing            ; Change player facing to 'Right'

  LDA #$00
  STA $0202
  STA $0206
  STA $020A
  STA $020E

  JMP SwapXPositions

SetTileToMinimum:
  LDA #$00
  STA playerTile
  RTS

GetPlayerTileTop:
  LDA playerHitboxTop       ; If character jumps above the ceiling, stop him from going
  CMP #$01                  ; too high
  BCC SetTileToMinimum 

  AND #%11110000
  STA playerTile

  LDA playerHitboxLeft
  AND #%11110000
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC playerTile
  TAY

  LDA playerHitboxRight
  AND #%11110000
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC playerTile
  STA playerTile

  RTS

CheckCollisionTop:
  JSR AlignPlayerHitbox
  JSR GetPlayerTileTop

  LDX playerTile
  LDA collisionMap, X
  BNE HandleCollisionTop

  LDA collisionMap, Y
  BNE HandleCollisionTop

  RTS

HandleCollisionTop:
  LDA #$00
  STA playerYSpeed

  LDA playerTopY
  CLC
  ADC #$01
  STA playerTopY

  LDA playerBottomY
  CLC
  ADC #$01
  STA playerBottomY

  JMP CheckCollisionTop

GetPlayerTileBottom:
  LDA playerHitboxBottom
  AND #%11110000
  STA playerTile

  LDA playerHitboxLeft
  AND #%11110000
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC playerTile
  TAY

  LDA playerHitboxRight
  AND #%11110000
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC playerTile
  STA playerTile

  RTS

CheckCollisionBottom:
  JSR AlignPlayerHitbox
  JSR GetPlayerTileBottom

  LDX playerTile
  LDA collisionMap, X
  BNE HandleCollisionBottom

  LDA collisionMap, Y
  BNE HandleCollisionBottom

  RTS

HandleCollisionBottom:
  LDA #$00
  STA playerYSpeed

  LDA buttons
  AND #BUTTON_A
  BEQ GroundPlayer

  JMP ContinueHandleCollisonBottom

GroundPlayer:
  LDA #$01
  STA grounded

ContinueHandleCollisonBottom:
  LDA playerTopY
  SEC
  SBC #$01
  STA playerTopY

  LDA playerBottomY
  SEC
  SBC #$01
  STA playerBottomY

  JMP CheckCollisionBottom

StartJump:
  LDA #$00
  STA grounded

  LDA #YMAXSPEED
  STA playerYSpeed

  RTS

MovePlayerVertically:

GravityCheck:
  LDA frameCounter                  ; Divide the frame counter by 2
  CLC                               ; If the carry is clear, it means we are on an even
  LSR A                             ; frame
  BCS ContinueMovePlayerVertically

ApplyGravity:
  LDA playerYSpeed
  SEC
  SBC #GRAVITY
  STA playerYSpeed

ContinueMovePlayerVertically:
  LDA playerTopY
  SEC
  SBC playerYSpeed
  STA playerTopY

  LDA playerBottomY
  SEC
  SBC playerYSpeed
  STA playerBottomY

  JSR CheckCollisionTop
  JSR CheckCollisionBottom

MovePlayerVerticallyDone:

EndMovementCycle:

ClearButtons:
  LDA #$00
  STA buttons

  JMP GameEngineDone

StartUpdate:
  INC frameCounter

UpdateSprites:
  LDA playerTopY
  STA $0200
  LDA playerLeftX
  STA $0203

  LDA playerTopY
  STA $0204
  LDA playerRightX
  STA $0207

  LDA playerBottomY
  STA $0208
  LDA playerLeftX
  STA $020B

  LDA playerBottomY
  STA $020C
  LDA playerRightX
  STA $020F

  JSR AlignPlayerHitbox

  RTS

;;;; BANK 1 ;;;; 

  .bank 1
  .org $E000

background:
      ; NTSC Resolution is 256 x 224. We use 256 x 240 to handle cutoff 
      ; [30] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [29] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [28] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [27] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [24] Upper Row - Cloud Tops
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $36,$37,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [25] Upper Row - Cloud Middle
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$35
  .db $25,$25,$38,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [24] Upper Row - Cloud Bottoms
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$39
  .db $3A,$3B,$3C,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [23] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [22] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [21] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [20] Upper Row - Block Tops
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$53,$54,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [19] Upper Row - Block Bottoms
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$55,$56,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [18] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [17] Upper Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [16] Middle Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [15] Middle Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [14] Middle Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [13] Middle Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [12] Middle Row - Brick and Block Tops
  .db $24,$24,$24,$24,$24,$24,$24,$24,$45,$45,$24,$24,$24,$24,$24,$24
  .db $45,$45,$53,$54,$45,$45,$53,$54,$45,$45,$24,$24,$24,$24,$24,$24  

      ; [11] Middle Row - Brick and Block Bottoms
  .db $24,$24,$24,$24,$24,$24,$24,$24,$47,$47,$24,$24,$24,$24,$24,$24
  .db $47,$47,$55,$56,$47,$47,$55,$56,$47,$47,$24,$24,$24,$24,$24,$24

      ; [10] Middle Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [09] Middle Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [08] Ground Row - Sky
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [07] Ground Row - Hill Top
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$31,$32,$24,$24,$24,$24
  .db $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24

      ; [06] Ground Row - Plant Tops
  .db $36,$37,$36,$37,$36,$37,$24,$24,$24,$30,$26,$34,$33,$24,$24,$24
  .db $24,$24,$45,$45,$24,$24,$24,$24,$24,$24,$36,$37,$24,$24,$24,$24

      ; [05] Ground Row - Plant Bottoms
  .db $25,$25,$25,$25,$25,$25,$38,$24,$30,$26,$26,$26,$26,$33,$24,$24
  .db $24,$24,$47,$47,$24,$24,$24,$24,$24,$35,$25,$25,$38,$24,$24,$24

      ; [04] Ground Row - Brick Tops (Upper)
  .db $B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5
  .db $B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5

      ; [03] Ground Row - Brick Bottoms (Upper)
  .db $B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7
  .db $B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7

      ; [02] Ground Row - Brick Tops (Lower)
  .db $B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5
  .db $B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5,$B4,$B5

      ; [01] Ground Row - Brick Bottoms (Lower)
  .db $B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7
  .db $B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7,$B6,$B7

attribute:  ; 8 x 8 = 64 bytes
  .db %10101010, %10101010, %10101010, %10101010
  .db %10101010, %10101010, %10101010, %10101010

  .db %10101010, %10101010, %10101010, %10101010
  .db %10101010, %10101010, %10101010, %10101010

  .db %10101010, %10101010, %10101010, %10101010
  .db %10101010, %01011010, %10101010, %10101010

  .db %10101010, %10101010, %10101010, %10101010
  .db %10101010, %10101010, %10101010, %10101010

  .db %10101010, %10101010, %01010101, %01010101
  .db %01010101, %01010101, %01010101, %10101010

  .db %10101010, %10101010, %00101010, %10101010
  .db %10101010, %10101010, %10101010, %10101010

  .db %11110000, %11110000, %11110000, %11110000
  .db %11111100, %11110000, %11110000, %11110000

  .db %11111111, %11111111, %11111111, %11111111
  .db %11111111, %11111111, %11111111, %11111111

palette:
  .db $22,$29,$1A,$0F,  $22,$36,$17,$0F,  $22,$30,$21,$0F,  $22,$27,$17,$0F   ; Background palette
  .db $22,$16,$36,$17,  $22,$02,$38,$3C,  $22,$1C,$15,$14,  $22,$02,$38,$3C   ; Sprite palette

sprites:
  ;---YPOS--TILE--ATTR--XPOS-----------|
  ;.db $BF,  $32,  $00,  $10  ; Sprite 0
  ;.db $BF,  $33,  $00,  $18  ; Sprite 1
  ;.db $C7,  $34,  $00,  $10  ; Sprite 2
  ;.db $C7,  $35,  $00,  $18  ; Sprite 3

  .db $BF,  $32,  $00,  $10  ; Sprite 0
  .db $BF,  $33,  $00,  $18  ; Sprite 1
  .db $C7,  $34,  $00,  $10  ; Sprite 2
  .db $C7,  $35,  $00,  $18  ; Sprite 3

collisionMap:
      ; 01 -> Blocked
      ; 00 -> Passable

  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$01,$00,$00,$00,$01,$01,$01,$01,$01,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .db $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00
  .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01

  .org $FFFA      ;first of the three vectors starts here
  .dw NMI         ;when an NMI happens (once per frame if enabled) the 
                  ;processor will jump to the label NMI:
  .dw RESET       ;when the processor first turns on or is reset, it will jump
                  ;to the label RESET:
  .dw 0           ;external interrupt IRQ is not used in this tutorial
  
;;;; BANK 2 ;;;; 

  .bank 2
  .org $0000
  .incbin "mario.chr"   ;includes 8KB graphics file from SMB1
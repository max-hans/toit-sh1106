// Copyright (C) 2018 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/**
Driver for the SH1106 i2C OLED display.
This is a 128x64 monochrome display, similar to SSD1306 but with different
  memory addressing. On the Wemos Lolin board the I2C bus is connected to
  pin5 (SDA) and pin4 (SCL), and the SH1106 display is device 0x3c.
  
Key differences from SSD1306:
- Uses page-based addressing instead of column/page range commands
- Requires 2-column offset for 128x64 displays (132-column internal RAM)
- Does not support hardware scrolling commands
*/

import binary
import bitmap show *
import font show *
import gpio
import i2c
import pixel-display.two-color show *
import pixel-display show *
import spi

SH1106-SETMEMORYMODE_ ::= 0x20
// SH1106 does not use 0x21 (COLUMNADDR) or 0x22 (PAGEADDR)
// Instead it uses:
// - 0xB0-0xB7 for page address (0xB0 | page_number)
// - 0x00-0x0F for lower column address (0x00 | low_nibble)
// - 0x10-0x1F for higher column address (0x10 | high_nibble)
SH1106-SET-PAGE-ADDRESS-BASE_ ::= 0xB0
SH1106-SET-LOWER-COLUMN-BASE_ ::= 0x00
SH1106-SET-HIGHER-COLUMN-BASE_ ::= 0x10
// SH1106 does not support hardware scrolling
SH1106-SETSTARTLINE-0_ ::= 0x40
SH1106-SETCONTRAST_ ::= 0x81
SH1106-CHARGEPUMP_ ::= 0x8d
SH1106-SETREMAPMODE-0_ ::= 0xa0
SH1106-SETREMAPMODE-1_ ::= 0xa1
SH1106-SETVERTICALSCROLLAREA_ ::= 0xa3  // Next byte is number of fixed rows.  Next after that is number of scrolling rows.
SH1106-DISPLAYALLON-RESUME_ ::= 0xa4  // End all pixels on (use RAM for image).
SH1106-DISPLAYALLON_ ::= 0xa5         // All pixels on.
SH1106-NORMALDISPLAY_ ::= 0xa6
SH1106-INVERSEDISPLAY_ ::= 0xa7
SH1106-SETMULTIPLEX_ ::= 0xa8
SH1106-DISPLAYOFF_ ::= 0xae
SH1106-DISPLAYON_ ::= 0xaf
SH1106-COMSCANINC_ ::= 0xc0
SH1106-COMSCANDEC_ ::= 0xc8
SH1106-SETDISPLAYOFFSET_ ::= 0xd3
SH1106-SETDISPLAYCLOCKDIV_ ::= 0xd5
SH1106-SETPRECHARGE_ ::= 0xd9
SH1106-SETCOMPINS_ ::= 0xda
SH1106-SETVCOMDETECT_ ::= 0xdb
SH1106-NOP_ ::= 0xe3

/**
Black-and-white driver for an SH1106 connected I2C.
*/
class I2cSh1106 extends Sh1106:
  i2c_ / i2c.Device

  constructor .i2c_ --reset/gpio.Pin?=null --height/int --flip/bool --inverse/bool --layout/int:
    super.from-subclass_ --reset=reset --height=height --flip=flip --inverse=inverse --layout=layout

  buffer-header-size_: return 1

  send-command-buffer_ buffer:
    buffer[0] = 0x00
    i2c_.write buffer

  send-data-buffer_ buffer:
    buffer[0] = 0x40
    i2c_.write buffer

/**
Black-and-white driver for an SH1106 connected over SPI.
*/
class SpiSh1106 extends Sh1106:
  device_ / spi.Device

  constructor .device_ --reset/gpio.Pin?=null --height/int --flip/bool --inverse/bool --layout/int:
    super.from-subclass_ --reset=reset --height=height --flip=flip --inverse=inverse --layout=layout

  buffer-header-size_: return 0

  send-command-buffer_ buffer:
    device_.transfer buffer --dc=0

  send-data-buffer_ buffer:
    device_.transfer buffer --dc=1

/**
Black-and-white driver for an SH1106 connected over I2C or SPI.
Intended to be used with the Pixel-Display package
  at https://pkg.toit.io/package/github.com%2Ftoitware%2Ftoit-pixel-display@v2.11.0
See https://docs.toit.io/language/sdk/display
*/
abstract class Sh1106 extends AbstractDriver:
  static I2C-ADDRESS ::= 0x3c
  static I2C-ADDRESS-ALT ::= 0x3d

  /**
  Sequential layout.

  The lines of the display are laid out sequentially.
  Hardware line "COM0" is connected to row 0 of the display.
  Hardware line "COM32" is connected to row 32 of the display.
  */
  static LAYOUT-SEQUENTIAL ::= 0
  /**
  Sequential switched layout.

  A common layout for 32-line displays.

  The lines of the display are laid out sequentially.
  Hardware line "COM0" is connected to row 32 of the display.
  Hardware line "COM32" is connected to row 0 of the display.

  Compared to $LAYOUT-SEQUENTIAL, lines 0-31 and 32-63 are swapped.
  */
  static LAYOUT-SEQUENTIAL-SWITCHED ::= 2

  /**
  Alternated layout.

  A common layout for 64-line displays.

  The lines of the display are laid out interleaved.
  Hardware line "COM0" is connected to row 0 of the display, "COM1" to row 2, ...
  Hardware line "COM32" is connected to row 1 of the display, "COM33" to row 3, ...
  */
  static LAYOUT-ALTERNATED ::= 1

  /**
  Alternated switched layout.

  The lines of the display are laid out interleaved.
  Hardware line "COM0" is connected to row 1 of the display, "COM1" to row 3, ...
  Hardware line "COM32" is connected to row 0 of the display, "COM33" to row 2, ...
  */
  static LAYOUT-ALTERNATED-SWITCHED ::= 3

  /**
  Constructs a driver for an SH1106 connected over I2C.

  The $reset pin is optional. If provided, it is used to reset the display.
  The $height parameter is the height of the display in pixels, and must be
    either 32 or 64.
  The $flip parameter controls whether the display is flipped vertically.
  The $inverse parameter controls whether the display is inverted. That is,
    whether a pixel value of 0 means "on" or "off".
  The $layout parameter controls how the SH1106 chip is physically connected
    to the rows of the display. Must be one of
    $LAYOUT-SEQUENTIAL, $LAYOUT-SEQUENTIAL-SWITCHED, $LAYOUT-ALTERNATED, or
    $LAYOUT-ALTERNATED-SWITCHED.

  It is safe to use the wrong $flip, $inverse and $layout parameters. The
    display will still work, but the image will be upside-down, inverted, or
    scrambled. If the display doesn't show the correct image, try changing
    these parameters. Note that rotations can be fixed by picking a different
    initial transform on the PixelDisplay.
  */
  constructor.i2c device/i2c.Device
      --reset/gpio.Pin?=null
      --height/int=64
      --flip/bool=false
      --inverse/bool=false
      --layout/int=(height == 32 ? LAYOUT-SEQUENTIAL-SWITCHED : LAYOUT-ALTERNATED):
    return I2cSh1106 device --reset=reset --height=height --flip=flip --inverse=inverse --layout=layout

  /**
  Variant of $Sh1106.i2c that takes an SPI device instead of an I2C device.
  */
  constructor.spi device/spi.Device
      --reset/gpio.Pin?=null
      --height/int=64
      --flip/bool=false
      --inverse/bool=false
      --layout/int=(height == 32 ? LAYOUT-SEQUENTIAL-SWITCHED : LAYOUT-ALTERNATED):
    return SpiSh1106 device --reset=reset --height=height --flip=flip --inverse=inverse --layout=layout

  constructor.from-subclass_
      --reset/gpio.Pin?
      --height/int
      --flip/bool
      --inverse/bool
      --layout = (height == 32 ? LAYOUT-SEQUENTIAL-SWITCHED : LAYOUT-ALTERNATED):
    if reset:
      reset.set 0
      sleep --ms=50
      reset.set 1
    if height != 32 and height != 64:
      throw "height must be 32 or 64"
    if layout != LAYOUT-SEQUENTIAL and layout != LAYOUT-SEQUENTIAL-SWITCHED
        and layout != LAYOUT-ALTERNATED and layout != LAYOUT-ALTERNATED-SWITCHED:
      throw "layout must be one of LAYOUT_SEQUENTIAL, LAYOUT_SEQUENTIAL_SWITCHED, LAYOUT_ALTERNATED, LAYOUT_ALTERNATED_SWITCHED"
    this.height = height
    init_ --flip=flip --inverse=inverse --layout=layout

  buffer_ := ByteArray WIDTH_ + 1
  command-buffers_ := [ByteArray 1, ByteArray 2, ByteArray 3, ByteArray 4]

  static WIDTH_ ::= 128
  static HEIGHT_ ::= 64

  width/int ::= WIDTH_
  height/int ::= ?
  flags/int ::= FLAG-2-COLOR | FLAG-PARTIAL-UPDATES

  abstract buffer-header-size_ -> int
  abstract send-command-buffer_ buffer -> none
  abstract send-data-buffer_ buffer -> none

  init_ --flip/bool --inverse/bool --layout/int:
    command_ SH1106-DISPLAYOFF_
    command_ SH1106-SETDISPLAYCLOCKDIV_ 0x80
    command_ SH1106-SETMULTIPLEX_ 0x3f
    command_ SH1106-SETDISPLAYOFFSET_ 0
    command_ SH1106-SETSTARTLINE-0_
    // SH1106 does not use SETMEMORYMODE - page addressing is default
    command_ SH1106-SETREMAPMODE-1_
    if flip:
      command_ SH1106-COMSCANINC_
    else:
      command_ SH1106-COMSCANDEC_
    command_ SH1106-SETCOMPINS_ ((layout << 4) | 0x02)
    command_ SH1106-SETCONTRAST_ 0xcf
    command_ SH1106-SETPRECHARGE_ 0xf1
    command_ SH1106-SETVCOMDETECT_ 0x30
    command_ SH1106-CHARGEPUMP_ 0x14
    // SH1106 does not support hardware scrolling - removed DEACTIVATE-SCROLL
    command_ SH1106-DISPLAYALLON-RESUME_
    if inverse:
      // This driver inverts the meaning of "inverse".
      // Typically displays are oled where the inverse mode is
      // more common.
      command_ SH1106-NORMALDISPLAY_
    else:
      command_ SH1106-INVERSEDISPLAY_
    command_ SH1106-DISPLAYON_

  command_ byte:
    i := buffer-header-size_
    buffer := command-buffers_[i]
    buffer[i] = byte
    send-command-buffer_ buffer

  command_ byte1 byte2:
    i := buffer-header-size_
    buffer := command-buffers_[i + 1]
    buffer[i] = byte1
    buffer[i + 1] = byte2
    send-command-buffer_ buffer

  command_ byte1 byte2 byte3:
    i := buffer-header-size_
    buffer := command-buffers_[i + 2]
    buffer[i] = byte1
    buffer[i + 1] = byte2
    buffer[i + 2] = byte3
    send-command-buffer_ buffer

  draw-two-color left/int top/int right/int bottom/int pixels/ByteArray -> none:
    // SH1106 requires a 2-column offset for 128x64 displays
    // (132-column internal RAM, display starts at column 2)
    COLUMN-OFFSET ::= 2
    start-column := left + COLUMN-OFFSET
    
    // Convert Y coordinates to page numbers (8 rows per page)
    start-page := top >> 3
    end-page := (bottom >> 3) - 1
    
    // SH1106 uses page-based addressing - must be page-aligned
    if (top & 0x07) != 0 or (bottom & 0x07) != 0:
      throw "SH1106 driver requires page-aligned drawing (top and bottom must be multiples of 8)"

    patch-width := right - left
    line-buffer := buffer_[0..patch-width + buffer-header-size_]

    i := 0
    // SH1106 requires setting page and column address for each page
    for page := start-page; page <= end-page; page++:
      // 1. Set Page Address (0xB0 to 0xB7 for 64-line displays)
      command_ (SH1106-SET-PAGE-ADDRESS-BASE_ | page)
      
      // 2. Set Column Address (split into lower and higher nibbles)
      command_ (SH1106-SET-LOWER-COLUMN-BASE_ | (start-column & 0x0F))  // Lower 4 bits
      command_ (SH1106-SET-HIGHER-COLUMN-BASE_ | (start-column >> 4))   // Upper 4 bits

      // 3. Send the data for this page
      line-buffer.replace buffer-header-size_ pixels i i + patch-width
      i += patch-width
      send-data-buffer_ line-buffer

/// I2C ID of an SH1106 display.
SH1106-ID ::= Sh1106.I2C-ADDRESS

# lsm6dso-nv

A driver for ST's LSM6DSO, a six-axis inertial module with a three-axis
accelerometer, a three-axis gyroscope and a temperature sensor, on an I2C
or an SPI bus, specified in ST's data sheet "LSM6DSO: iNEMO inertial
module: always-on 3D accelerometer and 3D gyroscope", DS12140 Rev 3, June
2024.  The driver implements the `Accelerometer`, `Gyroscope`, `Imu`,
`Thermometer` and `Identifiable` traits of
[devices-nv](https://novo-lang.org/packages/devices-nv).  It reads the
accelerometer in milli-g and the gyroscope in milli-degrees per second.
For the LSM6DSOX, which adds a machine learning core and a finite state
machine to the same registers, it also loads the configuration files of
ST's tools and reads the result (see "The LSM6DSOX").

## Install

```sh
novo pkg add lsm6dso-nv
```

## Example

A device program reads the part over I2C.  The breakout's SDA and SCL go
to the board's I2C pins, its CS pin to the supply, which selects I2C, and
its SDO/SA0 pin to ground, which puts the part at 0x6A.  Its INT1 pin is
left low or open while the part powers up.  The program waits the 35 ms
the part takes to turn on, brings it up at 104 Hz, ±2 g and ±250 dps, and
prints one line per pair of samples over RTT.  With the board flat and
face up, `az` is close to 1000 and the gyroscope reads near 0.

```novo norun:needs-pkg
use embedded_hal.{ BoardI2c, BoardGpio }
use dev_bus
use dev_accel.{ AccelMilliG, Accelerometer }
use dev_imu.{ ImuSample, Imu }
use lsm6dso
use lsm6dso.{ Lsm6dso }

// The part's address with the SDO/SA0 pin low.
const ADDR = 0x6A

// A label and a number, written without building a string.
fn field(label: Str, v: Int) [hw]
    hal.uart.write(label)
    hal.uart.write(str.from_int(v))

@tier(embedded)
fn main() [hw]
    let part = Lsm6dso.attach(BoardI2c { id: 0 }, BoardGpio { id: 0 }, dev_bus.wiring_i2c(0, ADDR))
    hal.timer.delay_ms(35)
    if not part.begin()
        hal.uart.write("lsm6dso: no answer\n")
        return
    loop
        if part.accel_ready()
            match part.imu_read()
                Some(s) =>
                    hal.uart.write("lsm6dso")
                    field(" ax=", s.accel.x)
                    field(" ay=", s.accel.y)
                    field(" az=", s.accel.z)
                    field(" gx=", s.gyro.x)
                    field(" gy=", s.gyro.y)
                    field(" gz=", s.gyro.z)
                    hal.uart.write("\n")
                None =>
                    hal.uart.write("lsm6dso: no result\n")
        else
            hal.timer.delay_ms(2)
```

The program is `tests/device_read.nv`.  Build it for a board with:

```sh
novo build --target=nrf52840-dk tests/device_read.nv
novo build --target=nrf54lm20-dk tests/device_read.nv
novo build --target=frdm-mcxn947 tests/device_read.nv
```

| Board | Flash | Of which the program | RAM at start |
|---|---|---|---|
| nRF52840 DK | 13,056 bytes | 1,314 bytes | 2,660 bytes |
| nRF54LM20 DK | 13,908 bytes | 1,368 bytes | 2,644 bytes |
| FRDM-MCXN947 | 23,292 bytes | 7,682 bytes | 2,748 bytes |

The two Nordic board packages answer for I2C and SPI as absent hardware,
so the build removes the code that follows the first bus read, and their
rows are the image without the driver's reading path.  The missing Nordic I2C
driver is tracked as a feature in the novo-lang repository.  The FRDM-MCXN947 board
package drives I2C and SPI, and its row is the image with the driver's
code in it.  The rest of each image is the runtime, the compiler's support
library and tables.  The driver's own code allocates nothing: every buffer
is a fixed-size `Vec` in the caller's frame.

**Hardware: NOT VERIFIED.**  No board carries an LSM6DSO yet.  The program
builds, and the driver's functions run over a double of the part that
follows the data sheet's register map and bus protocols.  A reading from a
part on a board has not been taken.

### The effects

Every function of the driver that reaches the bus declares `[hw]`, and
nothing else.  The driver performs no input or output of its own and
allocates nothing of its own.  The bus functions of devices-nv build one
short frame per transaction inside a `system` block and release it when
the call returns.  The module checks at every tier, `embedded` included.
The program above declares `[hw]` for the same reason.

## The LSM6DSOX: the machine learning core and the finite state machine

The LSM6DSOX is the LSM6DSO with two blocks that run beside the sensor
and leave a result in registers: a machine learning core (MLC) and a
finite state machine (FSM). The MLC computes statistics of the
accelerometer and gyroscope data over a window of samples, the features,
and runs decision trees on them; ST's repository describes a tree as a series
of nodes, each an if-then-else condition that compares a feature with a
threshold. The tree answers a small number, the class, which a host reads at
any time or waits for on an interrupt pin. The FSM runs up to 16 small
programs, each with an output byte and its own interrupt. A configuration is
written by ST's tools (MEMS Studio, which replaced Unico-GUI) as a list of
register writes in a `.ucf` file. The two parts answer 0x6C to WHO_AM_I, so
no register tells them apart, and a program that has an LSM6DSOX says so with
`Lsm6dsox.declare(part)`.

`examples/mlc_activity.nv` loads the file ST publishes for activity
recognition in a smartphone (accelerometer at 26 Hz and ±4 g, one tree of
about 120 nodes on windows of 75 samples) and prints the class each time the
tree's output changes:

```text
lsm6dsox: loaded 773 writes
class Stationary
class Walking
```

```novo norun:needs-pkg
use embedded_hal.{ BoardI2c, BoardGpio }
use dev_bus
use lsm6dso
use lsm6dso.{ Lsm6dso }
use lsm6dsox
use lsm6dsox.{ Lsm6dsox }
use lsm6dsox_ucf
use st_ucf

// Writes the line for the class `v`: its name from the file, or its number
// when the file names none.
@tier(embedded)
fn report(v: Int) [hw]
    hal.uart.write("class ")
    let at = lsm6dsox_ucf.ucf_label_at(st_ucf.activity, 0, v)
    if at >= 0
        label(st_ucf.activity, at)   // writes the name a byte at a time
    else
        digits(v)                    // writes the number a digit at a time
    hal.uart.write("\n")

@tier(embedded)
fn main() [hw]
    bsp.board.init()
    let part = Lsm6dso.attach(BoardI2c { id: 0 }, BoardGpio { id: 0 }, dev_bus.wiring_i2c(0, 0x6A))
    let x = Lsm6dsox.declare(part)
    hal.timer.delay_ms(35)
    if not part.begin()
        hal.uart.write("lsm6dsox: no answer\n")
        return
    let n = x.load_text(st_ucf.activity)
    if n < 0
        hal.uart.write("lsm6dsox: configuration refused\n")
        return
    while true
        let changed = x.mlc_changed()
        if changed >= 0 and (changed & 1) != 0
            let v = x.mlc_output(0)
            if v >= 0
                report(v)
        hal.timer.delay_ms(100)
```

The text of the file, `st_ucf.activity`, is a package asset that the program's
manifest declares (`[assets]`, see `docs/manifest.md` in the novo-lang
repository), so it sits in the image's flash as it is and the reader scans it
there. `tests/device_build.sh` builds the program from a scratch package that
declares the asset, for four boards, and runs the emulated board's image under
QEMU to check that the program reports a part that does not answer:

```sh
bash tests/device_build.sh
```

| Board | Flash | Of which program | Of which tables and data | RAM at start |
|---|---|---|---|---|
| nRF52840 DK | 20,208 bytes | 1,366 bytes | 9,178 bytes | 2,668 bytes |
| nRF54LM20 DK | 21,076 bytes | 1,428 bytes | 9,928 bytes | 2,652 bytes |
| FRDM-MCXN947 | 34,820 bytes | 11,592 bytes | 9,388 bytes | 2,756 bytes |

The tables and data hold the 7,089 bytes of the file. The Nordic board
packages answer for I2C as absent hardware, so their rows are the image
without the driver's reading path, as in the first device program. The loader
and the scanner allocate nothing.

**Hardware: NOT VERIFIED.** No board carries an LSM6DSOX. The functions run
over a double of the part with two register banks and are checked against the
register writes of ST's files, which the double records in order.

### The register banks

The registers of the embedded functions are in a second bank. FUNC_CFG_ACCESS
(0x01, the same in every bank) selects it with bits 7:6, REG_ACCESS: 00 is
the user bank, 01 the sensor hub bank and 10 the embedded functions bank.
Bit 0 belongs to the OIS interface and `bank_set` leaves it as it is. A
part left in the embedded bank answers other registers for every later read,
so each function here that visits the bank puts the user bank back, also when
the work failed, and answers `false` if either the work or the restore failed.
`begin` selects the user bank first for the same reason.

| Register | Bank | What it holds |
|---|---|---|
| 0x05 EMB_FUNC_EN_B | embedded | FSM_EN (bit 0), MLC_EN (bit 4) |
| 0x0A to 0x0D, 0x0E to 0x11 | embedded | EMB_FUNC_INT1, FSM_INT1_A and _B, MLC_INT1, and the same for INT2 |
| 0x46, 0x47 FSM_ENABLE_A, _B | embedded | which of the 16 programs run |
| 0x4C to 0x5B FSM_OUTS1 to 16 | embedded | one output byte for each program |
| 0x5F EMB_FUNC_ODR_CFG_B | embedded | FSM rate, bits 4:3: 12.5, 26, 52 or 104 Hz |
| 0x60 EMB_FUNC_ODR_CFG_C | embedded | MLC rate, bits 5:4: the same four |
| 0x67 EMB_FUNC_INIT_B | embedded | FSM_INIT (bit 0), MLC_INIT (bit 4), requests that do not read back |
| 0x70 to 0x77 MLC0_SRC to MLC7_SRC | embedded | one output byte for each decision tree |
| 0x36, 0x37 FSM_STATUS_A, _B | user | the programs whose output changed |
| 0x38 MLC_STATUS | user | the trees whose output changed |
| 0x5E MD1_CFG, 0x5F MD2_CFG | user | bit 1 lets the embedded functions' interrupts reach INT1 or INT2 |

### Loading a configuration

A `.ucf` file already holds every write: it puts both sensors in power-down,
selects the embedded bank, writes the programs and the trees through the page
registers (PAGE_SEL, PAGE_ADDRESS, PAGE_VALUE, PAGE_RW), enables the function,
routes its interrupt and sets the sensors' rates and full scales last. The
loader writes the entries in order, with the plain write of the part and no
read back, since the page registers do not read back what was written, and
puts the user bank back at the end.

| Function | What it does |
|---|---|
| `conf_load(port, writes)` | a list of writes, each `(address << 8) | value`; the number written, -1 if the bus refused one or the bank could not be put back |
| `conf_load_text(port, text)` | the same, reading the text of a file where it lies; -2 when a line is none of the three kinds of line the format has, after the writes before it |
| `conf_write(port, entry)` | one write |

The load follows `begin`, which resets the part. It changes the rates, the full
scales and the interrupt routing to what the file says: the activity file
leaves the accelerometer at 26 Hz and ±4 g and the gyroscope off, so read the
rates back with `accel_rate_mhz` and `gyro_rate_mhz`. The accelerometer's
rate must be equal to or higher than the MLC's.

### The `.ucf` text

ST's tools write a line to a register write, with comments:

```text
-- Machine Learning Core Tool v9.13.0.0, LSM6DSOX
-- <MLC0_SRC>DT1,0='Stationary',1='Walking',4='Jogging',8='Biking',12='Driving'

Ac 10 00
Ac 01 80
```

A line is blank, a comment (`--` first among the non-blank bytes) or an entry:
`Ac`, an address of two hexadecimal digits and a value of two, in either case,
separated by spaces or tabs, with a carriage return allowed before the line
feed. Anything else is refused and not guessed: the reader answers `UCF_BAD`
and names the line. The comment of a tree gives the class names of its output
values, which `ucf_label_at(text, tree, value)` finds. The files read are in
`tests/data` (see `tests/data/README.md` for their origin and licence).

| Function | Module | What it does |
|---|---|---|
| `ucf_next(text, var pos)` | `lsm6dsox_ucf` | the next entry as `(address << 8) | value`, `UCF_END` or `UCF_BAD`; allocates nothing and counts its loops, so it runs on a device |
| `ucf_count(text)`, `ucf_line_of(text, pos)` | `lsm6dsox_ucf` | the number of entries, and the line number of an offset |
| `ucf_label_at(text, tree, value)`, `ucf_label_len(text, start)` | `lsm6dsox_ucf` | the offset and the length of a class name |
| `ucf_parse(text)`, `ucf_error_line(text)`, `ucf_text(writes)` | `lsm6dsox_host` | for a program on a computer: the list of entries, or `None`; the first bad line; and the list back as text |

### The functions of the embedded bank

| Function | What it does |
|---|---|
| `bank_set(port, bank)`, `bank_get(port)` | the register bank (`BANK_USER`, `BANK_SENSOR_HUB`, `BANK_EMBEDDED`) |
| `emb_read`, `emb_write`, `emb_update` | one visit to the embedded bank for a read, a write that is read back, and a masked update |
| `mlc_enable`, `mlc_enabled`, `mlc_init` | MLC_EN, and the initialisation request |
| `mlc_out(port, n)`, `mlc_outs(port, var dst)` | the output of tree `n` (0 to 7), or of all eight |
| `mlc_status(port)` | MLC_STATUS: a mask, bit 0 for tree 0 |
| `mlc_odr_write(port, mhz)`, `mlc_odr_read(port)` | the rate: the slowest of 12.5, 26, 52 and 104 Hz at or above `mhz`, in thousandths of a hertz |
| `mlc_route_int(port, pin, mask)`, `emb_pin(port, pin, on)` | the interrupt of the trees in `mask` to INT1 or INT2, and the pin's bit for the embedded functions |
| `fsm_enable(port, mask)`, `fsm_enabled(port)`, `fsm_init(port)` | the programs that run, bit 0 for FSM1; the machine is on when the mask is not 0 |
| `fsm_out(port, n)`, `fsm_outs(port, var dst)`, `fsm_status(port)` | the output of program `n` (1 to 16), of all 16, and the programs whose output changed |
| `fsm_odr_write(port, mhz)`, `fsm_odr_read(port)`, `fsm_route_int(port, pin, mask)` | the rate and the routing, as for the MLC |

`Lsm6dsox` (I2C) and `Lsm6dsoxSpi` (SPI) are the types a program uses:
`declare(part)` wraps an `Lsm6dso` or an `Lsm6dsoSpi`, and the methods
`load`, `load_text`, `mlc_output`, `mlc_changed`, `mlc_on`, `route_mlc`,
`fsm_output`, `fsm_changed`, `fsm_set_enabled`, `route_fsm` and the others of
the table call the functions above on it.

devices-nv has no trait for inference. Its planning page proposes that a
sensor with a classifier inside implements the output half only, a class
index; `mlc_output` is that index.

## What it is

An accelerometer measures acceleration along three axes.  At rest it reads
the acceleration of gravity, 1 g, on the axis that points up, so it also
tells which way the board is tilted.  A gyroscope measures the rate of
turn about three axes, in degrees per second (dps), and reads 0 when the
board is still.

Each axis of each sensor is a 16-bit two's complement count.  The step of
a count is not the full scale over 2^15 (Table 2).

| Full scale | ±2 g | ±4 g | ±8 g | ±16 g |
|---|---|---|---|---|
| Accelerometer step | 0.061 mg | 0.122 mg | 0.244 mg | 0.488 mg |

| Full scale | ±125 dps | ±250 dps | ±500 dps | ±1000 dps | ±2000 dps |
|---|---|---|---|---|---|
| Gyroscope step | 4.375 mdps | 8.75 mdps | 17.5 mdps | 35 mdps | 70 mdps |

The accelerometer's full-scale code is not in ascending order: 00, 01, 10
and 11 are ±2, ±16, ±4 and ±8 g (Table 45), while XL_FS_MODE in CTRL8_XL is
clear, which it is after a reset and which the driver keeps.  The
gyroscope has the ±125 dps bit besides.  `GyroRange` has no value for
±125 dps, so `gyro_set_125dps` sets it, `gyro_range` then answers
`GyroRange250dps`, the narrowest value of the trait that holds it, and the
readings are converted at 125 dps.

Each sensor samples at a rate set by four bits.

| Code | 0000 | 0001 | 0010 | 0011 | 0100 | 0101 | 0110 | 0111 | 1000 | 1001 | 1010 | 1011 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Rate (Hz) | off | 12.5 | 26 | 52 | 104 | 208 | 416 | 833 | 1666 | 3332 | 6664 | 1.6 (accelerometer, low power) |

Table 2 gives the last three rates as 1666, 3332 and 6664 Hz, and the
register description of section 9 rounds them to 1.66, 3.33 and 6.66 kHz.
The driver takes Table 2's.  Code 1011 is 1.6 Hz for the accelerometer
when XL_HM_MODE is set, and 12.5 Hz when it is clear; the gyroscope has no
code 1011.

Each sensor has two kinds of power mode (sections 6.2 and 6.3).  High
performance is on after a reset, at every rate.  Setting XL_HM_MODE or
G_HM_MODE, `set_accel_mode` and `set_gyro_mode` with `Lsm6dsoLowPower`,
selects the low-power mode at 12.5, 26 and 52 Hz (and 1.6 Hz for the
accelerometer) and the normal mode at 104 and 208 Hz, which draw less
current and are noisier.  Above 208 Hz the sensor is in high-performance
mode whatever the bit says.

The part has two bus interfaces on the same pins.  CS high selects I2C.

| | I2C | SPI |
|---|---|---|
| Address | 0x6A, or 0x6B with SDO/SA0 high | chip select low |
| Several registers in one read | the address advances while IF_INC is set | the address advances while IF_INC is set |
| Read | register, repeated start, data | control byte with bit 7 set (R/W), then data, with no dummy byte |
| Write | register, then the data | control byte with bit 7 clear, then one byte |
| Clock | 400 kHz | 4 MHz, mode 3 (mode 0 or 3) |

The two buses differ from the LIS3DH's and the BMP390's: the register
address advances by a bit in CTRL3_C, IF_INC, which is set after a reset and
which `begin` sets again, and neither bus has an increment bit of its own.

## What the package contains

| Module | What is in it |
|---|---|
| `lsm6dso` | The types `Lsm6dso` (I2C) and `Lsm6dsoSpi` (SPI), `Lsm6dsoMode`, the trait `Lsm6dsoPort`, the bus framing, the register access, the conversions, the rates and power modes, the FIFO, the self-tests and the bring-up |
| `lsm6dsox` | The register banks, the machine learning core, the finite state machine, the loader of a configuration, and the types `Lsm6dsox` and `Lsm6dsoxSpi` that declare the part an LSM6DSOX |
| `lsm6dsox_ucf` | The reader of the `.ucf` text of ST's tools, and the finder of the class names in its comments |
| `lsm6dsox_host` | For a computer: the list of register writes of a `.ucf` file, and the list back as text |

## How to choose an entry point

A program on a board uses `Lsm6dso` for a part on I2C and `Lsm6dsoSpi` for
a part on SPI.  Each is built by `attach` with the board's bus, its GPIO
and the wiring, as a board's device table builds it.  Both implement
`Accelerometer`, `Gyroscope`, `Imu`, `Thermometer` and `Identifiable`.

| Method | What it does |
|---|---|
| `attach(bus, pins, w)` | the part at `w.addr` (I2C) or with the chip select `w.cs` (SPI); nothing is sent |
| `begin()` | brings the part up, see below |
| `accel_read()`, `gyro_read()`, `imu_read()` | `Accelerometer`, `Gyroscope`, `Imu`: milli-g, milli-degrees per second, and both from one burst of twelve registers |
| `accel_ready()`, `gyro_ready()` | the new-data flags of STATUS_REG |
| `accel_range()`, `accel_set_range(r)`, `gyro_range()`, `gyro_set_range(r)` | the full scales, changed without touching the other bits of the register |
| `accel_rate_hz()`, `accel_set_rate_hz(hz)`, `gyro_rate_hz()`, `gyro_set_rate_hz(hz)` | the rates in whole hertz, and the slowest rate at or above `hz`; 0 powers the sensor down |
| `accel_rate_mhz()`, `set_accel_rate_mhz(mhz)`, `gyro_rate_mhz()`, `set_gyro_rate_mhz(mhz)` | the same in thousandths of a hertz, which has 1.6 Hz and 12.5 Hz exactly |
| `accel_mode()`, `set_accel_mode(m)`, `gyro_mode()`, `set_gyro_mode(m)` | the power modes |
| `temp_read()` | `Thermometer`: the die temperature |
| `device_id()` | `Identifiable`: WHO_AM_I, 0x6C |
| `fifo_begin(n, with_gyro)`, `fifo_end()` | turn the FIFO on in continuous mode with the watermark at `n` words, and off |
| `accel_fifo_count()`, `accel_fifo_read(dst)`, `fifo_take_imu(accel, gyro)` | the FIFO: the word count, the accelerometer's words, and both sensors' |
| `route_int1(mask)`, `route_int2(mask)`, `configure_pins(active_low, open_drain)` | the interrupt pins |
| `accel_test(negative)`, `gyro_test(negative)` | the change in milli-g and in milli-degrees per second that each self-test makes |
| `reg(r)`, `set_reg(r, v)` | one register, and a write that is read back |

`begin` sets the register bank to the user bank, checks WHO_AM_I, resets
the part with SW_RESET and waits for it to clear, sets block data update
and the address increment, turns the I3C block off, turns the I2C block off
on SPI, masks the data-ready while the filters settle, puts the
full-scale mode and the two high-performance bits at their defaults, puts
both data-ready flags on INT1, and starts both sensors at 104 Hz, ±2 g and
±250 dps.  It answers `false` for a part that does not answer 0x6C and for
a register that does not hold what was written.  The LSM6DSOX and the
LSM6DSO32 answer 0x6C as well; the DSO32 has other full scales and is not
supported, and the DSOX's machine learning core is loaded and read with the
functions described under "The LSM6DSOX".

A program that holds its own bus, or a test with a double of the part,
implements `Lsm6dsoPort` over its bus and calls the module's functions,
which take the port: `lsm6dso.imu_read_of(port)`, `lsm6dso.start(port)`.
The framing of each bus is `i2c_read_into`, `i2c_write`, `spi_read_into`
and `spi_write`, generic over `I2cBus` and `SpiBus`.

### The FIFO

The FIFO is an option.  It is 3 KB of words of a tag byte and six data
bytes, and `begin` leaves it off.  `fifo_begin` puts it in continuous
mode, which overwrites the oldest word when it is full, batches the
accelerometer at its present rate and the gyroscope too when asked, and
puts the watermark on INT1 in place of the data-ready flags.  The part
counts words of every kind, so with both sensors batched the count is the
accelerometer's and the gyroscope's together, and the words alternate.

`accel_fifo_read` is the trait's and answers the accelerometer's words:
it takes every word out, because a word can only be read in order, and
drops the gyroscope's.  A program that batches both reads with
`fifo_take_imu`, which fills two lists and stops, without taking a word, as
soon as either is full.  Both convert with the full scales read from the
part before the first word.  Compression is off, so the only tags are the
gyroscope's and the accelerometer's.

## The rules a user needs

1. Wait 35 ms after the part is powered before `begin` (Table 3).  Leave
   INT1 low or open while it powers up: with INT1 tied to VDDIO the part
   comes up on I3C only (sections 5.3 and 7).
2. `begin` has to run before a reading: both sensors are in power-down at
   power-on.
3. A reading is converted at the full scale read in the transaction before
   it.  After a change of range or rate the filters settle for a few
   samples, which the data-ready line is masked for (DRDY_MASK).
4. `accel_set_rate_hz(0)` and `gyro_set_rate_hz(0)` power a sensor down,
   which saves current: Table 3 gives 0.55 mA for both sensors in
   high-performance mode and 170 uA for the accelerometer alone.  The
   temperature sensor is refreshed only while a motion sensor is on.
5. The accelerometer and the gyroscope each have their own rate.
   `imu_read` pairs whatever the two registers hold, so for samples that
   belong together the two rates are set equal and the pair is read when
   both flags are set.
6. The rates in whole hertz are rounded to the nearest, so 12.5 Hz reads as
   13 and 1.6 Hz as 2, and a request for 12 Hz takes 12.5 Hz.  Use the
   thousandths of a hertz for the exact rate.
7. Changing between low-power and high-performance mode while the
   accelerometer runs at code 1011 changes its rate between 1.6 and 12.5
   Hz.
8. The FIFO is configured from bypass: `fifo_begin` writes bypass first,
   then the batch rates and the watermark, then the mode (section 6.5).
   Batching is at the rates the sensors run at, so a change of rate after
   `fifo_begin` leaves the batch rate where it was.
9. The self-tests need the board still.  The driver follows the procedure
   of ST's `lsm6dso_self_test` example: the accelerometer at 52 Hz and ±4 g,
   the gyroscope at 208 Hz and ±2000 dps, the output left to settle for
   100 ms, five samples averaged with the self-test off and five with it
   on.  Table 2 gives the accelerometer's change as 50 to 1700 mg whatever
   the full scale, and the gyroscope's as 150 to 700 dps at ±2000 dps.
   `accel_self_test_within` and `gyro_self_test_within` compare a change
   with them by magnitude.  The sign of the change follows the `negative`
   argument.
10. SPI mode 0 and mode 3 both work (section 5.1), and the driver asks for
    mode 3.  `begin` sets I2C_disable in CTRL4_C on SPI (section 5.1.1), so
    the I2C block does not answer on the shared pins.
11. `device_id` answers `None` for a bus that no part drives: an SPI bus
    reads 0xFF, or 0x00 when held low.

## What is not included

- The embedded functions the LSM6DSO has: the pedometer and step detector,
  tilt detection and significant motion.  NOT IMPLEMENTED.  The embedded
  bank is reachable through `emb_read`, `emb_write` and `emb_update`.
- Training a decision tree.  NOT IMPLEMENTED.  ST's MEMS Studio turns labelled
  data into the `.ucf` file, and this package loads the file.
- The writing of a finite state machine program.  NOT IMPLEMENTED.  ST's
  tool writes the program as register writes, which `conf_load` loads, and
  the package reads the outputs.
- The JSON and the C-header formats of ST's current repository
  (`st-mems-machine-learning-core`), whose lists also carry delay and polling
  operations that the `.ucf` format has not.  NOT IMPLEMENTED.
- The FSM's long counter and its timeout, the latched or pulsed mode of the
  embedded interrupts (PAGE_RW, EMB_FUNC_LIR), the compression of the FIFO,
  the external magnetometer offsets and sensitivity that the MLC reads, and
  the sensor hub.  NOT IMPLEMENTED.  The registers are reachable through
  `emb_read` and `emb_write`.
- The event detectors of the main page: free fall, wake-up, tap and double
  tap, 6D and 4D orientation, and activity and inactivity.  NOT
  IMPLEMENTED; they are configured through TAP_CFG0 to MD2_CFG.
- The sensor hub (the I2C master for external sensors), the auxiliary SPI
  and the OIS interface, and the I3C interface.  NOT IMPLEMENTED.
- The accelerometer's ultra-low-power mode, the filter selection (LPF2,
  the high-pass and the gyroscope's low-pass), the user offsets, the
  timestamp and the FIFO's compression and counters.  NOT IMPLEMENTED.
- The three-wire SPI mode.
- The LSM6DSO32, whose full scales are ±4, ±8, ±16 and ±32 g.
- The async form of the traits, which an `async fn` cannot take as a value
  type.

## Related packages

- [devices-nv](https://novo-lang.org/packages/devices-nv) names the
  traits this driver implements, the wiring record and the register
  helpers it uses.
- [embedded-hal-nv](https://novo-lang.org/packages/embedded-hal-nv) names
  the `I2cBus`, `SpiBus` and `GpioOut` traits and the board handles.
- bmi270-nv drives Bosch's six-axis BMI270, which needs a configuration
  file at power-up.
- lis3dh-nv and adxl345-nv drive accelerometers of the same kind with
  other bus conventions.

## Tests

`novo test` runs the module over a double of the part that answers on an
I2C bus and on an SPI bus: the control byte, the address increment and what
happens when IF_INC is clear, WHO_AM_I, every conversion at every range of
both sensors, the rate codes with the power-mode dependence of code 1011,
the power modes, the FIFO with both kinds of word, the self-tests, the
bring-up from stale settings, and the two types over the host's board
handles.  The log of bytes sent is compared for each entry point.  A second
port refuses a chosen write or read of a chosen register, which reaches
the refusals a read-only register cannot.  A second suite, `tests/lsm6dsox_tests.nv`, runs the embedded
functions over a double with two register banks: the bank register and the
bit it keeps, each visit to the bank with the user bank put back also when the
work or the entry failed, the rates and their reserved bits, the enables, the
outputs, the status registers and the interrupt routing of the FSM and the MLC
with each write refused in turn, the loader on a list and on text, the
scanner on every kind of line it accepts and refuses, and the class names.
The files of ST in `tests/data` are loaded whole: the motion intensity file's
97 writes reach the double in the file's order, each in the bank the file had
selected, and the double's registers hold what the file sets, which is read
back through the functions; the activity file's 773 writes and the FSM file's
44 do the same.  The suites cover every line of
`src/`, and `tests/coverage.sh` measures it:

```sh
NOVO=bin/novo bash tests/coverage.sh
```

**Hardware: NOT VERIFIED.**  See the example section.

The sources read for this driver, for their fixes and not ported, are the
data sheet above, ST's platform-independent driver `lsm6dso_reg` and its
`lsm6dso_self_test` example, and Zephyr's `drivers/sensor/st/lsm6dso`.
Embassy and esp-hal hold no driver for the part.  Each fix kept is named
in `src/lsm6dso.nv` where it is kept.

For the LSM6DSOX the documents are ST's application notes AN5272, "LSM6DSOX:
Machine Learning Core", and AN5273, "LSM6DSOX: Finite State Machine", which are
cited by number: ST's server refused the requests for them and for the data
sheet, so none was read. The registers are from ST's platform-independent
driver `lsm6dsox_reg.h` and `.c` (`STMicroelectronics/lsm6dsox-pid`, commit
`2e86793125f7`) and its example `lsm6dsox_mlc.c` in
`STMicroelectronics/STMems_Standard_C_drivers` (commit `1f848c38e84b`). The
`.ucf` format and the three files are from
`STMicroelectronics/STMems_Machine_Learning_Core` (BSD 3-Clause, commit
`ebaa9adf137f`, discontinued in July 2025), and the descriptions of the core and
of the activity file from the README files of
`STMicroelectronics/st-mems-machine-learning-core` (commit `aa567b9b9f85`). The
pitfalls taken from them are named in `src/lsm6dsox.nv`:

- ST's driver restores the user bank also when the work failed, and keeps the
  OIS bit of FUNC_CFG_ACCESS when it selects a bank; so do the functions here.
- ST's driver writes the unused bits of EMB_FUNC_ODR_CFG_B as 3 and 2 with the
  FSM rate, which the files do too (0x4B for 26 Hz); `fsm_odr_write` does.
- ST's example resets the part before it loads a file, and the file writes
  both rates to 0 first and to its own values last, so the load follows `begin`
  and the rates change.
- A file written for a part with a tool of 2019 to 2025 holds only entries of
  the one kind `Ac`; the reader refuses a line of another kind and names it,
  where a reader that skips it would load half a configuration.

## Licence

Apache-2.0.

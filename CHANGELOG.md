# Changelog

## 0.1.0

The first release: a driver for ST's LSM6DSO six-axis inertial module on an
I2C or an SPI bus.

- `Lsm6dso` (I2C) and `Lsm6dsoSpi` (SPI), the types a board's device table
  builds, implementing devices-nv's `Accelerometer`, including the FIFO,
  `Gyroscope`, `Imu`, `Thermometer` and `Identifiable`, with their own
  methods for the rates in thousandths of a hertz, the power modes, the
  ±125 dps range, the interrupt pins, the FIFO with both sensors' words,
  the self-tests and register access.
- The register access as functions over `Lsm6dsoPort`, a trait that a type
  holding a bus implements, and the framing of each bus as functions over
  `I2cBus` and `SpiBus`.  An SPI read carries no dummy byte, and neither bus
  has an increment bit of its own: the address advances while IF_INC is
  set, which `begin` sets.
- Readings in milli-g at 0.061 to 0.488 mg a count and in milli-degrees per
  second at 4.375 to 70 mdps a count, converted with the full scales read
  in the transaction before the sample, the accelerometer's full-scale code
  in the order of Table 45.
- The output data rates from 12.5 Hz to 6664 Hz and the accelerometer's 1.6
  Hz, the dependence of code 1011 on XL_HM_MODE, and the high-performance
  and low-power modes of each sensor.
- The FIFO as an option: off after `begin`, on in continuous mode through
  `fifo_begin`, with the accelerometer's words and, when asked, the
  gyroscope's.
- The self-tests of both sensors as functions that answer the change, and
  comparisons with Table 2's limits.
- A reset with SW_RESET, finished when the bit reads 0, after the register
  bank is set to the user bank, then block data update, the address
  increment, I3C off, I2C off on SPI and the data-ready masked while the
  filters settle.
- The suite runs over a double of the part on both buses and covers every
  line of `src/`.

### Known

- Hardware verification: NOT VERIFIED.  No board carries an LSM6DSO.
- The embedded functions (the pedometer, tilt, significant motion, the
  finite state machine and the LSM6DSOX's machine learning core), the event
  detectors, the sensor hub, the auxiliary SPI and OIS, the ultra-low-power
  mode, the filters and the timestamp are NOT IMPLEMENTED.
- The data sheet read is DS12140 Rev 3 (June 2024).  The self-test
  procedure is ST's `lsm6dso_self_test` example, with a count of samples in
  place of its 100 ms waits, since the driver has no timer.
- The device program builds for the nRF52840 DK and the nRF54LM20 DK, whose
  board packages answer for I2C and SPI as absent hardware: on those images
  `begin` answers `false` until the boards drive the buses.  The gap is
  tracked by `features/embedded-devex/nordic-twim-i2c-driver.md`.

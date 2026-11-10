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
- The LSM6DSOX's machine learning core and finite state machine, in the new
  modules `lsm6dsox`, `lsm6dsox_ucf` and `lsm6dsox_host`, from ST's
  application notes AN5272 and AN5273 (cited by number, not read), ST's
  platform-independent driver and the `.ucf` files of ST's repository:
  - the register banks of FUNC_CFG_ACCESS, `bank_set` and `bank_get`, and the
    visits to the embedded bank (`emb_read`, `emb_write`, `emb_update`) that
    put the user bank back also when the work failed;
  - the MLC: enable, initialisation request, rate, the output of each of the
    eight trees, the status register and the interrupt routing;
  - the FSM: the programs enabled, the initialisation request, rate, the 16
    output bytes, the status registers and the interrupt routing;
  - `conf_load`, which loads a configuration given as a list of register
    writes, and `conf_load_text`, which reads the text of a `.ucf` file where
    it lies and allocates nothing;
  - the reader of the `.ucf` text, `ucf_next`, `ucf_count`, `ucf_line_of`, and
    the finder of the class names in its comments, `ucf_label_at` and
    `ucf_label_len`; for a program on a computer, `ucf_parse`,
    `ucf_error_line` and `ucf_text` build the list of writes and print it back;
  - `Lsm6dsox` and `Lsm6dsoxSpi`, the types that declare an `Lsm6dso` or an
    `Lsm6dsoSpi` to be an LSM6DSOX, since WHO_AM_I is 0x6C on both parts;
  - a device program, `examples/mlc_activity.nv`, that loads ST's "Activity
    recognition for mobile" file as a package asset and prints the class, and
    `tests/device_build.sh` and `tests/coverage.sh`;
  - the three `.ucf` files of ST in `tests/data`, with their licence (BSD
    3-Clause) and origin, and a second suite, `tests/lsm6dsox_tests.nv`.
- The manifest declares the embedded tier.

### Known

- Hardware verification: NOT VERIFIED.  No board carries an LSM6DSO or an
  LSM6DSOX.
- The pedometer, tilt and significant motion, the event detectors, the sensor hub, the auxiliary SPI and OIS, the ultra-low-power
  mode, the filters and the timestamp are NOT IMPLEMENTED.
- The data sheet read is DS12140 Rev 3 (June 2024).  The self-test
  procedure is ST's `lsm6dso_self_test` example, with a count of samples in
  place of its 100 ms waits, since the driver has no timer.
- The device program builds for the nRF52840 DK and the nRF54LM20 DK, whose
  board packages answer for I2C and SPI as absent hardware: on those images
  `begin` answers `false` until the boards drive the buses.  The gap is
  tracked by `features/embedded-devex/nordic-twim-i2c-driver.md`.
- Training a decision tree and writing a finite state machine program are NOT
  IMPLEMENTED: ST's tools produce the `.ucf` file.  The JSON and the C-header
  formats of ST's current repository are NOT IMPLEMENTED.  The FSM's long
  counter, the latched or pulsed mode of the embedded interrupts and the
  sensor hub's use by the MLC are NOT IMPLEMENTED.
- The application notes AN5272 and AN5273 and the data sheet of the LSM6DSOX
  were not read: ST's server refused the requests.

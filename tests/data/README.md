# Test data

The three `.ucf` files here are configuration files of STMicroelectronics for
the LSM6DSOX, copied unchanged from the repository
`STMicroelectronics/STMems_Machine_Learning_Core` (commit
`ebaa9adf137fc9edf7137f6c887e1ff32a0dba40`, July 2025, the last before
the repository was discontinued in favour of
`STMicroelectronics/st-mems-machine-learning-core`, whose files are JSON and C
headers and not `.ucf`). The licence of that repository, BSD 3-Clause,
Copyright (c) 2019 STMicroelectronics, is in `ST-LICENSE.txt`, and applies to
the three files.

| File | Path in the repository | MD5 |
|---|---|---|
| `lsm6dsox_activity_recognition_for_mobile.ucf` | `application_examples/lsm6dsox/Activity recognition for mobile/` | `b6db7f92ec45c5b06fb64d5a0843b780` |
| `lsm6dsox_motion_intensity.ucf` | `application_examples/lsm6dsox/Motion intensity/` | `ad5c131cce38e08b894f2659278b6fec` |
| `lsm6dsox_fsm.ucf` | `configuration_examples/example_6_sensortilebox_unico_unicleo/2_fsm/` | `2c986be67fc273800b3b7b43d83ed91e` |

The first holds a decision tree of about 120 nodes that tells stationary,
walking, jogging, biking and driving from the accelerometer at 26 Hz. The second
holds a tree with eight classes of motion intensity. The third holds a
finite state machine program.

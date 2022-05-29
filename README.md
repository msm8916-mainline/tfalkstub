# tfalkstub
[tfalkstub] is a simple stub firmware that allows using the 32-bit "Little Kernel" (LK)
bootloader from Qualcomm on top of 64-bit [Trusted Firmware-A (TF-A)]. It switches the
CPU to 32-bit mode and emulates required Secure Monitor Calls (SMC) to make LK work
properly.

The following Qualcomm SoCs are supported by [tfalkstub] (and TF-A) so far:

  - [Snapdragon 410 (MSM8916/APQ8016)](https://trustedfirmware-a.readthedocs.io/en/latest/plat/qti-msm8916.html)

[tfalkstub] is loaded at address `0x86400000`, while LK should be loaded at `0x8f600000`.
All control is handed over to the actual operating system after LK has finished running.
A 64-bit kernel should be loaded from LK; the emulation layer for 32-bit kernels in [tfalkstub]
is not designed to be used for anything except LK. Booting e.g. 32-bit Linux (instead of 64-bit)
may produce unexpected results.

## Installation
[Build and install TF-A for `msm8916`](https://trustedfirmware-a.readthedocs.io/en/latest/plat/qti-msm8916.html)
with the following configuration (this will make it jump to [tfalkstub] instead
of directly to the `aboot` firmware):

```
$ make CROSS_COMPILE=aarch64-linux-gnu- PLAT=msm8916 PRELOADED_BL33_BASE=0x86400000
```

Build [tfalkstub]:

```
$ make CROSS_COMPILE=aarch64-linux-gnu-
```

The resulting ELF file must be "signed" before flashing it, even if the board has
secure boot disabled. In this case the signature does not provide any security,
but it provides the firmware with required metadata.

On boards without secure board you can use [qtestsign] to sign the firmware with
automatically generated test keys:

```
$ ./qtestsign.py hyp tfalkstub.elf
```

**Tip:** If you clone [qtestsign] directly into your [tfalkstub] clone,
running `make` will also automatically sign the binary!

Install the resulting `tfalkstub-test-signed.mbn` to the `hyp` partition.

**WARNING:** Do not flash incorrectly signed firmware on devices that have secure boot
enabled! Make sure that you have a way to recover the board in case of problems (e.g. using EDL).

## License
[tfalkstub] is based on [qhypstub] and is also licensed under the
[GNU General Public License, version 2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html).

[tfalkstub]: https://github.com/msm8916-mainline/tfalkstub
[Trusted Firmware-A (TF-A)]: https://trustedfirmware-a.readthedocs.io/
[qtestsign]: https://github.com/msm8916-mainline/qtestsign
[qhypstub]: https://github.com/msm8916-mainline/qhystub

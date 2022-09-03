# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2021 Stephan Gerhold
OBJCOPY ?= objcopy

AS := $(CROSS_COMPILE)$(AS)
LD := $(CROSS_COMPILE)$(LD)
OBJCOPY := $(CROSS_COMPILE)$(OBJCOPY)

.PHONY: all
all: tfalkstub32.elf tfalkstub32.bin

tfalkstub32.elf: tfalkstub32.o tfalkstub32.ld
	$(LD) -n -T tfalkstub32.ld $(LDFLAGS) -o $@ $<

tfalkstub32.bin: tfalkstub32.elf
	$(OBJCOPY) -O binary $< $@

tfalkstub32-test-signed.mbn: tfalkstub32.elf
	../qtestsign/qtestsign.py hyp -o $@ $<

# Attempt to sign by default if qtestsign was cloned in the same directory
ifneq ($(wildcard ../qtestsign/qtestsign.py),)
all: tfalkstub32-test-signed.mbn
endif

.PHONY: clean
clean:
	rm -f *.o *.elf *.bin *.mbn

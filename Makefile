# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2021 Stephan Gerhold
OBJCOPY ?= objcopy

AS := $(CROSS_COMPILE)$(AS)
LD := $(CROSS_COMPILE)$(LD)
OBJCOPY := $(CROSS_COMPILE)$(OBJCOPY)

.PHONY: all
all: tfalkstub.elf tfalkstub.bin

tfalkstub.elf: tfalkstub.o tfalkstub.ld
	$(LD) -n -T tfalkstub.ld $(LDFLAGS) -o $@ $<

tfalkstub.bin: tfalkstub.elf
	$(OBJCOPY) -O binary $< $@

tfalkstub-test-signed.mbn: tfalkstub.elf
	qtestsign/qtestsign.py hyp -o $@ $<

# Attempt to sign by default if qtestsign was cloned in the same directory
ifneq ($(wildcard qtestsign/qtestsign.py),)
all: tfalkstub-test-signed.mbn
endif

.PHONY: clean
clean:
	rm -f *.o *.elf *.bin *.mbn

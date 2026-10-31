name := gfxinit

ifeq ($(MAKECMDGOALS),gfx_test)
prefixed-name	:= gfx_test
link-type	:= program
GFXINIT_TEST	:= y
endif

gfxinit-deplibs := libhw

libhw-dir ?= ../libhwbase/dest
include $(libhw-dir)/Makefile

$(gfxinit-objs): ADAFLAGS += -gnaty3abdefhiklnprSx

# Allow statements after then/else as we arrange cmdline parsing as a table
$(call src-to-obj,,gfxtest/hw-gfx-gma-gfx_test.adb): ADAFLAGS += -gnaty-S

gfx_test: $(binary)

phony_gpr: gfxinit_baytrail.gpr
	sed -i -e's/".*spark\.adc"/"spark.adc"/' $<
proof-allconfigs/baytrail/gnatprove/gnatprove.out: phony_gpr

.PHONY: gfx_test phony_gpr

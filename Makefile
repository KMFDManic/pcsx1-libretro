# Makefile for PCSX ReARMed

# default stuff goes here, so that config can override
TARGET ?= pcsx
CFLAGS += -Wall -ggdb -Iinclude -ffast-math
ifndef DEBUG
CFLAGS += -O2 -DNDEBUG
endif
CXXFLAGS += $(CFLAGS)
#DRC_DBG = 1
#PCNT = 1

all: target_ plugins_

-include Makefile.local

CC_LINK ?= $(CC)
CC_AS ?= $(CC)
LDFLAGS += $(MAIN_LDFLAGS)
EXTRA_LDFLAGS ?= -Wl,-Map=$@.map
LDLIBS += $(MAIN_LDLIBS)
ifdef PCNT
CFLAGS += -DPCNT
endif

# core
OBJS += libpcsxcore/cdriso.o libpcsxcore/cdrom.o libpcsxcore/cheat.o libpcsxcore/debug.o \
	libpcsxcore/decode_xa.o libpcsxcore/disr3000a.o libpcsxcore/mdec.o \
	libpcsxcore/misc.o libpcsxcore/plugins.o libpcsxcore/ppf.o libpcsxcore/psxbios.o \
	libpcsxcore/psxcommon.o libpcsxcore/psxcounters.o libpcsxcore/psxdma.o libpcsxcore/psxhle.o \
	libpcsxcore/psxhw.o libpcsxcore/psxinterpreter.o libpcsxcore/psxmem.o libpcsxcore/r3000a.o \
	libpcsxcore/sio.o libpcsxcore/socket.o libpcsxcore/spu.o
OBJS += libpcsxcore/gte.o libpcsxcore/gte_nf.o libpcsxcore/gte_divider.o
ifeq "$(ARCH)" "arm"
OBJS += libpcsxcore/gte_arm.o
endif
ifeq "$(HAVE_NEON)" "1"
OBJS += libpcsxcore/gte_neon.o
endif
libpcsxcore/psxbios.o: CFLAGS += -Wno-nonnull

# dynarec
ifeq "$(USE_DYNAREC)" "1"
OBJS += libpcsxcore/new_dynarec/new_dynarec.o libpcsxcore/new_dynarec/linkage_arm.o
OBJS += libpcsxcore/new_dynarec/pcsxmem.o
else
libpcsxcore/new_dynarec/emu_if.o: CFLAGS += -DDRC_DISABLE
frontend/libretro.o: CFLAGS += -DDRC_DISABLE
endif
OBJS += libpcsxcore/new_dynarec/emu_if.o
libpcsxcore/new_dynarec/new_dynarec.o: libpcsxcore/new_dynarec/assem_arm.c \
	libpcsxcore/new_dynarec/pcsxmem_inline.c
libpcsxcore/new_dynarec/new_dynarec.o: CFLAGS += -Wno-all -Wno-pointer-sign
ifdef DRC_DBG
libpcsxcore/new_dynarec/emu_if.o: CFLAGS += -D_FILE_OFFSET_BITS=64
CFLAGS += -DDRC_DBG
endif
ifeq "$(DRC_CACHE_BASE)" "1"
libpcsxcore/new_dynarec/%.o: CFLAGS += -DBASE_ADDR_FIXED=1
endif

# spu
OBJS += plugins/dfsound/dma.o plugins/dfsound/freeze.o \
	plugins/dfsound/registers.o plugins/dfsound/spu.o \
	plugins/dfsound/out.o
plugins/dfsound/spu.o: plugins/dfsound/adsr.c plugins/dfsound/reverb.c \
	plugins/dfsound/xa.c
ifeq "$(ARCH)" "arm"
OBJS += plugins/dfsound/arm_utils.o
endif
ifneq ($(findstring libretro,$(SOUND_DRIVERS)),)
plugins/dfsound/out.o: CFLAGS += -DHAVE_LIBRETRO
endif

# builtin gpu
OBJS += plugins/gpulib/gpu.o plugins/gpulib/vout_pl.o
ifeq "$(BUILTIN_GPU)" "neon"
OBJS += plugins/gpu_neon/psx_gpu_if.o plugins/gpu_neon/psx_gpu/psx_gpu_arm_neon.o
plugins/gpu_neon/psx_gpu_if.o: CFLAGS += -DNEON_BUILD -DTEXTURE_CACHE_4BPP -DTEXTURE_CACHE_8BPP
plugins/gpu_neon/psx_gpu_if.o: plugins/gpu_neon/psx_gpu/*.c
endif
ifeq "$(BUILTIN_GPU)" "peops"
# note: code is not safe for strict-aliasing? (Castlevania problems)
plugins/dfxvideo/gpulib_if.o: CFLAGS += -fno-strict-aliasing
plugins/dfxvideo/gpulib_if.o: plugins/dfxvideo/prim.c plugins/dfxvideo/soft.c
OBJS += plugins/dfxvideo/gpulib_if.o
endif
ifeq "$(BUILTIN_GPU)" "unai"
OBJS += plugins/gpu_unai/gpulib_if.o
ifeq "$(ARCH)" "arm"
OBJS += plugins/gpu_unai/gpu_arm.o
endif
plugins/gpu_unai/gpulib_if.o: CFLAGS += -DREARMED -O3 
CC_LINK = $(CXX)
endif

# cdrcimg
OBJS += plugins/cdrcimg/cdrcimg.o

# dfinput
OBJS += plugins/dfinput/main.o plugins/dfinput/pad.o plugins/dfinput/guncon.o

# frontend/gui
OBJS += frontend/cspace.o
ifeq "$(HAVE_NEON)" "1"
OBJS += frontend/cspace_neon.o
else
ifeq "$(ARCH)" "arm"
OBJS += frontend/cspace_arm.o
endif
endif

OBJS += frontend/libretro.o
CFLAGS += -DFRONTEND_SUPPORTS_RGB565

ifeq ($(MMAP_WIN32),1)
OBJS += libpcsxcore/memmap_win32.o
endif

# misc
OBJS += frontend/main.o frontend/plugin.o


frontend/menu.o frontend/main.o: frontend/revision.h
frontend/plat_sdl.o frontend/libretro.o: frontend/revision.h

libpcsxcore/gte_nf.o: libpcsxcore/gte.c
	$(CC) -c -o $@ $^ $(CFLAGS) -DFLAGLESS

frontend/revision.h: FORCE
	@(git describe || echo) | sed -e 's/.*/#define REV "\0"/' > $@_
	@diff -q $@_ $@ > /dev/null 2>&1 || cp $@_ $@
	@rm $@_

%.o: %.S
	$(CC_AS) $(CFLAGS) -c $^ -o $@


target_: $(TARGET)

$(TARGET): $(OBJS)
	$(CC_LINK) -o $@ $^ $(LDFLAGS) $(LDLIBS) $(EXTRA_LDFLAGS)

clean: $(PLAT_CLEAN) clean_plugins
	$(RM) $(TARGET) $(OBJS) $(TARGET).map frontend/revision.h

ifneq ($(PLUGINS),)
plugins_: $(PLUGINS)

$(PLUGINS):
	make -C $(dir $@)

clean_plugins:
	make -C plugins/gpulib/ clean
	for dir in $(PLUGINS) ; do \
		$(MAKE) -C $$(dirname $$dir) clean; done
else
plugins_:
clean_plugins:
endif

.PHONY: all clean target_ plugins_ clean_plugins FORCE

as = nasm
ld = ld
strip = strip

# flags de montagem
asflags = -f elf64 -O3

# mais flags
ldflags = -static -nostdlib -s -n -N --build-id=none \
          --no-dynamic-linker --no-eh-frame-hdr \
          --no-ld-generated-unwind-info -z norelro \
          --hash-style=sysv --gc-sections

# outras flags
sflags = -s -R .comment -R .gnu.version -R .gnu.version_r -R .gnu.hash \
         -R .note -R .note.gnu.build-id -R .note.ABI-tag -R .eh_frame -R .eh_frame_hdr

src = init.asm
obj = init.o
bin = gatinit

all: $(bin)

$(obj): $(src)
	$(as) $(asflags) -o $@ $<

$(bin): $(obj)
	$(ld) $(ldflags) -o $@ $<
	$(strip) $(sflags) $@

clean:
	rm -f $(obj) $(bin)

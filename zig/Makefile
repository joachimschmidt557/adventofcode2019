TASKS=01 01_2 02 02_2 03 03_2 04 04_2 05 05_2 06 06_2 07 07_2 08 08_2 09 09_2 10 11 11_2 12

all: $(TASKS)

.gitignore: Makefile
	true > $@
	echo zig-cache/ >> $@
	for x in $(TASKS); do echo $$x >> $@; done
	for x in $(TASKS); do echo $$x.o >> $@; done

%: %.zig
	zig build-exe $^

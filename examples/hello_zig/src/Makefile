hello: hello.c aux.c base64.o

base64.o:
	zig build
	# extract base64.o from static library.
	ar x zig-out/lib/libziglib.a

# Why write Goa components in Assembly?

The examples of Goa may be used to explore and investigate the interactions between user-land components in Genode and the session interfaces, compatibility layers (e.g. POSIX), and other aspects of the Genode framework.

The `hello_make` example in C++ is great for showcasing how a Genode component should look like and interact with it's environment.

The `hello_posix` example in C illustrates how to make use of POSIX compatibility layers and also illustrates how one can execute code on Genode where the entry point cannot be written as a C++ Component class.

The `hello_rust` example in Rust provides insight into how other languages than C/C++ can be integrated into the Genode userland, what linking is required to have those executables be able to run on Genode (e.g. the `libutil` Rust compatibility library for Genode).

To further explore concepts and interactions within Genode it may be helpful to go down to the low-level constructs, removing as much magic as possible. So, for exploring concepts of linkage requirements, session interface interactions, POSIX compatibility layers and many future investigations that one has yet to imagine, having a Goa example implemented in Assembly language may be instrumental. Of course, NASM would only be suited for x86 architectures. But given this example, Goa users on aarch64 (and other) architecture may easily adapt it to their use cases.

We hope you may enjoy playing around with Goa using assembly, as a way of learning more about the underlying magic of how Genode works.

Please note, that the ABI interface through which Assembly programs would interact with Genode is not considered stable, and for most real use cases, one should use a higher level language to implement components in Goa.

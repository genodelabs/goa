#include <stdio.h>
#include <unistd.h>

/* Genode includes */
#include <base/slab.h>
#include <profile/profile.h>

/* backing store for Slab allocator */
Genode::uint8_t backing_store[8*1024];

/* Slab allocator for Function_info objects */
Genode::Slab    slab { sizeof(Profile::Function_info),
                       sizeof(backing_store), backing_store };

/* Thread_info object for "ep" thread */
Profile::Thread_info info { "ep",                          /* the thread's name */
                            slab,                          /* Function_info allocator */
                            Profile::Milliseconds { 6000 } /* print interval */
                          };   

void dummy_sub()
{
	usleep(100*1000);
}

void dummy()
{
	for (unsigned i=0; i < 10; i++) {
		dummy_sub();
		usleep(1000);
	}
}

int main(int, char **)
{
	printf("Starting profiling test\n");

	Profile::init(2'000'000);
	info.enable();

	for (unsigned i=0; i < 10; i++) {
		dummy();
	}

	printf("Finished\n");
	return 0;
}

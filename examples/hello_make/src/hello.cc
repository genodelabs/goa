#include <base/log.h>
#include <base/component.h>

extern "C" void wait_for_continue();

void Component::construct(Genode::Env &)
{
	Genode::log("Hello");

	wait_for_continue();

	for (int i=0; i < 10; i++) {
		Genode::log("World!");
	}
}

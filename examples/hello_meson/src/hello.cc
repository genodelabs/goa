#include <base/log.h>
#include <base/component.h>

#include <forty_two.h>

void Component::construct(Genode::Env &)
{
	Genode::log("Hello Meson: ", get_forty_two());
}

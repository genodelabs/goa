#include <base/log.h>
#include <base/component.h>

void Component::construct(Genode::Env &)
{
	Genode::log("Hello");
}

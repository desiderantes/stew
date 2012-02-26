#include "example.h"

G_DEFINE_TYPE (ExampleObject, example_object, G_TYPE_OBJECT);

/**
 * example_object_foo:
 *
 * An example method.
 * 
 */
void example_object_foo (void)
{
}

static void
example_object_init (ExampleObject *greeter)
{
}

static void
example_object_class_init (ExampleObjectClass *klass)
{  
}

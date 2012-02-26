#ifndef _EXAMPLE_H_
#define _EXAMPLE_H_

#include <glib-object.h>

G_BEGIN_DECLS

typedef struct
{
    GObject parent_instance;
} ExampleObject;

typedef struct
{
    GObjectClass parent_class;
} ExampleObjectClass;

GType example_object_get_type (void);

void example_object_foo (void);

G_END_DECLS

#endif /* _EXAMPLE_H_ */

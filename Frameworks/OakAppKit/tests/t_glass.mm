#import <OakAppKit/OakUIConstructionFunctions.h>
#import <oak/oak.h>

void test_glass_container_is_a_container ()
{
	NSGlassEffectContainerView* container = OakCreateGlassContainer();
	OAK_ASSERT(container != nil);
	OAK_ASSERT([container isKindOfClass:[NSGlassEffectContainerView class]]);
}

void test_glass_container_does_not_autoresize ()
{
	// Every caller lays these out with Auto Layout; a container that also
	// autoresizes fights its own constraints.
	NSGlassEffectContainerView* container = OakCreateGlassContainer();
	OAK_ASSERT_EQ(container.translatesAutoresizingMaskIntoConstraints, NO);
}

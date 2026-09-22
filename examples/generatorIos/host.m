#import <UIKit/UIKit.h>
#include "fixture.h"
#include <stdio.h>

static int32_t fixtureValue;

@interface IonFixtureDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation IonFixtureDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	UIViewController *controller = [UIViewController new];
	controller.view.backgroundColor = UIColor.systemBackgroundColor;
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, 160, 340, 100)];
	label.numberOfLines = 2;
	label.text = [NSString stringWithFormat:@"Ion iOS generator\nNative value: %d", fixtureValue];
	label.textColor = UIColor.labelColor;
	label.font = [UIFont systemFontOfSize:24];
	[controller.view addSubview:label];
	self.window.rootViewController = controller;
	[self.window makeKeyAndVisible];
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
	NSString *marker = [documents stringByAppendingPathComponent:@"ion-generator.txt"];
	NSError *error = nil;
	if (![label.text writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
		fprintf(stderr, "fixture marker: %s\n", error.description.UTF8String);
		abort();
	}
	printf("Ion UIKit launched: %d\n", fixtureValue);
	fflush(stdout);
	return YES;
}
@end

void ionFixtureRun(int32_t value) {
	fixtureValue = value + ION_FIXTURE_VALUE + 0;
	UIApplicationMain(0, nil, nil, NSStringFromClass(IonFixtureDelegate.class));
}

extern void MsMain(void);
extern int cmdCount;
extern char **cmdLine;
extern char **gEnv;
extern int msProgramResult;

int main(int argc, char **argv, char **env) {
	cmdCount = argc;
	cmdLine = argv;
	gEnv = env;
	@autoreleasepool { MsMain(); }
	return msProgramResult;
}

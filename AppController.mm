#import "AppController.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#import "NSTimerUtils.h"
#import "HoverView.h"
#import "UIViewUtilities.h"
#import "RemoteViewController.h"
#import <GameController/GCController.h>

@interface AppController ()
- (void)axisSnappingChanged:(id)sender;
- (void)tiltModeChanged:(id)sender;
- (void)joystickFloatingChanged:(id)sender;
- (void) setTiltNeutral;
@end


#define ACCELEROMETER_UPDATE_RATE 1.0/30.0

#pragma mark -
@implementation AppController

@synthesize navController=_navController;
@synthesize browserViewController=_browserViewController;
@synthesize window=_window;
@synthesize debugTextLabels=_debugTextLabels;
@synthesize hoverView=_hoverView;
@synthesize logoImage=_logoImage;
@synthesize setTiltNeutralButton=_setTiltNeutralButton;
@synthesize joystickStyleLabel=_joystickStyleLabel;
@synthesize joystickStyleControl=_joystickStyleControl;


AppController* gApp;

- (void) _showAlert:(NSString *)title
{
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:@"Check your networking configuration." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alertView show];
	[alertView release];
}

+ (AppController*) sharedApp
{
	return gApp;
}

+ (void) timerWithInterval:(NSTimeInterval)seconds andBlock:(void (^)())b
{
	[[NSRunLoop currentRunLoop] addTimer:[NSTimer timerWithTimeInterval:seconds repeats:NO usingBlock:b] forMode:NSDefaultRunLoopMode];
}


- (void) applicationDidFinishLaunching:(UIApplication *)application
{
    
    gApp = self;

    self.debugTextLabels = [NSMutableArray arrayWithCapacity:10];

	self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
	[_window setBackgroundColor:[UIColor darkGrayColor]];
	
    self.browserViewController = [[[BrowserViewController alloc] initWithTitle:@"BombSquad Remote" showDisclosureIndicators:NO showCancelButton:NO] autorelease];
    self.browserViewController.delegate = self;
    self.browserViewController.searchingForServicesString = @"Searching For Games";

    [_browserViewController start];

    self.navController = [[[UINavigationController alloc] initWithRootViewController:_browserViewController] autorelease];

    [_window setRootViewController:self.navController];

    //[_window addSubview:_navController.view];
    
	//Show the window
	[_window makeKeyAndVisible];
	
    // on ipad we've got copious amounts of empty space, so lets throw our logo in there..
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        float logoSize = 200;
        self.logoImage = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo.png"]] autorelease];
        _logoImage.autoresizingMask = (UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin
                                       | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin);
        _logoImage.frame = CGRectMake(_navController.view.bounds.size.width/2-logoSize/2,_navController.view.bounds.size.height*0.5-logoSize/2,logoSize,logoSize);
        [_navController.view addSubview:_logoImage];
    }

    // turn on accelerometer
    [[UIAccelerometer sharedAccelerometer] setDelegate:self];
    [[UIAccelerometer sharedAccelerometer] setUpdateInterval:ACCELEROMETER_UPDATE_RATE];


    // add any already-connected controllers
    for (GCController *controller:[GCController controllers]){
        [self addController:controller];
    }

    // ..and start listening for controller connects/disconnects
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gameControllerDidConnect:)
                                                 name:GCControllerDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(gameControllerDidDisconnect:)
                                                 name:GCControllerDidDisconnectNotification object:nil];

    
    //[self configureConnectedGameControllers];
    //    [GCController startWirelessControllerDiscoveryWithCompletionHandler:^{
    //        NSLog(@"Finished finding controllers");
    //    }];
    //printf("FOUND CONTROLLERS: %d\n",[[GCController controllers] count]);
}


- (void)gameControllerDidConnect:(NSNotification*)nIn {
    GCController *controller = [nIn object];
    [self addController: controller];
}

- (void)gameControllerDidDisconnect:(NSNotification*)nIn {
    GCController *controller = [nIn object];
    [self removeController:controller];
}

- (void) addController:(GCController*)controller
{
    [AppController debugPrint:@"Controller connected."];

    // if this controller has no player set, let's just assign it to 1.
    // (we dont really use this, but it looks prettier than ambiguous flashing or whatnot)
    if (controller.playerIndex == GCControllerPlayerIndexUnset){
        controller.playerIndex = 0;
    }

    // if they have the extended profile:
    // (note; we could reduce redundant code here by *always* setting common stuff in the regular profile, but it sounds
    // like theoretically a controller could lack the regular profile so lets just do everything in extended or everything in regular)
    if (controller.extendedGamepad != nil){
        controller.extendedGamepad.dpad.valueChangedHandler = ^(GCControllerDirectionPad *dpad, float xValue, float yValue) {
            //printf("DPAD: %f %f\n",xValue,yValue);
            [[RemoteViewController sharedRemoteViewController] hardwareDPadChangedX:xValue andY:yValue];
        };
        controller.extendedGamepad.buttonA.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("A: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleJumpPress];
            else [[RemoteViewController sharedRemoteViewController] handleJumpRelease];
        };
        controller.extendedGamepad.buttonB.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("B: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleBombPress];
            else [[RemoteViewController sharedRemoteViewController] handleBombRelease];
        };
        controller.extendedGamepad.buttonX.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("X: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handlePunchPress];
            else [[RemoteViewController sharedRemoteViewController] handlePunchRelease];
        };
        controller.extendedGamepad.buttonY.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("Y: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleThrowPress];
            else [[RemoteViewController sharedRemoteViewController] handleThrowRelease];
        };
        controller.extendedGamepad.leftShoulder.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("LSHOULDER: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleRun1Press];
            else [[RemoteViewController sharedRemoteViewController] handleRun1Release];
        };
        controller.extendedGamepad.rightShoulder.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("RSHOULDER: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleRun2Press];
            else [[RemoteViewController sharedRemoteViewController] handleRun2Release];
        };
        controller.extendedGamepad.leftTrigger.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("LTRIGGER: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleRun3Press];
            else [[RemoteViewController sharedRemoteViewController] handleRun3Release];
        };
        controller.extendedGamepad.rightTrigger.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("RTRIGGER: %f %d\n",value,pressed);

            if (pressed) [[RemoteViewController sharedRemoteViewController] handleRun4Press];
            else [[RemoteViewController sharedRemoteViewController] handleRun4Release];
        };
        controller.extendedGamepad.leftThumbstick.valueChangedHandler = ^(GCControllerDirectionPad *dpad, float xValue, float yValue) {
            //printf("LSTICK: %f %f\n",xValue,yValue);
            [[RemoteViewController sharedRemoteViewController] hardwareStickChangedX:xValue andY:yValue];
        };
    }
    // otherwise try the regular profile:
    else if (controller.gamepad != nil){
        controller.gamepad.dpad.valueChangedHandler = ^(GCControllerDirectionPad *dpad, float xValue, float yValue) {
            //printf("DPAD: %f %f\n",xValue,yValue);
            [[RemoteViewController sharedRemoteViewController] hardwareDPadChangedX:xValue andY:yValue];
        };
        controller.gamepad.buttonA.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("A: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleJumpPress];
            else [[RemoteViewController sharedRemoteViewController] handleJumpRelease];
        };
        controller.gamepad.buttonB.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("B: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleBombPress];
            else [[RemoteViewController sharedRemoteViewController] handleBombRelease];
        };
        controller.gamepad.buttonX.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("X: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handlePunchPress];
            else [[RemoteViewController sharedRemoteViewController] handlePunchRelease];
        };
        controller.gamepad.buttonY.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("Y: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleThrowPress];
            else [[RemoteViewController sharedRemoteViewController] handleThrowRelease];
        };
        controller.gamepad.leftShoulder.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("LSHOULDER: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleRun1Press];
            else [[RemoteViewController sharedRemoteViewController] handleRun1Release];
        };
        controller.gamepad.rightShoulder.valueChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            //printf("RSHOULDER: %f %d\n",value,pressed);
            if (pressed) [[RemoteViewController sharedRemoteViewController] handleRun2Press];
            else [[RemoteViewController sharedRemoteViewController] handleRun2Release];
        };
    }
    // all controllers should have this..
    controller.controllerPausedHandler = ^(GCController *controller ) {
        //printf("PAUSE!\n");
        [[RemoteViewController sharedRemoteViewController] handleMenu];
    };
}

- (void) removeController:(GCController*)controller
{
    //printf("CONTROLLER DISCONNECTED\n");
    [AppController debugPrint:@"Controller disconnected."];
}


- (void) dealloc
{	
    self.navController = nil;
    self.browserViewController = nil;
    self.window = nil;
    self.debugTextLabels = nil;
    self.hoverView = nil;
    self.setTiltNeutralButton = nil;
    self.joystickStyleLabel = nil;
    self.joystickStyleControl = nil;
    self.logoImage = nil;

    [[UIAccelerometer sharedAccelerometer] setDelegate:nil];

	[super dealloc];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    //printf("WILL RESIGN ACTIVE\n");
    [_browserViewController stop];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    //printf("DID BECOME ACTIVE\n");
    [_browserViewController start];
    
    [[RemoteViewController sharedRemoteViewController] doBecomeActive];

}

//static void readCallback(CFSocketRef cfSocket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
//{
//    
//    printf("GOT UDP DATA!\n");
//}

- (void) showPrefsWithDelegate:(id) delegate
{
    if (_hoverView){
        [self hidePrefs];
        return;
    };

    bool haveControllers = ([[GCController controllers] count] > 0);

    _prefsDelegate = delegate;
    
    // pull defaults...
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
//	NSString *userName = [defaults objectForKey:@"playerName"]==nil?nil:[defaults stringForKey:@"playerName"];
//    if (userName == nil){
//        // if there's no stored name, generate one from our device name
//        NSString *dName = [UIDevice currentDevice].name;
//        const char *name = [dName UTF8String];
//        char buffer[17];
//        strncpy(buffer,name,sizeof(buffer));
//        buffer[16] = 0;
//        // Lets's clip at apostrophes or spaces..
//        // that way "Bill Smith's iPhone" becomes 'Bill'
//        // and 'Consuelo's iPod' becomes 'Consuelo'
//        char *s = strchr(buffer,'\'');
//        if (s and s > buffer) *s = 0;
//        s = strchr(buffer,' ');
//        if (s and s > buffer) *s = 0;
//        userName = [[[NSString alloc] initWithUTF8String:buffer] autorelease];
//    }
    
    
    
    _browserViewController.navigationItem.rightBarButtonItem.title = @"done";
    

    CGRect frame;

    if (haveControllers){
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) frame = CGRectMake(0,0, 300, 290);
        else frame = CGRectMake(0,0,300,260);
    }
    else{
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) frame = CGRectMake(0,0, 300, 230);
        else frame = CGRectMake(0,0,300,200);
    }


    //printf("W %f w %f\n",_navController.view.frame.size.width,frame.size.width);
    frame.origin.x = (_navController.view.bounds.size.width-frame.size.width)/2.0;
    frame.origin.y = (_navController.view.bounds.size.height-frame.size.height)/2.0+10.0;

    self.hoverView = [[[HoverView alloc] initWithFrame:frame] autorelease];
	_hoverView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    _hoverView.opaque = NO;
    
    
    UILabel *l;
//    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0,20,300,20)];
//    l.textColor = [UIColor whiteColor];
//    l.textAlignment = UITextAlignmentCenter;
//    l.backgroundColor = [UIColor clearColor];
//    l.text = [NSString stringWithFormat:@"Player Name:"];
//    [_hoverView addSubview:l];
    
    
//    UITextField *tf = [[[UITextField alloc] initWithFrame:CGRectMake(50,50,200,30)] autorelease];
//    [_hoverView addSubview:tf];
//    tf.text = userName;
//    
//    tf.borderStyle = UITextBorderStyleBezel;
//    //tf.placeholder = @"<enter text>";
//    tf.backgroundColor = [UIColor whiteColor];
//    tf.returnKeyType = UIReturnKeyDone;
//    tf.clearButtonMode = UITextFieldViewModeWhileEditing;	// has a clear 'x' button to the right
//    tf.delegate = self;

    
    BOOL tiltMode = [defaults objectForKey:@"tiltMode"]==nil?NO:[defaults boolForKey:@"tiltMode"];
    BOOL joystickFloating = [defaults objectForKey:@"joystickFloating"]==nil?YES:[defaults boolForKey:@"joystickFloating"];
    float controllerDPadSensitivity = [defaults objectForKey:@"controllerDPadSensitivity"]==nil?DEFAULT_CONTROLLER_DPAD_SENSITIVITY:[defaults floatForKey:@"controllerDPadSensitivity"];

    {
        l = [[UILabel alloc] initWithFrame:CGRectMake(0,35,300,20)];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = UITextAlignmentCenter;
        l.backgroundColor = [UIColor clearColor];
        l.text = [NSString stringWithFormat:@"Movement Control:"];
        [_hoverView addSubview:l];
        
        NSArray *segmentTextContent = [NSArray arrayWithObjects: @"Joystick", @"Tilt", nil];
        UISegmentedControl *sf = [[UISegmentedControl alloc] initWithItems:segmentTextContent];
        sf.frame = CGRectMake(50,65,200,30);
        
        //    UISegmentedControlStylePlain,     // large plain
        //    UISegmentedControlStyleBordered,  // large bordered
        //    UISegmentedControlStyleBar,       // small button/nav bar style. tintable
        //    UISegmentedControlStyleBezeled,   // large bezeled style. tintable
        
        sf.segmentedControlStyle = UISegmentedControlStylePlain;
        [sf addTarget:self action:@selector(tiltModeChanged:) forControlEvents:UIControlEventValueChanged];
        
        sf.selectedSegmentIndex = tiltMode;
        
        [_hoverView addSubview:sf];
    }
    
    if (0){
        l = [[UILabel alloc] initWithFrame:CGRectMake(0,175,300,20)];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = UITextAlignmentCenter;
        l.backgroundColor = [UIColor clearColor];
        l.text = [NSString stringWithFormat:@"Axis Snapping:"];
        [_hoverView addSubview:l];
        
        UISwitch *s = [[[UISwitch alloc] initWithFrame:CGRectMake(100,205,100,30)] autorelease];
        [s addTarget:self action:@selector(axisSnappingChanged:) forControlEvents:UIControlEventValueChanged];
        s.on = [defaults objectForKey:@"axisSnapping"]==nil?NO:[defaults boolForKey:@"axisSnapping"];
        
        [_hoverView addSubview:s];
        
    }
    
    if (1){
        UIButton *b = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [b addTarget:self action:@selector(setTiltNeutral) forControlEvents:UIControlEventTouchUpInside];
        b.frame = CGRectMake(80,125,140,40);
        [b setTitle:@"Set Tilt Neutral" forState:UIControlStateNormal];
        //b.fgcolor = [UIColor clearColor];
        b.titleLabel.alpha = tiltMode?1.0:0.2;
        b.hidden = tiltMode?FALSE:TRUE;
        [_hoverView addSubview:b];
        self.setTiltNeutralButton = b;
    }
    
    
    {
        l = [[UILabel alloc] initWithFrame:CGRectMake(0,110,300,20)];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = UITextAlignmentCenter;
        l.backgroundColor = [UIColor clearColor];
        l.text = [NSString stringWithFormat:@"Joystick Style:"];
        [_hoverView addSubview:l];
        
        l.hidden = tiltMode?TRUE:FALSE;
        self.joystickStyleLabel = l;

        NSArray *segmentTextContent = [NSArray arrayWithObjects: @"Floating", @"Fixed", nil];
        UISegmentedControl *sf = [[UISegmentedControl alloc] initWithItems:segmentTextContent];
        sf.frame = CGRectMake(50,140,200,30);
        
        //    UISegmentedControlStylePlain,     // large plain
        //    UISegmentedControlStyleBordered,  // large bordered
        //    UISegmentedControlStyleBar,       // small button/nav bar style. tintable
        //    UISegmentedControlStyleBezeled,   // large bezeled style. tintable
        
        sf.segmentedControlStyle = UISegmentedControlStylePlain;
        
        sf.hidden = tiltMode?TRUE:FALSE;

        self.joystickStyleControl = sf;

        [sf addTarget:self action:@selector(joystickFloatingChanged:) forControlEvents:UIControlEventValueChanged];
        
        //sf.selectedSegmentIndex = tiltMode;
        sf.selectedSegmentIndex = !joystickFloating;
  
        [_hoverView addSubview:sf];

    }

    if (haveControllers){
        l = [[UILabel alloc] initWithFrame:CGRectMake(0,185,300,20)];
        l.textColor = [UIColor whiteColor];
        l.textAlignment = UITextAlignmentCenter;
        l.backgroundColor = [UIColor clearColor];
        l.text = [NSString stringWithFormat:@"Controller DPad Sensitivity:"];
        [_hoverView addSubview:l];

        _dPadSlider = [[UISlider alloc] initWithFrame:CGRectMake(50, 215, 200, 23)];
        [_hoverView addSubview:_dPadSlider];
        _dPadSlider.minimumValue = 0.0;
        _dPadSlider.maximumValue = 1.0;
        _dPadSlider.value = controllerDPadSensitivity;
        _dPadSlider.continuous = NO;
        [_dPadSlider addTarget:self action:@selector(sliderChanged:)
           forControlEvents:UIControlEventValueChanged];
    }
    
    
    // lets make a close button on ipad since its farther from the top of the screen
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b addTarget:self action:@selector(hidePrefs) forControlEvents:UIControlEventTouchUpInside];
        b.frame = CGRectMake(100,frame.size.height-40, 100, 30);
        [b setTitle:@"close" forState:UIControlStateNormal];
        b.titleLabel.alpha = 0.3;
        [_hoverView addSubview:b];
    }
    
    
    [_navController.view addSubview:_hoverView];
    [_hoverView transitionInTop];

    //printf("WOULD SHOW PREFS\n");
}

-(void)sliderChanged:(id)sender{
    //printf("SLIDERCHANGED %f\n",_dPadSlider.value);
    [[NSUserDefaults standardUserDefaults] setFloat:_dPadSlider.value forKey:@"controllerDPadSensitivity"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[RemoteViewController sharedRemoteViewController] controllerDPadSensitivityChanged:_dPadSlider.value];

    //NSLog(@"SliderValue %f",mySlider.value);
}

- (void) setTiltNeutral
{

    float tiltY,tiltZ;
    switch(self.navController.interfaceOrientation){
        case UIInterfaceOrientationPortrait:
            tiltY = _accelY;
            tiltZ = _accelZ;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            tiltY = -_accelY;
            tiltZ = _accelZ;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            tiltY = -_accelX;
            tiltZ = _accelZ;
            break;
        case UIInterfaceOrientationLandscapeRight:
            tiltY = _accelX;
            tiltZ = _accelZ;
            break;
        default:
            tiltY = tiltZ = 0.0;
            break;
    }
    
    [[NSUserDefaults standardUserDefaults] setFloat:tiltY forKey:@"tiltNeutralY"];
    [[NSUserDefaults standardUserDefaults] setFloat:tiltZ forKey:@"tiltNeutralZ"];
	[[NSUserDefaults standardUserDefaults] synchronize];

    [[RemoteViewController sharedRemoteViewController] tiltNeutralChangedToY:tiltY z:tiltZ];
}

- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration {
    // store the current accel in case they poke the 'set neutral' button
    
    _accelX = acceleration.x;
    _accelY = acceleration.y;
    _accelZ = acceleration.z;
    
    [[RemoteViewController sharedRemoteViewController] accelerometer:accelerometer didAccelerate:acceleration];
}

- (void)tiltModeChanged:(id)caller
{
    int val = ((UISegmentedControl*)caller).selectedSegmentIndex;
    [[NSUserDefaults standardUserDefaults] setBool:val forKey:@"tiltMode"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    self.setTiltNeutralButton.titleLabel.alpha = val?1.0:0.2;
    self.setTiltNeutralButton.hidden = val?FALSE:TRUE;
    self.joystickStyleLabel.hidden = val?TRUE:FALSE;
    self.joystickStyleControl.hidden = val?TRUE:FALSE;

    // inform our delegate that axis-snapping has changed
//    if ([_prefsDelegate respondsToSelector:@selector(axisSnappingChanged:)]) {
//        //printf("THEY RESPOND!\n");
//        [_prefsDelegate tiltModeChanged:[NSNumber numberWithInt:val]];
//    }
//    else{
//        //printf("THEY DONT RESPOND\n");
//    }
    
    [[RemoteViewController sharedRemoteViewController] tiltModeChanged:[NSNumber numberWithInt:val]];

}

- (void)joystickFloatingChanged:(id)caller
{
    int val = (not ((UISegmentedControl*)caller).selectedSegmentIndex);
    [[NSUserDefaults standardUserDefaults] setBool:val forKey:@"joystickFloating"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
//    self.setTiltNeutralButton.titleLabel.alpha = val?1.0:0.2;
//    self.setTiltNeutralButton.hidden = val?FALSE:TRUE;
//    self.joystickStyleLabel.hidden = val?TRUE:FALSE;
//    self.joystickStyleControl.hidden = val?TRUE:FALSE;
    [[RemoteViewController sharedRemoteViewController] joystickFloatingChanged:[NSNumber numberWithInt:val]];
    
}

- (void)axisSnappingChanged:(id)caller
{
    int val = ((UISwitch*)caller).on;
    [[NSUserDefaults standardUserDefaults] setBool:val forKey:@"axisSnapping"];

    // inform our delegate that axis-snapping has changed
    if ([_prefsDelegate respondsToSelector:@selector(axisSnappingChanged:)]) {
        //printf("THEY RESPOND!\n");
        [_prefsDelegate axisSnappingChanged:[NSNumber numberWithInt:val]];
    }
    else{
        //printf("THEY DONT RESPOND\n");
    }

}

- (BOOL)textFieldShouldReturn:(UITextField *)theTextField {
    //NSLog(@"GOT %@\n",theTextField.text);
    

	[theTextField resignFirstResponder];

    [[NSUserDefaults standardUserDefaults] setObject:theTextField.text forKey:@"playerName"];
	[[NSUserDefaults standardUserDefaults] synchronize];

    return YES;
}

- (void) hidePrefs
{
    _browserViewController.navigationItem.rightBarButtonItem.title = @"options";
    [_hoverView transitionOutTop];
    self.hoverView = nil;
    self.setTiltNeutralButton = nil;
}

- (void) browserViewController:(BrowserViewController*)bvc didSelectAddress:(struct sockaddr)addr withSize:(int)size
{
    //printf("WOULD DOOOOO\n");
    RemoteViewController *r = [[[RemoteViewController alloc] initWithAddress:addr andSize:size] autorelease];
    [_navController pushViewController:r animated:YES];

}
- (void) browserViewController:(BrowserViewController *)bvc didResolveInstance:(NSNetService *)netService
{
	if (!netService) return;

    // see if we've got an ipv4 address in there..
    bool haveV4 = NO;
    for (NSData *addr in [netService addresses]){
        struct sockaddr *sa = (struct sockaddr *)[addr bytes];
        if (sa->sa_family == AF_INET6){
            //printf("GOT INET 6");
        }
        else{
            //printf("GOT INET 4");
            haveV4 = YES;
            break;
        }
    }
//    if (not haveV4){
//        //printf("WARNING: NO IPV4 ADDRESSES!\n");
//        [AppController debugPrint:@"Network is not ready;"];
//        [AppController debugPrint:@"Please try again momentarily."];
//        [_browserViewController stop];
//        [_browserViewController start];
//        return;
//    }
    
    
    RemoteViewController *r = [[[RemoteViewController alloc] initWithNetService:netService] autorelease];
    [_navController pushViewController:r animated:YES];

//    
//    NSArray *addresses = [netService addresses];
//    BOOL success = NO;
//    
//    // lets try ipv6 first..
////    for(unsigned int i = 0; i < [addresses count]; i++){
////        char addr[256];
////        struct sockaddr *sa = (struct sockaddr *)[[addresses objectAtIndex:i] bytes];
//        //if(sa->sa_family == AF_INET6){
////            printf("GOT V6\n");
////            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
////            if(inet_ntop(AF_INET6, &sin6->sin6_addr, addr, sizeof(addr))){
////                NSLog(@"%s", addr);
////            }
////            
////            // create our datagram socket...
////            CFSocketContext socketCtxt = {0, self, NULL, NULL, NULL};	
////            CFSocketRef s = CFSocketCreate(kCFAllocatorDefault, PF_INET6, SOCK_DGRAM, IPPROTO_UDP, kCFSocketAcceptCallBack, (CFSocketCallBack)&readCallback, &socketCtxt);;
////            if (s != NULL){
////                
////                // bind it...
////                struct sockaddr_in6 addr6;
////                memset(&addr6, 0, sizeof(addr6));
////                addr6.sin6_len = sizeof(addr6);
////                addr6.sin6_family = AF_INET6;
////                addr6.sin6_port = 0;
////                addr6.sin6_flowinfo = 0;
////                addr6.sin6_addr = in6addr_any;
////                NSData *address6 = [NSData dataWithBytes:&addr6 length:sizeof(addr6)];
////                
////                if (kCFSocketSuccess != CFSocketSetAddress(s, (CFDataRef)address6)) {
////                    printf("ERROR ON CFSocketSetAddress for ipv6 socket\n");
////                    if (s) CFRelease(s);
////                    s = NULL;
////                }
////                if (s != NULL){
////                    // and connect..
////                    CFSocketError sockErr = CFSocketConnectToAddress(s, (CFDataRef)[addresses objectAtIndex:i], (CFTimeInterval)0.0);
////                    if(sockErr != kCFSocketSuccess){
////                        printf("POO; error on connect\n");
////                        if (s) CFRelease(s);
////                        s = NULL;
////                    }
////                    // we made it!!
////                    if (s){
////                        printf("MADE IPV6 SOCKET SUCCESSFULLY!\n");
////                        success = YES;
////                        
////                        UInt8 data[3] = {1,2,3};
////                        CFDataRef d = CFDataCreate(NULL,data,3);
////                        CFSocketError sockErr = CFSocketSendData(s,NULL,d,0);
////                        CFRelease(d);
////                        if (sockErr != kCFSocketSuccess){
////                            printf("ERROR ON SEND\n");
////                        }
////                        break;
////                    }
////                }
////            }
////            
////            //            int sd = socket(AF_INET6,SOCK_DGRAM,0);
//////            if (sd<0){
//////                printf("cannot open socket\n");
//////                continue;
//////            }
////            //printf("SUCCESS!\n");
////            
////        }
////    }
//    // fallback on ip4v..
////    if (!success){
//    {
//        for(unsigned int i = 0; i < [addresses count]; i++){
//            char addr[256];
//            struct sockaddr *sa = (struct sockaddr *)
//            [[addresses objectAtIndex:i] bytes];
//            if(sa->sa_family == AF_INET){
//                printf("GOT V4!\n");
//                struct sockaddr_in *sin = (struct sockaddr_in *)sa;
//                if(inet_ntop(AF_INET, &sin->sin_addr, addr, sizeof(addr))){
//                    NSLog(@"%s", addr);
//                }
//                
//                // create our datagram socket...
//                CFSocketContext socketCtxt = {0, self, NULL, NULL, NULL};	
//                CFSocketRef s = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP, kCFSocketReadCallBack, (CFSocketCallBack)&readCallback, &socketCtxt);;
//                if (s != NULL){
//                    
//                    // bind it...
//                    struct sockaddr_in addr4;
//                    memset(&addr4, 0, sizeof(addr4));
//                    addr4.sin_len = sizeof(addr4);
//                    addr4.sin_family = AF_INET;
//                    addr4.sin_port = 0;
//                    addr4.sin_addr.s_addr = htonl(INADDR_ANY);
//                    NSData *address4 = [NSData dataWithBytes:&addr4 length:sizeof(addr4)];
//                    
////                    // bind it...
////                    struct sockaddr_in6 addr6;
////                    memset(&addr6, 0, sizeof(addr6));
////                    addr6.sin6_len = sizeof(addr6);
////                    addr6.sin6_family = AF_INET6;
////                    addr6.sin6_port = 0;
////                    addr6.sin6_flowinfo = 0;
////                    addr6.sin6_addr = in6addr_any;
////                    NSData *address6 = [NSData dataWithBytes:&addr6 length:sizeof(addr6)];
//                    
//                    if (kCFSocketSuccess != CFSocketSetAddress(s, (CFDataRef)address4)) {
//                        printf("ERROR ON CFSocketSetAddress for ipv4 socket\n");
//                        if (s) CFRelease(s);
//                        s = NULL;
//                    }
//                    if (s != NULL){
//                        // and connect..
//                        CFSocketError sockErr = CFSocketConnectToAddress(s, (CFDataRef)[addresses objectAtIndex:i], (CFTimeInterval)0.0);
//                        if(sockErr != kCFSocketSuccess){
//                            printf("POO; error on connect\n");
//                            if (s) CFRelease(s);
//                            s = NULL;
//                        }
//                        // we made it!!
//                        if (s){
//                            printf("MADE IPV4 SOCKET SUCCESSFULLY!\n");
//                            success = YES;
//                            
//                            UInt8 data[3] = {1,2,3};
//                            CFDataRef d = CFDataCreate(NULL,data,3);
//                            CFSocketError sockErr = CFSocketSendData(s,NULL,d,0);
//                            CFRelease(d);
//                            if (sockErr != kCFSocketSuccess){
//                                printf("ERROR ON SEND\n");
//                            }
//                            break;
//                        }
//                    }
//                }
//                
//                
//            }
//        }
//    }
//    if (!success){
//        printf("No addresses found\n");
//        return;
//    }
////    for(unsigned int i = 0; i < [addresses count]; i++){
////        char addr[256];
////        struct sockaddr *sa = (struct sockaddr *)
////        [[addresses objectAtIndex:i] bytes];
////        if(sa->sa_family == AF_INET){
////            printf("GOT V4!\n");
////            struct sockaddr_in *sin = (struct sockaddr_in *)sa;
////            if(inet_ntop(AF_INET, &sin->sin_addr, addr, sizeof(addr))){
////                NSLog(@"%s", addr);
////            }
////        }
////        else if(sa->sa_family == AF_INET6){
////            printf("GOT V6\n");
////            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)sa;
////            if(inet_ntop(AF_INET6, &sin6->sin6_addr, addr, sizeof(addr))){
////                NSLog(@"%s", addr);
////            }
////        }
////    }
    
}

+ (void) debugPrint: (NSString*) s
{
    float padding = 20;
	CGRect f = gApp.navController.view.bounds;
	CGRect frame = CGRectMake(padding,f.size.height-(20+padding), f.size.width - 2*padding, 20);
    //CGRect frame = CGRectMake(padding,f.size.height-(20+padding), f.size.width - padding, 20);

	UILabel *l = [[[UILabel alloc] initWithFrame:frame] autorelease];
    l.textAlignment = UITextAlignmentCenter;

	l.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
	l.text = s;
    l.font = [UIFont boldSystemFontOfSize:12];

	l.textColor = [UIColor greenColor];
	l.backgroundColor = [UIColor clearColor];
	l.userInteractionEnabled = NO;
	[gApp.navController.view addSubview:l];


	// scoot existing ones up...
	for (UILabel *l in gApp.debugTextLabels){
        //printf("MOVING EXISTING UP\n");
		CGRect f = l.frame;
		f.origin.y -= 20;
		l.frame = f;
	}
    //printf("ADDING %x\n",l);
    [gApp.debugTextLabels addObject:l];
    //printf("FOOF %d\n",[gApp.debugTextLabels count]);

    l.alpha = 0.0;
    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ l.alpha = 1.0;}
                     completion:nil];
    
	// after a bit, fade this one out and remove it
	[AppController timerWithInterval:2.0 andBlock:^{
        [UIView animateWithDuration:1
                              delay:0
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ l.alpha = 0.0;}
                         completion:^(BOOL completed){
                             [l removeFromSuperview];
                             [gApp.debugTextLabels removeObject:l];
                         }];
        
		//[l removeFromSuperview];
		//[gApp.debugTextLabels removeObject:l];
        
	}];
}


@end

/* WizardViewController.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or   
 *  (at your option) any later version.                                 
 *                                                                      
 *  This program is distributed in the hope that it will be useful,     
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of      
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the       
 *  GNU Library General Public License for more details.                
 *                                                                      
 *  You should have received a copy of the GNU General Public License   
 *  along with this program; if not, write to the Free Software         
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */ 

#import "WizardViewController.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"

#import <XMLRPCConnection.h>
#import <XMLRPCConnectionManager.h>
#import <XMLRPCResponse.h>
#import <XMLRPCRequest.h>

typedef enum _ViewElement {
    ViewElement_Username = 100,
    ViewElement_Password = 101,
    ViewElement_Password2 = 102,
    ViewElement_Email = 103,
    ViewElement_Domain = 104,
    ViewElement_Label = 200,
    ViewElement_Error = 201
} ViewElement;

@implementation WizardViewController

@synthesize contentView;

@synthesize welcomeView;
@synthesize choiceView;
@synthesize createAccountView;
@synthesize connectAccountView;
@synthesize externalAccountView;
@synthesize validateAccountView;

@synthesize waitView;

@synthesize backButton;
@synthesize startButton;

static int LINPHONE_WIZARD_MIN_PASSWORD_LENGTH = 6;
static int LINPHONE_WIZARD_MIN_USERNAME_LENGTH = 4;
static NSString *LINPHONE_WIZARD_URL = @"https://www.linphone.org/wizard.php";
static NSString *LINPHONE_WIZARD_DOMAIN = @"sip.linphone.org";


#pragma mark - Lifecycle Functions

- (id)init {
    self = [super initWithNibName:@"WizardViewController" bundle:[NSBundle mainBundle]];
    if (self != nil) {
        self->historyViews = [[NSMutableArray alloc] init];
        self->currentView = nil;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [contentView release];
    
    [welcomeView release];
    [choiceView release];
    [createAccountView release];
    [connectAccountView release];
    [externalAccountView release];
    [validateAccountView release];
    
    [waitView release];
    
    [backButton release];
    [startButton release];
    
    [historyViews release];
    
    [super dealloc];
}


#pragma mark - UICompositeViewDelegate Functions

static UICompositeViewDescription *compositeDescription = nil;

+ (UICompositeViewDescription *)compositeViewDescription {
    if(compositeDescription == nil) {
        compositeDescription = [[UICompositeViewDescription alloc] init:@"Wizard" 
                                                                content:@"WizardViewController" 
                                                               stateBar:nil 
                                                        stateBarEnabled:false 
                                                                 tabBar:nil 
                                                          tabBarEnabled:false 
                                                             fullscreen:false
                                                          landscapeMode:[LinphoneManager runningOnIpad]
                                                           portraitMode:true];
    }
    return compositeDescription;
}


#pragma mark - ViewController Functions

- (void)viewDidLoad {
    [super viewDidLoad];
    [self resetWizard];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationUpdateEvent:)
                                                 name:kLinphoneRegistrationUpdate
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                 name:kLinphoneRegistrationUpdate
                                               object:nil];
    
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}


#pragma mark -

+ (void)cleanTextField:(UIView*)view {
    if([view isKindOfClass:[UITextField class]]) {
        [(UITextField*)view setText:@""];
    } else {
        for(UIView *subview in view.subviews) {
            [WizardViewController cleanTextField:subview];
        }
    }
}

- (void)resetWizard {
    [self clearProxyConfig];
    [WizardViewController cleanTextField:welcomeView];
    [WizardViewController cleanTextField:choiceView];
    [WizardViewController cleanTextField:createAccountView];
    [WizardViewController cleanTextField:connectAccountView];
    [WizardViewController cleanTextField:externalAccountView];
    [WizardViewController cleanTextField:validateAccountView];
    [self changeView:welcomeView back:FALSE animation:FALSE];
    [waitView setHidden:TRUE];
}

+ (UIView*)findView:(ViewElement)tag view:(UIView*)view {
    for(UIView *child in [view subviews]) {
        if([child tag] == tag){
            return (UITextField*)child;
        } else {
            UIView *o = [WizardViewController findView:tag view:child];
            if(o)
                return o;
        }
    }
    return nil;
}

+ (UITextField*)findTextField:(ViewElement)tag view:(UIView*)view {
    UIView *aview = [WizardViewController findView:tag view:view];
    if([aview isKindOfClass:[UITextField class]])
        return (UITextField*)aview;
    return nil;
}

+ (UILabel*)findLabel:(ViewElement)tag view:(UIView*)view {
    UIView *aview = [WizardViewController findView:tag view:view];
    if([aview isKindOfClass:[UILabel class]])
        return (UILabel*)aview;
    return nil;
}

- (void)clearHistory {
    [historyViews removeAllObjects];
}

- (void)changeView:(UIView *)view back:(BOOL)back animation:(BOOL)animation {
    // Change toolbar buttons following view
    if (view == welcomeView) {
        [startButton setHidden:false];
        [backButton setHidden:true];
    } else {
        [startButton setHidden:true];
        [backButton setHidden:false];
    }
    
    if (view == validateAccountView) {
        [backButton setEnabled:FALSE];
    } else {
        [backButton setEnabled:TRUE];
    }
    
    // Animation
    if(animation && [[LinphoneManager instance] lpConfigBoolForKey:@"animations_preference"] == true) {
      CATransition* trans = [CATransition animation];
      [trans setType:kCATransitionPush];
      [trans setDuration:0.35];
      [trans setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
      if(back) {
          [trans setSubtype:kCATransitionFromLeft];
      }else {
          [trans setSubtype:kCATransitionFromRight];
      }
      [contentView.layer addAnimation:trans forKey:@"Transition"];
    }
    
    // Stack current view
    if(currentView != nil) {
        if(!back)
            [historyViews addObject:currentView];
        [currentView removeFromSuperview];
    }
    
    // Set current view
    currentView = view;
    [contentView insertSubview:view atIndex:0];
    [view setFrame:[contentView bounds]];
    [contentView setContentSize:[view bounds].size];
}

- (void)clearProxyConfig {
	linphone_core_clear_proxy_config([LinphoneManager getLc]);
	linphone_core_clear_all_auth_info([LinphoneManager getLc]);
}

- (void)addProxyConfig:(NSString*)username password:(NSString*)password domain:(NSString*)domain {
	const char* identity = [[NSString stringWithFormat:@"sip:%@@%@",username,domain] UTF8String];
	LinphoneProxyConfig* proxyCfg = linphone_core_create_proxy_config([LinphoneManager getLc]);
	LinphoneAuthInfo* info=linphone_auth_info_new([username UTF8String],NULL,[password UTF8String],NULL,NULL);
	linphone_proxy_config_set_identity(proxyCfg,identity);
	linphone_proxy_config_set_server_addr(proxyCfg,[domain UTF8String]);
	linphone_proxy_config_enable_register(proxyCfg,true);
	linphone_core_add_proxy_config([LinphoneManager getLc], proxyCfg);
	linphone_core_set_default_proxy([LinphoneManager getLc], proxyCfg);
	linphone_core_add_auth_info([LinphoneManager getLc],info)
	;
}

- (void)checkUserExist:(NSString*)username {
    [LinphoneLogger log:LinphoneLoggerDebug format:@"XMLRPC check_account %@", username];
    
    NSURL *URL = [NSURL URLWithString: LINPHONE_WIZARD_URL];
    XMLRPCRequest *request = [[XMLRPCRequest alloc] initWithURL: URL];
    [request setMethod: @"check_account" withParameters:[NSArray arrayWithObjects:username, nil]];
    
    XMLRPCConnectionManager *manager = [XMLRPCConnectionManager sharedManager];
    [manager spawnConnectionWithXMLRPCRequest: request delegate: self];
    
    [request release];
    [waitView setHidden:false];
}

- (void)createAccount:(NSString*)identity password:(NSString*)password email:(NSString*)email {
    NSString *useragent = [LinphoneManager getUserAgent];
    [LinphoneLogger log:LinphoneLoggerDebug format:@"XMLRPC create_account_with_useragent %@ %@ %@ %@", identity, password, email, useragent];
    
    NSURL *URL = [NSURL URLWithString: LINPHONE_WIZARD_URL];
    XMLRPCRequest *request = [[XMLRPCRequest alloc] initWithURL: URL];
    [request setMethod: @"create_account_with_useragent" withParameters:[NSArray arrayWithObjects:identity, password, email, useragent, nil]];
    
    XMLRPCConnectionManager *manager = [XMLRPCConnectionManager sharedManager];
    [manager spawnConnectionWithXMLRPCRequest: request delegate: self];
    
    [request release];
    [waitView setHidden:false];
}

- (void)checkAccountValidation:(NSString*)identity {
    [LinphoneLogger log:LinphoneLoggerDebug format:@"XMLRPC check_account_validated %@", identity];
    
    NSURL *URL = [NSURL URLWithString: LINPHONE_WIZARD_URL];
    XMLRPCRequest *request = [[XMLRPCRequest alloc] initWithURL: URL];
    [request setMethod: @"check_account_validated" withParameters:[NSArray arrayWithObjects:identity, nil]];
    
    XMLRPCConnectionManager *manager = [XMLRPCConnectionManager sharedManager];
    [manager spawnConnectionWithXMLRPCRequest: request delegate: self];
    
    [request release];
    [waitView setHidden:false];
}

- (void)registrationUpdate:(LinphoneRegistrationState)state {
    switch (state) {
        case LinphoneRegistrationOk: {
            [waitView setHidden:true];
            [[PhoneMainView instance] changeCurrentView:[DialerViewController compositeViewDescription]];
            break;
        }
        case LinphoneRegistrationNone:
        case LinphoneRegistrationCleared:  {
            [waitView setHidden:true];
            break;
        }
        case LinphoneRegistrationFailed: {
            [waitView setHidden:true];
            break;
        }
        case LinphoneRegistrationProgress: {
            [waitView setHidden:false];
            break;
        }
        default:
            break;
    }
}


#pragma mark - UITextFieldDelegate Functions

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    activeTextField = textField;
}


#pragma mark - Action Functions

- (IBAction)onStartClick:(id)sender {
    [self changeView:choiceView back:FALSE animation:TRUE];
}

- (IBAction)onBackClick:(id)sender {
    if ([historyViews count] > 0) {
        UIView * view = [historyViews lastObject];
        [historyViews removeLastObject];
        [self changeView:view back:TRUE animation:TRUE];
    }
}

- (IBAction)onCancelClick:(id)sender {
    [[PhoneMainView instance] changeCurrentView:[DialerViewController compositeViewDescription]];
}

- (IBAction)onCreateAccountClick:(id)sender {
    [self changeView:createAccountView back:FALSE animation:TRUE];
}

- (IBAction)onConnectAccountClick:(id)sender {
    [self changeView:connectAccountView back:FALSE animation:TRUE];
}

- (IBAction)onExternalAccountClick:(id)sender {
    [self changeView:externalAccountView back:FALSE animation:TRUE];
}

- (IBAction)onCheckValidationClick:(id)sender {
    NSString *username = [WizardViewController findTextField:ViewElement_Username view:contentView].text;
    [self checkAccountValidation:[NSString stringWithFormat:@"%@@%@", username, LINPHONE_WIZARD_DOMAIN]];
}

- (IBAction)onSignInExternalClick:(id)sender {
    [self.waitView setHidden:false];
    NSString *username = [WizardViewController findTextField:ViewElement_Username  view:contentView].text;
    NSString *password = [WizardViewController findTextField:ViewElement_Password  view:contentView].text;
    NSString *domain = [WizardViewController findTextField:ViewElement_Domain  view:contentView].text;
    [self addProxyConfig:username password:password domain:domain];
}

- (IBAction)onSignInClick:(id)sender {
    [self.waitView setHidden:false];
    NSString *username = [WizardViewController findTextField:ViewElement_Username  view:contentView].text;
    NSString *password = [WizardViewController findTextField:ViewElement_Password  view:contentView].text;
    [self addProxyConfig:username password:password domain:LINPHONE_WIZARD_DOMAIN];
}

- (IBAction)onRegisterClick:(id)sender {
    NSString *username = [WizardViewController findTextField:ViewElement_Username  view:contentView].text;
    NSString *password = [WizardViewController findTextField:ViewElement_Password  view:contentView].text;
    NSString *password2 = [WizardViewController findTextField:ViewElement_Password2  view:contentView].text;
    NSString *email = [WizardViewController findTextField:ViewElement_Email view:contentView].text;
    NSMutableString *errors = [NSMutableString string];
    
    if ([username length] < LINPHONE_WIZARD_MIN_USERNAME_LENGTH) {
        
        [errors appendString:[NSString stringWithFormat:NSLocalizedString(@"The username is too short (minimum %d characters).\n", nil), LINPHONE_WIZARD_MIN_USERNAME_LENGTH]];
    }
    
    if ([password length] < LINPHONE_WIZARD_MIN_PASSWORD_LENGTH) {
        [errors appendString:[NSString stringWithFormat:NSLocalizedString(@"The password is too short (minimum %d characters).\n", nil), LINPHONE_WIZARD_MIN_PASSWORD_LENGTH]];
    }
    
    if (![password2 isEqualToString:password]) {
        [errors appendString:NSLocalizedString(@"The passwords are different.\n", nil)];
    }
    
    NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @".+@.+\\.[A-Za-z]{2}[A-Za-z]*"];
    if(![emailTest evaluateWithObject:email]) {
        [errors appendString:NSLocalizedString(@"The email is invalid.\n", nil)];
    }
    
    if([errors length]) {
        UIAlertView* errorView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Check error",nil)
                                                        message:[errors substringWithRange:NSMakeRange(0, [errors length] - 1)]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Continue",nil)
                                              otherButtonTitles:nil,nil];
        [errorView show];
        [errorView release];
    } else {
        [self checkUserExist:username];
    }
}


#pragma mark - Event Functions

- (void)registrationUpdateEvent:(NSNotification*)notif {
    [self registrationUpdate:[[notif.userInfo objectForKey: @"state"] intValue]];
}

#pragma mark - Keyboard Event Functions

- (void)keyboardWillHide:(NSNotification *)notif {
    //CGRect beginFrame = [[[notif userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    //CGRect endFrame = [[[notif userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIViewAnimationCurve curve = [[[notif userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    NSTimeInterval duration = [[[notif userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView beginAnimations:@"resize" context:nil];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    [UIView setAnimationBeginsFromCurrentState:TRUE];
    
    // Move view
    UIEdgeInsets inset = {0,0,0,0};
    [contentView setContentInset:inset];
    [contentView setScrollIndicatorInsets:inset];
    [contentView setShowsVerticalScrollIndicator:FALSE];
    
    [UIView commitAnimations];
}

- (void)keyboardWillShow:(NSNotification *)notif {
    //CGRect beginFrame = [[[notif userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    CGRect endFrame = [[[notif userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIViewAnimationCurve curve = [[[notif userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    NSTimeInterval duration = [[[notif userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView beginAnimations:@"resize" context:nil];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    [UIView setAnimationBeginsFromCurrentState:TRUE];
    
    if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
        int width = endFrame.size.height;
        endFrame.size.height = endFrame.size.width;
        endFrame.size.width = width;
    }
    
    // Change inset
    {
        UIEdgeInsets inset = {0,0,0,0};
        CGRect frame = [contentView frame];
        CGRect rect = [PhoneMainView instance].view.bounds;
        CGPoint pos = {frame.size.width, frame.size.height};
        CGPoint gPos = [contentView convertPoint:pos toView:[UIApplication sharedApplication].keyWindow.rootViewController.view]; // Bypass IOS bug on landscape mode
        inset.bottom = -(rect.size.height - gPos.y - endFrame.size.height);
        if(inset.bottom < 0) inset.bottom = 0;
        
        [contentView setContentInset:inset];
        [contentView setScrollIndicatorInsets:inset];
        CGRect fieldFrame = activeTextField.frame;
        fieldFrame.origin.y += fieldFrame.size.height;
        [contentView scrollRectToVisible:fieldFrame animated:TRUE];
        [contentView setShowsVerticalScrollIndicator:TRUE];
    }
    [UIView commitAnimations];
}


#pragma mark - XMLRPCConnectionDelegate Functions

- (void)request:(XMLRPCRequest *)request didReceiveResponse:(XMLRPCResponse *)response {
    [LinphoneLogger log:LinphoneLoggerDebug format:@"XMLRPC %@: %@", [request method], [response body]];
    [waitView setHidden:true];
    if ([response isFault]) {
        NSString *errorString = [NSString stringWithFormat:NSLocalizedString(@"Communication issue (%@)", nil), [response faultString]];
        UIAlertView* errorView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Communication issue",nil)
                                                            message:errorString
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Continue",nil)
                                                  otherButtonTitles:nil,nil];
        [errorView show];
        [errorView release];
    } else if([response object] != nil) { //Don't handle if not object: HTTP/Communication Error
        if([[request method] isEqualToString:@"check_account"]) {
            if([response object] == [NSNumber numberWithInt:1]) {
                UIAlertView* errorView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Check issue",nil)
                                                                message:NSLocalizedString(@"Username already exists", nil)
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"Continue",nil)
                                                      otherButtonTitles:nil,nil];
                [errorView show];
                [errorView release];
            } else {
                NSString *username = [WizardViewController findTextField:ViewElement_Username view:contentView].text;
                NSString *password = [WizardViewController findTextField:ViewElement_Password view:contentView].text;
                NSString *email = [WizardViewController findTextField:ViewElement_Email view:contentView].text;
                [self createAccount:[NSString stringWithFormat:@"%@@%@", username, LINPHONE_WIZARD_DOMAIN] password:password email:email];
            }
        } else if([[request method] isEqualToString:@"create_account_with_useragent"]) {
            if([response object] == [NSNumber numberWithInt:0]) {
                NSString *username = [WizardViewController findTextField:ViewElement_Username view:contentView].text;
                NSString *password = [WizardViewController findTextField:ViewElement_Password view:contentView].text;
                [self changeView:validateAccountView back:FALSE animation:TRUE];
                [WizardViewController findTextField:ViewElement_Username view:contentView].text = username;
                [WizardViewController findTextField:ViewElement_Password view:contentView].text = password;
            } else {
                UIAlertView* errorView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Account creation issue",nil)
                                                                    message:NSLocalizedString(@"Can't create the account. Please try again.", nil)
                                                                   delegate:nil
                                                          cancelButtonTitle:NSLocalizedString(@"Continue",nil)
                                                          otherButtonTitles:nil,nil];
                [errorView show];
                [errorView release];
            }
        } else if([[request method] isEqualToString:@"check_account_validated"]) {
             if([response object] == [NSNumber numberWithInt:1]) {
                 NSString *username = [WizardViewController findTextField:ViewElement_Username view:contentView].text;
                 NSString *password = [WizardViewController findTextField:ViewElement_Password view:contentView].text;
                [self addProxyConfig:username password:password domain:LINPHONE_WIZARD_DOMAIN];
             } else {
                 UIAlertView* errorView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Account validation issue",nil)
                                                                     message:NSLocalizedString(@"Your account is not validate yet.", nil)
                                                                    delegate:nil
                                                           cancelButtonTitle:NSLocalizedString(@"Continue",nil)
                                                           otherButtonTitles:nil,nil];
                 [errorView show];
                 [errorView release];
             }
        }
    }
}

- (void)request:(XMLRPCRequest *)request didFailWithError:(NSError *)error {
    NSString *errorString = [NSString stringWithFormat:NSLocalizedString(@"Communication issue (%@)", nil), [error localizedDescription]];
    UIAlertView* errorView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Communication issue", nil)
                                                    message:errorString
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"Continue", nil)
                                          otherButtonTitles:nil,nil];
    [errorView show];
    [errorView release];
    [waitView setHidden:true];
}

- (BOOL)request:(XMLRPCRequest *)request canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return FALSE;
}

- (void)request:(XMLRPCRequest *)request didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    
}

- (void)request:(XMLRPCRequest *)request didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    
}

@end
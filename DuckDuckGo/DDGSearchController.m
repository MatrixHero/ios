//
//  DDGSearchController.m
//  DuckDuckGo2
//
//  Created by Chris Heimark on 12/9/11.
//  Copyright (c) 2011 DuckDuckGo, Inc. All rights reserved.
//

#import "DDGSearchController.h"
#import "DDGSearchSuggestionsProvider.h"
#import "AFNetworking.h"
#import "DDGBangsProvider.h"
#import "DDGInputAccessoryView.h"
#import "DDGBookmarksViewController.h"
#import "DDGAutocompleteViewController.h"
#import "ECSlidingViewController.h"
#import "DDGSettingsViewController.h"
#import "DDGHistoryProvider.h"
#import "DDGWebViewController.h"

#import "NSMutableString+DDGDumpView.h"

@interface DDGSearchController ()
@property (nonatomic, weak, readwrite) id<DDGSearchHandler> searchHandler;
@property (nonatomic, strong) DDGHistoryProvider *historyProvider;
@property (nonatomic, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, strong) NSMutableArray *controllers;
@property (nonatomic, weak) UIPanGestureRecognizer *panGesture;
@end

@implementation DDGSearchController

-(id)initWithSearchHandler:(id <DDGSearchHandler>)searchHandler managedObjectContext:(NSManagedObjectContext *)managedObjectContext; {
	self = [super initWithNibName:@"DDGSearchController" bundle:nil];
    
	if (self) {
        self.searchHandler = searchHandler;
        self.managedObjectContext = managedObjectContext;
        self.controllers = [NSMutableArray arrayWithCapacity:2];
	}
	return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	[self.view removeFromSuperview];
}

- (CGRect)contentRect {
    [self view];
    
    CGRect searchbarRect = self.searchBar.frame;
    CGRect frame = self.view.bounds;
    CGRect intersection = CGRectIntersection(frame, searchbarRect);
    frame.origin.y = intersection.origin.y + intersection.size.height;
    frame.size.height = frame.size.height - frame.origin.y;
    
    return frame;
}

- (void)pushContentViewController:(UIViewController *)contentController animated:(BOOL)animated {
    NSTimeInterval duration = (animated) ? 0.3 : 0.0;
    
    UIViewController *incommingViewController = contentController;
    UIViewController *outgoingViewController = [self.controllers lastObject];
    
    CGRect contentRect = [self contentRect];
    CGRect incommingRect = contentRect;
    incommingRect.origin.x += contentRect.size.width;
    CGRect outgoingRect = contentRect;
    outgoingRect.origin.x -= contentRect.size.width;

    incommingViewController.view.frame = incommingRect;

    [incommingViewController willMoveToParentViewController:self];
    [self.view insertSubview:incommingViewController.view belowSubview:self.background];
    [self addChildViewController:incommingViewController];
    [outgoingViewController viewWillDisappear:animated];
    [incommingViewController viewWillAppear:animated];
    
    [self.controllers addObject:incommingViewController];
    [self setState:([self canPopContentViewController]) ? DDGSearchControllerStateWeb : DDGSearchControllerStateHome];
    
    [UIView animateWithDuration:duration
                     animations:^{
                         incommingViewController.view.frame = contentRect;
                         outgoingViewController.view.frame = outgoingRect;
                     }
                     completion:^(BOOL finished) {
                         [outgoingViewController viewDidDisappear:animated];
                         [incommingViewController viewDidAppear:animated];
                     }];
}

- (BOOL)canPopContentViewController {
    return ([self.controllers count] > 1);
}

- (void)popContentViewControllerAnimated:(BOOL)animated {
    if ([self canPopContentViewController]) {
        NSTimeInterval duration = (animated) ? 0.3 : 0.0;
        UIViewController *outgoingViewController = [self.controllers lastObject];
        UIViewController *incommingViewController = [self.controllers objectAtIndex:self.controllers.count-2];
        
        CGRect contentRect = [self contentRect];
        CGRect outgoingRect = contentRect;
        outgoingRect.origin.x += contentRect.size.width;
        
        [outgoingViewController viewWillDisappear:animated];
        [incommingViewController viewWillAppear:animated];
        
        [self.controllers removeLastObject];
        [self setState:([self canPopContentViewController]) ? DDGSearchControllerStateWeb : DDGSearchControllerStateHome];
        
        [UIView animateWithDuration:duration
                         animations:^{
                             incommingViewController.view.frame = contentRect;
                             outgoingViewController.view.frame = outgoingRect;
                         }
                         completion:^(BOOL finished) {
                             [outgoingViewController viewDidDisappear:animated];
                             [incommingViewController viewDidAppear:animated];
                             [outgoingViewController willMoveToParentViewController:nil];
                             [outgoingViewController.view removeFromSuperview];
                             [outgoingViewController removeFromParentViewController];
                         }];
    }
}

- (NSArray *)contentControllers {
    return [self.controllers copy];
}

- (DDGHistoryProvider *)historyProvider {
    if (nil == _historyProvider) {
        _historyProvider = [[DDGHistoryProvider alloc] initWithManagedObjectContext:self.managedObjectContext];
    }
    
    return _historyProvider;
}


#pragma mark - View lifecycle

- (void)viewWillLayoutSubviews
{
	if (self.view.frame.origin.y < 0.0)
	{
//		// uncoment these lines to get/see a nicely formatted view hiearchy dump
//		NSMutableString *s = [NSMutableString string];
//		[s dumpView:self.view atIndent:0];
//		NSLog (@"DDGSearchController:viewWILLLayoutSubviews \n%@", s);

		// repair damage occuring deep in the bowels of this view hiearchy
		CGRect r = self.view.frame;
		r.origin.y = 0.0;
		self.view.frame = r;
	}
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    backButtonVisible = YES;
    
    DDGAutocompleteViewController *autocompleteVC = [[DDGAutocompleteViewController alloc] initWithStyle:UITableViewStylePlain];
    self.autocompleteNavigationController = [[UINavigationController alloc] initWithRootViewController:autocompleteVC];
    _autocompleteNavigationController.delegate = self;
    [self addChildViewController:_autocompleteNavigationController];
    [_background addSubview:_autocompleteNavigationController.view];
    _autocompleteNavigationController.view.frame = _background.bounds;
    [_autocompleteNavigationController didMoveToParentViewController:self];
    // [_autocompleteNavigationController pushViewController:autocompleteVC animated:NO];
    
    [self revealBackground:NO animated:NO];
    
    _searchField.placeholder = NSLocalizedString(@"SearchPlaceholder", nil);
    [_searchField addTarget:self action:@selector(searchFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    
    stopOrReloadButton = [[UIButton alloc] init];
    stopOrReloadButton.frame = CGRectMake(0, 0, 31, 31);
    [stopOrReloadButton addTarget:self action:@selector(stopOrReloadButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    _searchField.rightView = stopOrReloadButton;
    
    unusedBangButtons = [[NSMutableArray alloc] initWithCapacity:50];    
    
    [self createInputAccessory];
    
	_searchField.rightViewMode = UITextFieldViewModeAlways;
	_searchField.leftViewMode = UITextFieldViewModeAlways;
	_searchField.leftView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"spacer8x16.png"]];
	
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGesture:)];
    panGesture.delegate = self;
    [self.view addGestureRecognizer:panGesture];
    self.panGesture = panGesture;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void)viewDidUnload {
    [self setActionButton:nil];
    [self setAutocompleteNavigationController:nil];
    [self setCancelButton:nil];
    [super viewDidUnload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    NSAssert(self.state != DDGSearchControllerStateUnknown, nil);
    
    [self.slidingViewController.panGesture requireGestureRecognizerToFail:self.panGesture];
}

#pragma mark - UIGestureRecognizerDelegate

- (void)panGesture:(UIPanGestureRecognizer *)panGesture {
    
    switch (panGesture.state) {
        case UIGestureRecognizerStateChanged:
        {
            CGPoint transation = [panGesture translationInView:self.view];
            [panGesture setTranslation:CGPointZero inView:self.view];
            
            UIViewController *currentViewController = [self.controllers lastObject];
            UIViewController *previousViewController = nil;
            if ([self canPopContentViewController])
                previousViewController = [self.controllers objectAtIndex:[self.controllers count]-2];
            
            CGPoint currentCenter = currentViewController.view.center;
            CGPoint previousCenter = previousViewController.view.center;
            
            currentCenter.x += transation.x;
            previousCenter.x += transation.x;
            
            [UIView animateWithDuration:0 animations:^{
                currentViewController.view.center = currentCenter;
                previousViewController.view.center = previousCenter;
            }];            
        }
            break;
        case UIGestureRecognizerStateBegan:
        {
            UIViewController *previousViewController = nil;
            if ([self canPopContentViewController])
                previousViewController = [self.controllers objectAtIndex:[self.controllers count]-2];
            [previousViewController viewWillAppear:YES];
            [previousViewController viewDidAppear:YES];
        }
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        {
            CGRect contentRect = [self contentRect];
            CGFloat contentMidX = CGRectGetMidX(contentRect);
            UIViewController *currentViewController = [self.controllers lastObject];
            
            CGFloat offset = currentViewController.view.center.x - contentMidX;
            CGPoint velocity = [panGesture velocityInView:panGesture.view];
            CGFloat percent = (offset) / (self.view.bounds.size.width / 2.0);
            
            BOOL pop = (velocity.x > 0 && percent > 0.25);
            
            UIViewController *previousViewController = nil;
            if ([self canPopContentViewController])
                previousViewController = [self.controllers objectAtIndex:[self.controllers count]-2];
            
            CGFloat distanceRemaining = contentRect.size.width - offset;
            CGFloat duration = MIN(distanceRemaining / abs(velocity.x), 0.4);            
            
            if (pop) {
                CGRect outgoingRect = contentRect;
                outgoingRect.origin.x += contentRect.size.width;
                
                [self.controllers removeLastObject];
                [self setState:([self canPopContentViewController]) ? DDGSearchControllerStateWeb : DDGSearchControllerStateHome];                
                
                [UIView animateWithDuration:duration animations:^{
                    currentViewController.view.frame = outgoingRect;
                    previousViewController.view.frame = contentRect;
                    [currentViewController viewWillDisappear:YES];
                } completion:^(BOOL finished) {
                    [currentViewController viewDidDisappear:YES];
                    [currentViewController willMoveToParentViewController:nil];
                    [currentViewController.view removeFromSuperview];
                    [currentViewController removeFromParentViewController];                    
                }];
                
            } else {
                CGRect previousRect = contentRect;
                previousRect.origin.x -= contentRect.size.width;
                
                [UIView animateWithDuration:duration animations:^{
                    currentViewController.view.frame = contentRect;
                    previousViewController.view.frame = previousRect;
                    [previousViewController viewWillDisappear:YES];
                } completion:^(BOOL finished) {
                    [previousViewController viewDidDisappear:YES];
                }];                
            }
        }
            break;
        default:
            break;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return [self canPopContentViewController];
}

#pragma mark - Keyboard notifications

- (void)slidingViewTopDidAnchorRight:(NSNotification *)notification {
    [self.searchField resignFirstResponder];
}

-(void)keyboardWillShow:(NSNotification *)notification {
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(slidingViewTopDidAnchorRight:) name:ECSlidingViewTopDidAnchorRight object:self.slidingViewController];
    [self keyboardWillShow:YES notification:notification];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ECSlidingViewTopDidAnchorRight object:self.slidingViewController];
    [self keyboardWillShow:NO notification:notification];
}

-(void)keyboardWillShow:(BOOL)show notification:(NSNotification*)notification {
    NSDictionary *info = [notification userInfo];
    CGRect keyboardBegin = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
    keyboardBegin = [self.view.superview convertRect:keyboardBegin fromView:nil];
    CGRect keyboardEnd = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardEnd = [self.view.superview convertRect:keyboardEnd fromView:nil];
    double dy = keyboardEnd.origin.y - keyboardBegin.origin.y;
    if(ABS(dy) < 1) {
        
        // this isn't a standard up/down animation so don't try animating
        
        [self revealInputAccessory:show animationDuration:0.0];
        
        double delayInSeconds = (show ? [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue] : 0.0);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            CGRect f = self.view.frame;
            
            if(show)
                f.size.height = self.view.superview.bounds.size.height - f.origin.y - keyboardEnd.size.height;
            else
                f.size.height = self.view.superview.bounds.size.height - f.origin.y;
            
            self.view.frame = f;
        });
                
    } else {
        double animationDuration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        
        [self revealInputAccessory:show animationDuration:animationDuration];
        
        UIViewAnimationCurve curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
        UIViewAnimationOptions options = 0;
        switch (curve) {
            case UIViewAnimationCurveEaseIn:
                options = UIViewAnimationOptionCurveEaseIn;
                break;
            case UIViewAnimationCurveEaseInOut:
                options = UIViewAnimationOptionCurveEaseInOut;
                break;
            case UIViewAnimationCurveEaseOut:
                options = UIViewAnimationOptionCurveEaseOut;
                break;
            case UIViewAnimationCurveLinear:
                options = UIViewAnimationOptionCurveLinear;
                break;
            default:
                options = UIViewAnimationOptionCurveEaseInOut;
                break;
        }

        [UIView animateWithDuration:animationDuration
                              delay:0
                            options:options
                         animations:^{
                             CGRect f = self.view.frame;
                             f.size.height = keyboardEnd.origin.y - f.origin.y;
                             self.view.frame = f;
                         } completion:nil];
    }
}

#pragma mark - DDGSearchHandler

-(void)searchControllerActionButtonPressed {
    UIViewController *contentViewController = [self.controllers lastObject];
    if ([contentViewController conformsToProtocol:@protocol(DDGSearchHandler)]) {
        UIViewController <DDGSearchHandler> *searchHandler = (UIViewController <DDGSearchHandler> *)contentViewController;
        if([searchHandler respondsToSelector:@selector(searchControllerActionButtonPressed)])
            [searchHandler searchControllerActionButtonPressed];
    } else {
        if([_searchHandler respondsToSelector:@selector(searchControllerActionButtonPressed)])
            [_searchHandler searchControllerActionButtonPressed];
    }
}

-(void)searchControllerLeftButtonPressed {
    [_searchField resignFirstResponder];
    UIViewController *contentViewController = [self.controllers lastObject];
    if ([contentViewController conformsToProtocol:@protocol(DDGSearchHandler)]) {
        [(UIViewController <DDGSearchHandler> *)contentViewController searchControllerLeftButtonPressed];
    } else {
        if ([self.controllers count] > 1)
            [self popContentViewControllerAnimated:YES];
        else
            [_searchHandler searchControllerLeftButtonPressed];
    }
}

-(void)loadQueryOrURL:(NSString *)queryOrURLString {
    UIViewController *contentViewController = [self.controllers lastObject];
    if ([contentViewController conformsToProtocol:@protocol(DDGSearchHandler)]) {
        [(UIViewController <DDGSearchHandler> *)contentViewController loadQueryOrURL:queryOrURLString];
    } else {
        DDGWebViewController *webViewController = [[DDGWebViewController alloc] initWithNibName:nil bundle:nil];
        webViewController.searchController = self;
        [self pushContentViewController:webViewController animated:YES];
        [webViewController loadQueryOrURL:queryOrURLString];
    }
}

-(void)loadStory:(DDGStory *)story readabilityMode:(BOOL)readabilityMode {
    UIViewController *contentViewController = [self.controllers lastObject];
    if ([contentViewController conformsToProtocol:@protocol(DDGSearchHandler)]) {
        [(UIViewController <DDGSearchHandler> *)contentViewController loadStory:story readabilityMode:readabilityMode];
    } else {
        DDGWebViewController *webViewController = [[DDGWebViewController alloc] initWithNibName:nil bundle:nil];
        webViewController.searchController = self;
        [self pushContentViewController:webViewController animated:YES];
        [webViewController loadStory:story readabilityMode:readabilityMode];
    }
}

-(void)prepareForUserInput {
    UIViewController *contentViewController = [self.controllers lastObject];
    if ([contentViewController conformsToProtocol:@protocol(DDGSearchHandler)]) {
        [(UIViewController <DDGSearchHandler> *)contentViewController prepareForUserInput];
    } else {
        [_searchHandler prepareForUserInput];
    }
}

#pragma mark - Interactions with search handler

- (IBAction)actionButtonPressed:(id)sender {
    [self searchControllerActionButtonPressed];
}

- (IBAction)leftButtonPressed:(UIButton*)sender {
    if(autocompleteOpen) {
        [_autocompleteNavigationController popViewControllerAnimated:YES];
    } else {
        [self searchControllerLeftButtonPressed];
    }
}

-(void)setState:(DDGSearchControllerState)searchControllerState {    
    if (_state == searchControllerState)
        return;
    
	_state = searchControllerState;
    
    [self view];
    
    if(_state == DDGSearchControllerStateHome) {
        [_leftButton setImage:[UIImage imageNamed:@"button_menu-default"] forState:UIControlStateNormal];
        [_leftButton setImage:[UIImage imageNamed:@"button_menu-onclick"] forState:UIControlStateHighlighted];
        
        _actionButton.hidden = YES;
        [self clearAddressBar];
        
    } else if (_state == DDGSearchControllerStateWeb) {
        [_leftButton setImage:[UIImage imageNamed:@"home_button.png"] forState:UIControlStateNormal];
        [_leftButton setImage:nil forState:UIControlStateHighlighted];
        
        CGRect f = _cancelButton.frame;
        f.origin.x -= _actionButton.frame.size.width + 5;
        _cancelButton.frame = f;
        
        _actionButton.hidden = NO;
    }
    
    CGRect searchFrame = _searchField.frame;
    CGRect leftFrame = _leftButton.frame;
    CGFloat rightInset = (_actionButton.hidden) ? 0.0 : _actionButton.frame.size.width + 5.0;
    
    searchFrame.origin.x = leftFrame.origin.x + leftFrame.size.width + 5.0;
    searchFrame.size.width = self.view.bounds.size.width - (searchFrame.origin.x + rightInset + 5.0);
    
    _searchField.frame = searchFrame;
}

-(void)stopOrReloadButtonPressed {
    if([_searchHandler respondsToSelector:@selector(searchControllerStopOrReloadButtonPressed)])
        [_searchHandler performSelector:@selector(searchControllerStopOrReloadButtonPressed)];
}

-(void)webViewStartedLoading {
    [stopOrReloadButton setImage:[UIImage imageNamed:@"stop.png"] forState:UIControlStateNormal];
}

-(void)webViewFinishedLoading {
    [stopOrReloadButton setImage:[UIImage imageNamed:@"reload.png"] forState:UIControlStateNormal];    
    [_searchField finish];
}

-(void)webViewCanGoBack:(BOOL)canGoBack {
    if(canGoBack)
        [_leftButton setImage:[UIImage imageNamed:@"back_button.png"] forState:UIControlStateNormal];
    else
        [_leftButton setImage:[UIImage imageNamed:@"home_button.png"] forState:UIControlStateNormal];
}

-(void)setProgress:(CGFloat)progress {
    [_searchField setProgress:progress];
}

#pragma mark - Helper methods

-(NSString *)validURLStringFromString:(NSString *)urlString {
    // check whether the entered text is a URL or a search query
    NSURL *url = [NSURL URLWithString:urlString];
    if(url && url.scheme) {
        // it has a scheme, so it's probably a valid URL
        return urlString;
    } else {
        // check whether adding a scheme makes it a valid URL
        NSString *urlStringWithSchema = [NSString stringWithFormat:@"http://%@",urlString];
        url = [NSURL URLWithString:urlStringWithSchema];
        
        if(url && url.host && [url.host rangeOfString:@"."].location != NSNotFound) {
            // it has a host with a dot ("xyz.com"), so it's probably a URL
            return urlStringWithSchema;
        } else {
            // it can't be made into a valid URL
            return nil;
        }
    }
}

// mostly for clarity
-(BOOL)isQuery:(NSString *)queryOrURL {
    return ![self validURLStringFromString:queryOrURL];
}

-(NSString *)queryFromDDGURL:(NSURL *)url {
    // parse URL query components
    NSArray *queryComponentsArray = [[url query] componentsSeparatedByString:@"&"];
    NSMutableDictionary *queryComponents = [[NSMutableDictionary alloc] init];
    for(NSString *queryComponent in queryComponentsArray) {
        NSArray *parameter = [queryComponent componentsSeparatedByString:@"="];
        if(parameter.count > 1)
            [queryComponents setObject:[parameter objectAtIndex:1] forKey:[parameter objectAtIndex:0]];
    }
    
    // check whether we have a DDG search URL
    if([[url host] isEqualToString:@"duckduckgo.com"]) {
        if([[url path] isEqualToString:@"/"] && [queryComponents objectForKey:@"q"]) {
            // yep! extract the search query...
            NSString *query = [queryComponents objectForKey:@"q"];
            query = [query stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
            query = [query stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            
            return query;
        } else if(![[url pathExtension] isEqualToString:@"html"]) {
            // article page
            NSString *query = [url path];
            query = [query substringFromIndex:1]; // strip the leading '/' in the URL
            query = [query stringByReplacingOccurrencesOfString:@"_" withString:@"%20"];
            query = [query stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            
            return query;
        } else {
            // a URL on DDG.com, but not a search query
            return nil;
        }
    } else {
        // no, just a plain old URL.
        return nil;
    }
}

#pragma mark - Nav controller delegate

-(void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if(!autocompleteOpen)
        return;
    
    BOOL showBackButton = (viewController != [navigationController.viewControllers objectAtIndex:0]);
    NSLog(@"bbv %i",backButtonVisible);
    if(showBackButton != backButtonVisible)
        [UIView animateWithDuration:0.25 animations:^{
            _searchField.frame = [self showBackButton:showBackButton];
        }];
}

#pragma mark - View management

// set up and reveal the autocomplete view
-(void)revealAutocomplete {    
    // save search text in case user cancels input without navigating somewhere
    if(!oldSearchText)
        oldSearchText = _searchField.text;
    barUpdated = NO;
    
    if(![self isQuery:_searchField.text]) {
        [self clearAddressBar];
    }
    
    _searchField.rightView = nil;
    [self revealBackground:YES animated:YES];
    
    [UIView animateWithDuration:0.25 animations:^{        
        CGRect f;
        CGRect searchFieldFrame = [self showBackButton:NO];
        
        if(_state == DDGSearchControllerStateWeb) {
            _actionButton.alpha = 0;
            searchFieldFrame.size.width += _actionButton.frame.size.width + 5;
        }
        
        _cancelButton.alpha = 1;
        
        f = _cancelButton.frame;
        f.origin.x = self.view.bounds.size.width - _cancelButton.frame.size.width - 5;
        _cancelButton.frame = f;
        
        searchFieldFrame.size.width -= _cancelButton.frame.size.width + 5;
        
        _searchField.frame = searchFieldFrame;
    }];
    
    self.slidingViewController.panGesture.enabled = NO;
    
    autocompleteOpen = YES;
}

// cleans up the search field and dismisses
-(void)dismissAutocomplete {
    if (!autocompleteOpen)
        return;
    
    autocompleteOpen = NO;

    self.slidingViewController.panGesture.enabled = YES;
    
    if(_state == DDGSearchControllerStateHome) {
        [_leftButton setImage:[UIImage imageNamed:@"button_menu-default"] forState:UIControlStateNormal];
        [_leftButton setImage:[UIImage imageNamed:@"button_menu-onclick"] forState:UIControlStateHighlighted];
    }

    [_searchField resignFirstResponder];
    if(!barUpdated) {
        _searchField.text = oldSearchText;
        oldSearchText = nil;
    }
    if([_searchHandler respondsToSelector:@selector(searchControllerAddressBarWillCancel)])
        [_searchHandler searchControllerAddressBarWillCancel];
    
    [self revealBackground:NO animated:YES];
    if(_state==DDGSearchControllerStateWeb)
        _searchField.rightView = stopOrReloadButton;
    
    [UIView animateWithDuration:0.25 animations:^{        
        CGRect f;
        CGRect searchFieldFrame = [self showBackButton:YES];
        
        if(_state == DDGSearchControllerStateWeb) {
            _actionButton.alpha = 1;
            searchFieldFrame.size.width -= _actionButton.frame.size.width + 5;
        
            f = _cancelButton.frame;
            f.origin.x = self.view.bounds.size.width - (_actionButton.frame.size.width + 5);
            _cancelButton.frame = f;
        } else {
            f = _cancelButton.frame;
            f.origin.x = self.view.bounds.size.width;
            _cancelButton.frame = f;
        }
        
        _cancelButton.alpha = 0;
        
        searchFieldFrame.size.width += _cancelButton.frame.size.width + 5;
        
        _searchField.frame = searchFieldFrame;
    }];
}

// this returns the updated searchFieldFrame instead of setting it because sometimes we want to make further changes to it
-(CGRect)showBackButton:(BOOL)show {
    if(backButtonVisible == show)
        return _searchField.frame;
    
    backButtonVisible = show;
    
    _leftButton.alpha = (show ? 1 : 0);
    
    CGFloat direction = (show ? 1 : -1);
    
    CGRect f = _leftButton.frame;
    f.origin.x += direction*(_leftButton.frame.size.width + 5);
    _leftButton.frame = f;
    
    CGRect searchFieldFrame = _searchField.frame;
    searchFieldFrame.origin.x += direction*(_leftButton.frame.size.width + 5);
    searchFieldFrame.size.width -= direction*(_leftButton.frame.size.width + 5);
    
    return searchFieldFrame;
}

// fade in or out the autocomplete view- to be used when revealing/hiding autocomplete
- (void)revealBackground:(BOOL)reveal animated:(BOOL)animated {
    
    if(reveal)
        [_autocompleteNavigationController viewWillAppear:animated];
    else
        [_autocompleteNavigationController viewWillDisappear:animated];
    
    if(animated)
        [UIView animateWithDuration:0.25 animations:^{
            _background.alpha = (reveal ? 1.0 : 0.0);
        } completion:^(BOOL finished) {
            if(reveal)
                [_autocompleteNavigationController viewDidAppear:animated];
            else
                [_autocompleteNavigationController viewDidDisappear:animated];
        }];
    else {
        _background.alpha = (reveal ? 1.0 : 0.0);
        if(reveal)
            [_autocompleteNavigationController viewDidAppear:animated];
        else
            [_autocompleteNavigationController viewDidDisappear:animated];
    }
    
}

// fade in or out the input accessory– to be used on keyboard show/hide
-(void)revealInputAccessory:(BOOL)reveal animationDuration:(CGFloat)animationDuration {
    if(reveal) {
        [UIView animateWithDuration:animationDuration animations:^{
            inputAccessory.alpha = 1.0;
        } completion:^(BOOL finished) {
            [self positionNavControllerForInputAccessoryForceHidden:NO];
        }];
    } else {
        [self positionNavControllerForInputAccessoryForceHidden:YES];
        [UIView animateWithDuration:animationDuration animations:^{
            inputAccessory.alpha = 0.0;
        }];
    }
}

-(IBAction)cancelButtonPressed:(id)sender {
    [self dismissAutocomplete];
}

-(void)updateBarWithURL:(NSURL *)url {
    barUpdated = YES;
    NSString *query = [self queryFromDDGURL:url];
    _searchField.text = (query ? query : url.absoluteString);
}

-(void)clearAddressBar {
    _searchField.text = @"";
}

#pragma mark - Input accessory (the bang button/bar)

-(void)createInputAccessory {
    inputAccessory = [[DDGInputAccessoryView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 46, self.view.bounds.size.width, 46)];
    inputAccessory.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    inputAccessory.alpha = 0.0;
    [self.view addSubview:inputAccessory];
    
    // add bang button
    UIButton *bangButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [bangButton setBackgroundImage:[UIImage imageNamed:@"bang_button.png"] forState:UIControlStateNormal];
    bangButton.frame = CGRectMake(0, 0, 46, 46);
    bangButton.tag = 103;
    [bangButton addTarget:self action:@selector(bangButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [inputAccessory addSubview:bangButton];
    
    // add scroll view
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, inputAccessory.bounds.size.width, 46)];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    scrollView.showsHorizontalScrollIndicator = YES;
    scrollView.contentSize = CGSizeMake(0, 46);
    scrollView.tag = 102;
    scrollView.hidden = YES;
    [inputAccessory addSubview:scrollView];
}

// if the input accessory isn't hidden, but is about to hide, you can set forceHidden to position nav controller as though input accessory is hidden. Use this e.g. when animating inputAccessory, so the nav controller shows up behind it.
-(void)positionNavControllerForInputAccessoryForceHidden:(BOOL)forceHidden {
    UIScrollView *scrollView = (UIScrollView *)[inputAccessory viewWithTag:102];
    
    CGRect f = _autocompleteNavigationController.view.frame;
    if(scrollView.hidden || inputAccessory.hidden || inputAccessory.alpha < 0.1 || forceHidden) {
        f.size.height = _autocompleteNavigationController.view.superview.bounds.size.height;
    } else {
        f.size.height = _autocompleteNavigationController.view.superview.bounds.size.height - 44.0;
    }
    _autocompleteNavigationController.view.frame = f;
}

-(void)bangButtonPressed {
    NSString *textToAdd;
    if(_searchField.text.length==0 || [_searchField.text characterAtIndex:_searchField.text.length-1]==' ')
        textToAdd = @"!";
    else
        textToAdd = @" !";

    [self textField:_searchField 
          shouldChangeCharactersInRange:NSMakeRange(_searchField.text.length, 0) 
          replacementString:textToAdd];
    _searchField.text = [_searchField.text stringByAppendingString:textToAdd];
}

-(void)bangAutocompleteButtonPressed:(UIButton *)sender {
    if(currentWordRange.location == NSNotFound) {
        if(_searchField.text.length == 0)
            _searchField.text = sender.titleLabel.text;
        else
            [_searchField setText:[_searchField.text stringByAppendingFormat:@" %@",sender.titleLabel.text]];
    } else {
        [_searchField setText:[_searchField.text stringByReplacingCharactersInRange:currentWordRange withString:sender.titleLabel.text]];
    }
}

-(void)loadSuggestionsForBang:(NSString *)bang {
    UIScrollView *scrollView = (UIScrollView *)[inputAccessory viewWithTag:102];
    
    NSArray *suggestions = [DDGBangsProvider bangsWithPrefix:bang];
    if(suggestions.count > 0) {
        scrollView.hidden = NO;
        [self positionNavControllerForInputAccessoryForceHidden:NO];
        UIButton *bangButton = (UIButton *)[inputAccessory viewWithTag:103];
        [bangButton setBackgroundImage:[UIImage imageNamed:@"bang_button_open.png"] forState:UIControlStateNormal];
        bangButton.hidden = YES;
    }
    UIImage *backgroundImg = [[UIImage imageNamed:@"empty_bang_button.png"] stretchableImageWithLeftCapWidth:7.0 topCapHeight:0];

    for(NSDictionary *suggestionDict in suggestions) {
        NSString *suggestion = [suggestionDict objectForKey:@"name"];

        UIButton *button;
        if([unusedBangButtons count] > 0) {
            button = [unusedBangButtons lastObject];
            [unusedBangButtons removeLastObject];
        } else {
            button = [UIButton buttonWithType:UIButtonTypeCustom];   
            [button.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
            [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            [button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [button.titleLabel setShadowOffset:CGSizeMake(0, 1)];
        }

        [button setTitle:suggestion forState:UIControlStateNormal];
        [button addTarget:self action:@selector(bangAutocompleteButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        CGSize titleSize = [suggestion sizeWithFont:button.titleLabel.font];
        
        [button setFrame:CGRectMake(scrollView.contentSize.width, 0, (titleSize.width > 30 ? titleSize.width + 20 : 50), 46)];
        [button setBackgroundImage:backgroundImg forState:UIControlStateNormal];
        scrollView.contentSize = CGSizeMake(scrollView.contentSize.width + button.frame.size.width, 46);
        [scrollView addSubview:button];
    }
}

-(void)clearBangSuggestions {
    UIScrollView *scrollView = (UIScrollView *)[inputAccessory viewWithTag:102];
    
    scrollView.contentSize = CGSizeMake(0, 46);
    for(UIView *subview in scrollView.subviews) {
        if([subview isKindOfClass:[UIButton class]]) {
            [subview removeFromSuperview];
            [unusedBangButtons addObject:subview];
        }
    }
    
    scrollView.hidden = YES;
    [self positionNavControllerForInputAccessoryForceHidden:NO];
    
    UIButton *bangButton = (UIButton *)[inputAccessory viewWithTag:103];
    [bangButton setBackgroundImage:[UIImage imageNamed:@"bang_button.png"] forState:UIControlStateNormal];
    bangButton.hidden = NO;
}

#pragma mark - Text field delegate

-(void)searchFieldDidChange:(id)sender
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:DDGSettingAutocomplete])
	{
		// autocomplete only when enabled
		DDGAutocompleteViewController *autocompleteViewController = [_autocompleteNavigationController.viewControllers objectAtIndex:0];
		if(_autocompleteNavigationController.topViewController != autocompleteViewController)
			[_autocompleteNavigationController popToRootViewControllerAnimated:NO];
		
		[autocompleteViewController searchFieldDidChange:_searchField];
	}
}

-(BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // find the word that the cursor is currently in and update the bang bar based on it
    
    NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];

    if(newString.length == 0) {
        currentWordRange = NSMakeRange(NSNotFound, 0);
        [self clearBangSuggestions];
        return YES; // there's nothing we can do with an empty string
    }
    
    // find word beginning
    int wordBeginning;
    for(wordBeginning = range.location+string.length;wordBeginning>=0;wordBeginning--) {
        if(wordBeginning == 0 || [newString characterAtIndex:wordBeginning-1] == ' ')
            break;
    }

    // find word end
    int wordEnd;
    for(wordEnd = wordBeginning;wordEnd<newString.length;wordEnd++) {
        if(wordEnd == newString.length || [newString characterAtIndex:wordEnd] == ' ')
            break;
    }
    
    currentWordRange = NSMakeRange(wordBeginning, wordEnd-wordBeginning);
    
    NSString *currentWord;
    if(currentWordRange.length == 0)
        currentWord = @"";
    else
        currentWord = [newString substringWithRange:currentWordRange];
    
    [self clearBangSuggestions];
    if(currentWord.length > 0 && [currentWord characterAtIndex:0]=='!') {
        [self loadSuggestionsForBang:currentWord];
    }
    
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
	// save search text in case user cancels input without navigating somewhere
    if(!oldSearchText)
        oldSearchText = textField.text;
    
    [self clearBangSuggestions];
    
    return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if([_searchHandler respondsToSelector:@selector(searchControllerAddressBarWillOpen)])
        [_searchHandler searchControllerAddressBarWillOpen];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dismissAutocomplete)
                                                 name:ECSlidingViewUnderLeftWillAppear
                                               object:self.slidingViewController];
    
	return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    currentWordRange = NSMakeRange(NSNotFound, 0);
	// only open autocomplete if not already open and it is enabled for use
    if(!autocompleteOpen && [[NSUserDefaults standardUserDefaults] boolForKey:DDGSettingAutocomplete])
        [self revealAutocomplete];
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField {
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:ECSlidingViewUnderLeftWillAppear
                                                  object:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	NSString *s = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (![s length]) {
		textField.text = nil;
		return NO;
	}
	[textField resignFirstResponder];
	
	if ([_searchField.text length])
        [self.historyProvider logSearchResultWithTitle:_searchField.text];

    [self loadQueryOrURL:([_searchField.text length] ? _searchField.text : nil)];
    [self dismissAutocomplete];

    oldSearchText = nil;
	return YES;
}

@end

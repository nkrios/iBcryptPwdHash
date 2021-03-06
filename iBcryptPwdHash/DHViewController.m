//
//  DHViewController.m
//  iBcryptPwdHash
//
//  Created by Daniel Hjort on 5/2/14.
//  Copyright (c) 2014 Daniel Hjort. All rights reserved.
//

#import "DHViewController.h"
#import "JFBCrypt.h"
#import "DHPwdHashUtil.h"

#define IDIOM    UI_USER_INTERFACE_IDIOM()
#define IPAD     UIUserInterfaceIdiomPad

static const float IPAD_LANDSCAPE_INPUT_SHIFT = 120;

@interface DHViewController ()

@end

@implementation DHViewController {
    BOOL mRoundsAreVisible, mBookmarksAreVisible;
    BOOL mIpadInputShifted;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.roundsPickerHandler = [[DHRoundsPickerHandler alloc] initWithDelegate:self];
    if (IDIOM == IPAD) {
        self.roundsPickerController = [[DHPickerViewController alloc] init];
        self.roundsPopoverController = [[UIPopoverController alloc] initWithContentViewController:self.roundsPickerController];
        [self.roundsPickerController addPickerHandler:self.roundsPickerHandler];
        [self.roundsPickerController.picker selectRow:self.roundsPickerHandler.defaultRow inComponent:0 animated:NO];
    } else {
        self.roundsPicker.dataSource = self.roundsPickerHandler;
        self.roundsPicker.delegate = self.roundsPickerHandler;
        [self.roundsPicker selectRow:self.roundsPickerHandler.defaultRow inComponent:0 animated:NO];
    }
    [self.saltField setText:[self.roundsPickerHandler getCurrentSalt]];
    
    self.bookmarksPickerHandler = [[DHBookmarksPickerHandler alloc] initWithPicker:self.bookmarksPicker AndDelegate:self];
    if (IDIOM == IPAD) {
        self.bookmarksPickerController = [[DHPickerViewController alloc] init];
        self.bookmarksPopoverController = [[UIPopoverController alloc] initWithContentViewController:self.bookmarksPickerController];
        [self.bookmarksPickerController addPickerHandler:self.bookmarksPickerHandler];
        self.bookmarksPickerHandler.picker = self.bookmarksPickerController.picker;
    } else {
        self.bookmarksPicker.dataSource = self.bookmarksPickerHandler;
        self.bookmarksPicker.delegate = self.bookmarksPickerHandler;
    }
    
    [self.bottomConstraintCopyright setConstant:13];
    [self.bottomConstraintBookmarks setConstant:0];
    [self.bottomConstraintRounds setConstant:0];
    mRoundsAreVisible = NO;
    mBookmarksAreVisible = NO;
    
    CGRect toolBarFrame = [self.toolBar frame];
    toolBarFrame.origin.y = 20;
    [self.toolBar setFrame:toolBarFrame];
    
    [self.hashedPasswordLabel setText:@""];
    self.addressField.delegate = self;
    self.saltField.delegate = self;
    self.passwordField.delegate = self;
    
    [self.addressField setText:@"http://www.example.com"];
    [self.createButton setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    
    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(handleTaps:)];
    [self.tapView addGestureRecognizer:self.tapGestureRecognizer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    if (IDIOM == IPAD) {
        
        if (UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation))
        {
            self.topConstraintInputIpad.constant -= IPAD_LANDSCAPE_INPUT_SHIFT;
            mIpadInputShifted = YES;
        } else {
            mIpadInputShifted = NO;
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Helpers

- (void)copyToPasteboard:(NSString*)text
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = text;
}

- (void)allTextFieldResign
{
    [self.addressField resignFirstResponder];
    [self.saltField resignFirstResponder];
    [self.passwordField resignFirstResponder];
}

- (void)inputEnabled:(BOOL)enabled
{
    self.addressField.enabled = enabled;
    self.saltField.enabled = enabled;
    self.passwordField.enabled = enabled;
    self.createButton.enabled = enabled;
    
    if (!enabled) {
        [self allTextFieldResign];
    }
}

- (void)updateWithResult:(NSString*)result
{
    // copy to clipboard
    [self.infoLabel setText:NSLocalizedString(@"PwCopiedKey", @"")];
    [self copyToPasteboard:result];
    [self.hashedPasswordLabel setText:result];
    
    [self inputEnabled:YES];
}

- (void)create
{
    [self.infoLabel setText:NSLocalizedString(@"PleaseWaitKey", @"")];
    [self inputEnabled:NO];

    // check salt
    NSString* salt = [self.saltField text];
    if (salt.length == 0) {
        salt = [JFBCrypt generateSaltWithNumberOfRounds:self.roundsPickerHandler.selectedRounds];
        [self.saltField setText:salt];
    } else if (![salt hasPrefix:@"$2a$"]
               || salt.length != 29) {
        // invalid salt
        [self inputEnabled:YES];
        [self.infoLabel setText:NSLocalizedString(@"SaltNotValidKey", @"")];
        return;
    }
    [self.roundsPickerHandler saveSalt:salt ForRounds:self.roundsPickerHandler.selectedRounds];
    
    NSString* address = [self.addressField text];
    NSString* domain = [DHPwdHashUtil extractDomain:address];
    if (domain.length == 0) {
        // no entered password
        [self inputEnabled:YES];
        [self.infoLabel setText:NSLocalizedString(@"EnterSiteKey", @"")];
        return;
    }
    [self.bookmarksPickerHandler saveBookmark:address];
    
    NSString* password = [self.passwordField text];
    if (password.length == 0) {
        // no entered password
        [self inputEnabled:YES];
        [self.infoLabel setText:NSLocalizedString(@"EnterPasswordKey", @"")];
        return;
    }
    
    NSString* toBeHashed = [domain stringByAppendingString:password];
    
    // clear previous
    [self copyToPasteboard:@""];
    [self.hashedPasswordLabel setText:@""];
    
    /* do the rest asyncronously */
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // do the hashing
        NSString* hash = [JFBCrypt hashPassword:toBeHashed withSalt:salt];
        NSString* result = [DHPwdHashUtil removeSalt:salt FromHash:hash];
        result = [DHPwdHashUtil applySize:password.length + 2 AndAlphaNumerical:[DHPwdHashUtil isAlphaNumeric:password] ToPassword:result];
        
        [self performSelectorOnMainThread:@selector(updateWithResult:) withObject:result waitUntilDone:NO];
    });
}

#pragma mark - Popovers (iPad)

- (void)showBookmarksPopover
{
    if ([self.roundsPopoverController isPopoverVisible]) {
        [self.roundsPopoverController dismissPopoverAnimated:YES];
    }
    [self.bookmarksPopoverController presentPopoverFromBarButtonItem:self.bookmarksButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)showRoundsPopover
{
    if ([self.bookmarksPopoverController isPopoverVisible]) {
        [self.bookmarksPopoverController dismissPopoverAnimated:YES];
    }
    [self.roundsPopoverController presentPopoverFromBarButtonItem:self.roundsButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

#pragma mark - Animations (iPhone)

- (void)hideCopyright
{
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.copyrightLabel.alpha = 0;
                     }];
}

- (void)showCopyright
{
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.copyrightLabel.alpha = 0.5;
                     }];
}

- (void)hideRounds
{
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.bottomConstraintRounds.constant = 0;
                         [self.view layoutIfNeeded];
                     }];
    [self showCopyright];
    mRoundsAreVisible = FALSE;
}

- (void)showRounds
{
    
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.bottomConstraintRounds.constant = 162;
                         [self.view layoutIfNeeded];
                     }];
    [self hideCopyright];
    mRoundsAreVisible = TRUE;
}

- (void)hideBookmarks
{
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.bottomConstraintBookmarks.constant = 0;
                         [self.view layoutIfNeeded];
                     }];
    [self showCopyright];
    mBookmarksAreVisible = FALSE;
}

- (void)showBookmarks
{
    
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.5
                    animations:^{
                        self.bottomConstraintBookmarks.constant = 162;
                        [self.view layoutIfNeeded];
                        }];
    [self hideCopyright];
    mBookmarksAreVisible = TRUE;
}

#pragma mark - Actions

- (IBAction)createAction:(id)sender
{
    NSLog(@"createAction");
    
    [self create];
}

- (IBAction)roundsAction:(id)sender
{
    NSLog(@"settingsAction");
    // show/hide rounds pop-over/spinner
    
    if (IDIOM == IPAD) {
        [self showRoundsPopover];
        return;
    } else {
        [self allTextFieldResign];
    }
    
    if (mRoundsAreVisible) {
            [self hideRounds];
    } else {
        if (mBookmarksAreVisible) {
            [self hideBookmarks];
        }
        [self showRounds];
    }
}

- (IBAction)bookmarksAction:(id)sender
{
    NSLog(@"bookmarksAction");
    // show/hide bookmarks pop-over/spinner
    
    if (IDIOM == IPAD) {
        [self showBookmarksPopover];
        return;
    } else {
        [self allTextFieldResign];
    }
    
    if (mBookmarksAreVisible) {
        [self hideBookmarks];
    } else {
        if (mRoundsAreVisible) {
            [self hideRounds];
        }
        [self showBookmarks];
    }
}

#pragma mark - Notifications

- (void)keyboardWillShow:(NSNotification *)notification
{
    [self hideBookmarks];
    [self hideRounds];
}

- (void)orientationDidChange:(NSNotification *)notification
{
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    switch (orientation)
    {
        case UIDeviceOrientationLandscapeLeft:
        case UIDeviceOrientationLandscapeRight:
            if (!mIpadInputShifted) {
                self.topConstraintInputIpad.constant -= IPAD_LANDSCAPE_INPUT_SHIFT;
                mIpadInputShifted = YES;
            }
            break;
            
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationPortrait:
        case UIDeviceOrientationPortraitUpsideDown:
        case UIDeviceOrientationUnknown:
        default:
            if (mIpadInputShifted) {
                self.topConstraintInputIpad.constant += IPAD_LANDSCAPE_INPUT_SHIFT;
                mIpadInputShifted = NO;
            }
    }
}

#pragma mark - DHBookmarkPickerDelegate

- (void)selectedBookmark:(NSString*)bookmark
{
    [self.addressField setText:bookmark];
}

#pragma mark - DHRoundsPickerDelegate

- (void)selectedRounds:(int)rounds WithSalt:(NSString*)salt
{
    [self.saltField setText:salt];
}

#pragma mark - UITextfieldDelegate

- (BOOL) textFieldShouldClear:(UITextField *)textField{
    
    if (textField == self.passwordField) {
        [self.infoLabel setText:NSLocalizedString(@"PasswordErasedKey", @"")];
        [self copyToPasteboard:@""];
        [self.hashedPasswordLabel setText:@""];
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    
    if (textField == self.addressField) {
        [self.addressField resignFirstResponder];
        [self.saltField becomeFirstResponder];
    } else if (textField == self.saltField) {
        [self.saltField resignFirstResponder];
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.passwordField) {
        [self create];
    }
    return YES;
}

#pragma mark - UITapGestureRecognizer

- (void) handleTaps:(UITapGestureRecognizer*)paramSender
{
    [self allTextFieldResign];
    if (mRoundsAreVisible) {
        [self hideRounds];
    }
    if (mBookmarksAreVisible) {
        [self hideBookmarks];
    }
}

@end

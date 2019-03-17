//
//  UploadViewController.m
//  piwigo
//
//  Created by Spencer Baker on 1/20/15.
//  Copyright (c) 2015 bakercrew. All rights reserved.
//

#import <Photos/Photos.h>

#import "AppDelegate.h"
#import "CategoriesData.h"
#import "ImageDetailViewController.h"
#import "ImageUpload.h"
#import "ImageUploadManager.h"
#import "ImageUploadProgressView.h"
#import "ImageUploadViewController.h"
#import "ImagesCollection.h"
#import "LocalImagesHeaderReusableView.h"
#import "LocalImageCollectionViewCell.h"
#import "MBProgressHUD.h"
#import "NoImagesHeaderCollectionReusableView.h"
#import "NotUploadedYet.h"
#import "PhotosFetch.h"
#import "UploadViewController.h"

NSInteger const kMaxNberOfLocationsToDecode = 10;

@interface UploadViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate, PHPhotoLibraryChangeObserver, ImageUploadProgressDelegate, LocalImagesHeaderDelegate>

@property (nonatomic, strong) UICollectionView *localImagesCollection;
@property (nonatomic, assign) NSInteger categoryId;
@property (nonatomic, assign) NSInteger nberOfImagesPerRow;
@property (nonatomic, strong) NSArray *imagesInSections;
@property (nonatomic, strong) NSMutableArray *locationOfImagesInSections;
@property (nonatomic, strong) PHAssetCollection *groupAsset;

@property (nonatomic, strong) UILabel *noImagesLabel;

@property (nonatomic, strong) UIBarButtonItem *sortBarButton;
@property (nonatomic, strong) UIBarButtonItem *cancelBarButton;
@property (nonatomic, strong) UIBarButtonItem *uploadBarButton;

@property (nonatomic, strong) NSMutableArray *touchedImages;
@property (nonatomic, strong) NSMutableArray *selectedImages;
@property (nonatomic, strong) NSMutableArray *selectedSections;

@property (nonatomic, assign) kPiwigoSortBy sortType;
@property (nonatomic, assign) BOOL removeUploadedImages;
@property (nonatomic, strong) UIViewController *hudViewController;

@end

@implementation UploadViewController

-(instancetype)initWithCategoryId:(NSInteger)categoryId andGroupAsset:(PHAssetCollection*)groupAsset
{
    self = [super init];
    if(self)
    {
        self.view.backgroundColor = [UIColor piwigoBackgroundColor];
        self.categoryId = categoryId;
        self.groupAsset = groupAsset;
        self.sortType = kPiwigoSortByNewest;
        self.removeUploadedImages = NO;
        self.imagesInSections = [[PhotosFetch sharedInstance] getImagesForAssetGroup:self.groupAsset
                                 inAscendingOrder:NO];

        // Initialise arrays used to manage selections
        self.touchedImages = [NSMutableArray new];
        self.selectedImages = [NSMutableArray new];
        [self initSelectButtons];
        
        // Initialise locations of sections
        [self initLocationsOfSections];

        // Collection of images
        UICollectionViewFlowLayout *collectionFlowLayout = [UICollectionViewFlowLayout new];
        collectionFlowLayout.scrollDirection = UICollectionViewScrollDirectionVertical;
        if (@available(iOS 9.0, *)) {
            collectionFlowLayout.sectionHeadersPinToVisibleBounds = YES;
        }
        self.localImagesCollection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:collectionFlowLayout];
        self.localImagesCollection.translatesAutoresizingMaskIntoConstraints = NO;
        self.localImagesCollection.backgroundColor = [UIColor clearColor];
        self.localImagesCollection.alwaysBounceVertical = YES;
        self.localImagesCollection.showsVerticalScrollIndicator = YES;
        self.localImagesCollection.dataSource = self;
        self.localImagesCollection.delegate = self;

        [self.localImagesCollection registerClass:[NoImagesHeaderCollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"NoImagesHeaderCollection"];
        [self.localImagesCollection registerNib:[UINib nibWithNibName:@"LocalImagesHeaderReusableView" bundle:nil] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"LocalImagesHeaderReusableView"];
        [self.localImagesCollection registerClass:[LocalImageCollectionViewCell class] forCellWithReuseIdentifier:@"LocalImageCollectionViewCell"];

        [self.view addSubview:self.localImagesCollection];
        [self.view addConstraints:[NSLayoutConstraint constraintFillSize:self.localImagesCollection]];
        if (@available(iOS 11.0, *)) {
            [self.localImagesCollection setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentAlways];
        } else {
            // Fallback on earlier versions
        }

        // Bar buttons
        self.sortBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"list"] landscapeImagePhone:[UIImage imageNamed:@"listCompact"] style:UIBarButtonItemStylePlain target:self action:@selector(askSortType)];
        [self.sortBarButton setAccessibilityIdentifier:@"Sort"];
        self.cancelBarButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelSelect)];
        [self.cancelBarButton setAccessibilityIdentifier:@"Cancel"];
        self.uploadBarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"upload"] style:UIBarButtonItemStylePlain target:self action:@selector(presentImageUploadView)];
        
        // Register Photo Library changes
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];

        // Register palette changes
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(paletteChanged) name:kPiwigoNotificationPaletteChanged object:nil];
    }
    return self;
}


#pragma mark - View Lifecycle

-(void)viewDidLoad
{
    [super viewDidLoad];
    
    if([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
    {
        [self setEdgesForExtendedLayout:UIRectEdgeNone];
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // Set colors, fonts, etc.
    [self paletteChanged];
    
    // Update navigation bar and title
    [self updateNavBar];
    
    // Scale width of images on iPad so that they seem to adopt a similar size
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        CGFloat mainScreenWidth = MIN([UIScreen mainScreen].bounds.size.width,
                                     [UIScreen mainScreen].bounds.size.height);
        CGFloat currentViewWidth = MIN(self.view.bounds.size.width,
                                       self.view.bounds.size.height);
        self.nberOfImagesPerRow = roundf(currentViewWidth / mainScreenWidth * [Model sharedInstance].thumbnailsPerRowInPortrait);
    }
    else {
        self.nberOfImagesPerRow = [Model sharedInstance].thumbnailsPerRowInPortrait;
    }

    // Progress bar
    [ImageUploadProgressView sharedInstance].delegate = self;
    [[ImageUploadProgressView sharedInstance] changePaletteMode];
    
    if([ImageUploadManager sharedInstance].imageUploadQueue.count > 0)
    {
        [[ImageUploadProgressView sharedInstance] addViewToView:self.view forBottomLayout:self.bottomLayoutGuide];
    }
    
    // Reload collection (and display those being uploaded)
    [self.localImagesCollection reloadData];
}

-(void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    // Save position of collection view
    NSArray *visibleCells = [self.localImagesCollection visibleCells];
    LocalImageCollectionViewCell *cell = [visibleCells firstObject];
    NSIndexPath *indexPath = [self.localImagesCollection indexPathForCell:cell];
    PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];

    //Reload the tableview on orientation change, to match the new width of the table.
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self updateNavBar];
        [self.localImagesCollection reloadData];
        
        // Scroll to previous position
        NSIndexPath *indexPath = [self indexPathOfImageAsset:imageAsset];
        [self.localImagesCollection scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
    } completion:nil];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

-(void)paletteChanged
{
    // Background color of the view
    self.view.backgroundColor = [UIColor piwigoBackgroundColor];
    
    // Navigation bar appearence
    NSDictionary *attributes = @{
                                 NSForegroundColorAttributeName: [UIColor piwigoWhiteCream],
                                 NSFontAttributeName: [UIFont piwigoFontNormal],
                                 };
    self.navigationController.navigationBar.titleTextAttributes = attributes;
    [self.navigationController.navigationBar setTintColor:[UIColor piwigoOrange]];
    [self.navigationController.navigationBar setBarTintColor:[UIColor piwigoBackgroundColor]];
    self.navigationController.navigationBar.barStyle = [Model sharedInstance].isDarkPaletteActive ? UIBarStyleBlack : UIBarStyleDefault;
    
    // Collection view
    self.localImagesCollection.indicatorStyle = [Model sharedInstance].isDarkPaletteActive ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleBlack;
    [self.localImagesCollection reloadData];
}

-(void)updateNavBar
{
    switch (self.selectedImages.count) {
        case 0:
            self.navigationItem.leftBarButtonItems = @[];
            // Do not show two buttons provide enough space for title
            // See https://www.paintcodeapp.com/news/ultimate-guide-to-iphone-resolutions
            if(self.view.bounds.size.width <= 414) {     // i.e. smaller than iPhones 6,7 Plus screen width
                self.navigationItem.rightBarButtonItems = @[self.sortBarButton];
            }
            else {
                self.navigationItem.rightBarButtonItems = @[self.sortBarButton, self.uploadBarButton];
                [self.uploadBarButton setEnabled:NO];
            }
            self.title = NSLocalizedString(@"selectImages", @"Select Images");
            break;
            
        case 1:
            self.navigationItem.leftBarButtonItems = @[self.cancelBarButton];
            // Do not show two buttons provide enough space for title
            // See https://www.paintcodeapp.com/news/ultimate-guide-to-iphone-resolutions
            if(self.view.bounds.size.width <= 414) {     // i.e. smaller than iPhones 6,7 Plus screen width
                self.navigationItem.rightBarButtonItems = @[self.uploadBarButton];
            }
            else {
                self.navigationItem.rightBarButtonItems = @[self.sortBarButton, self.uploadBarButton];
            }
            [self.uploadBarButton setEnabled:YES];
            self.title = NSLocalizedString(@"selectImageSelected", @"1 Image Selected");
            break;
            
        default:
            self.navigationItem.leftBarButtonItems = @[self.cancelBarButton];
            // Do not show two buttons provide enough space for title
            // See https://www.paintcodeapp.com/news/ultimate-guide-to-iphone-resolutions
            if(self.view.bounds.size.width <= 414) {     // i.e. smaller than iPhones 6,7 Plus screen width
                self.navigationItem.rightBarButtonItems = @[self.uploadBarButton];
            }
            else {
                self.navigationItem.rightBarButtonItems = @[self.sortBarButton, self.uploadBarButton];
            }
            [self.uploadBarButton setEnabled:YES];
            self.title = [NSString stringWithFormat:NSLocalizedString(@"selectImagesSelected", @"%@ Images Selected"), @(self.selectedImages.count)];
            break;
    }
}


#pragma mark - Manage Images

-(void)initLocationsOfSections
{
    // Initalisation
    self.locationOfImagesInSections = [NSMutableArray new];

    // Determine locations of images in sections
    for (NSArray *imagesInSection in self.imagesInSections) {
        
        // Initialise location of section with invalid location
        CLLocation *locationForSection = [[CLLocation alloc]
                                          initWithCoordinate:kCLLocationCoordinate2DInvalid
                                          altitude:0.0
                                          horizontalAccuracy:0.0 verticalAccuracy:0.0
                                          timestamp:[NSDate date]];
        
        // Loop over images of section
        for (PHAsset *imageAsset in imagesInSection) {
            
            // Any location data ?
            if ((imageAsset.location == nil) ||
                !CLLocationCoordinate2DIsValid(imageAsset.location.coordinate)) {
                // Image has no valid location data => Next image
                continue;
            }
            
            // Location found => Store it and move to next section
            if (!CLLocationCoordinate2DIsValid(locationForSection.coordinate)) {
                // First valid location => Store it
                locationForSection = imageAsset.location;
            } else {
                // Another valid location => Compare to first one
                if ([imageAsset.location distanceFromLocation:locationForSection] < 1000000) {
                    // Reduce precision - Latitude
//                    CGFloat dif = fabs(imageAsset.location.coordinate.latitude - locationForSection.coordinate.latitude);
//                    CGFloat latitude = locationForSection.coordinate.latitude;
//                    CGFloat longitude = locationForSection.coordinate.longitude;
//                    if (dif > 0) {
//                        CGFloat corr = roundf(1.0 / dif);
//                        latitude = roundf(locationForSection.coordinate.latitude * corr) / corr;
//                    }
//                    // Reduce precision - Longitude
//                    dif = fabs(imageAsset.location.coordinate.longitude - locationForSection.coordinate.longitude);
//                    if (dif > 0) {
//                        CGFloat corr = roundf(1.0 / dif);
//                        longitude = roundf(locationForSection.coordinate.longitude * corr) / corr;
//                    }
//                    // Update location for section
//                    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
//                    CLLocation *newLocation = [[CLLocation alloc] initWithCoordinate:coordinate
//                                                altitude:locationForSection.altitude
//                                                horizontalAccuracy:locationForSection.horizontalAccuracy
//                                                verticalAccuracy:locationForSection.verticalAccuracy
//                                                timestamp:locationForSection.timestamp];
//                    locationForSection = newLocation;
                }
            }
        }
        
        // Store location for current section
        [self.locationOfImagesInSections addObject:locationForSection];
    }
}

-(NSIndexPath *)indexPathOfImageAsset:(PHAsset *)imageAsset
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:0];
    
    // Loop over all sections
    for (NSInteger section = 0; section < [self.localImagesCollection numberOfSections]; section++)
    {
        // Index of image in section?
        NSInteger item = [[self.imagesInSections objectAtIndex:section] indexOfObject:imageAsset];
        if (item != NSNotFound) {
            indexPath = [NSIndexPath indexPathForItem:item inSection:section];
            break;
        }
    }
    return indexPath;
}

-(void)askSortType
{
    UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"sortBy", @"Sort by")
            message:NSLocalizedString(@"imageSortMessage", @"Please select how you wish to sort images")
            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"alertCancelButton", @"Cancel")
            style:UIAlertActionStyleCancel
            handler:^(UIAlertAction * action) {}];
    
    UIAlertAction *newestAction = [UIAlertAction
            actionWithTitle:[PhotosFetch getNameForSortType:kPiwigoSortByNewest]
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
                // Change sort option
                self.sortType = kPiwigoSortByNewest;
                
                // Sort images
                [self sortImagesInAscendingOrder:NO];
            }];
    
    UIAlertAction* oldestAction = [UIAlertAction
            actionWithTitle:[PhotosFetch getNameForSortType:kPiwigoSortByOldest]
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) {
                // Change sort option
                self.sortType = kPiwigoSortByOldest;
                
                // Sort images
                [self sortImagesInAscendingOrder:YES];
            }];
    
    UIAlertAction* uploadedAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"localImageSort_notUploaded", @"Not Uploaded")
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) {
                // Remove uploaded images?
                if (self.removeUploadedImages)
                {
                    // Store choice
                    self.removeUploadedImages = NO;
                    
                    // Sort images
                    switch (self.sortType) {
                        case kPiwigoSortByNewest:
                            [self sortImagesInAscendingOrder:NO];
                            break;
                            
                        case kPiwigoSortByOldest:
                            [self sortImagesInAscendingOrder:YES];
                            break;
                            
                        default:
                            break;
                    }
                }
                else {
                    // Store choice
                    self.removeUploadedImages = YES;
                    
                    // Remove uploaded images from collection
                    [self removeUploadedImagesFromCollection];
                }
            }];
    
    // Add actions
    [alert addAction:cancelAction];
    switch (self.sortType) {
        case kPiwigoSortByNewest:
            [alert addAction:oldestAction];
            [alert addAction:uploadedAction];
            break;
            
        case kPiwigoSortByOldest:
            [alert addAction:newestAction];
            [alert addAction:uploadedAction];
            break;
            
        default:
            break;
    }
    
    // Present list of actions
    alert.popoverPresentationController.barButtonItem = self.sortBarButton;
    [self presentViewController:alert animated:YES completion:nil];
}

-(void)sortImagesInAscendingOrder:(BOOL)ascending
{
    // Save position of collection view
    NSArray *visibleCells = [self.localImagesCollection visibleCells];
    LocalImageCollectionViewCell *cell = [visibleCells firstObject];
    NSIndexPath *indexPath = [self.localImagesCollection indexPathForCell:cell];
    PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
    
    // Retrieve images according to chosen sort order
    self.imagesInSections = [[PhotosFetch sharedInstance] getImagesForAssetGroup:self.groupAsset
                                                                inAscendingOrder:ascending];
    // Initialise locations of sections
    [self initLocationsOfSections];
    
    // Update Select buttons status
    [self updateSelectButtons];
    
    // Refresh collection view
    [self.localImagesCollection reloadData];
    
    // Scroll to previous position
    indexPath = [self indexPathOfImageAsset:imageAsset];
    [self.localImagesCollection scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
}

-(void)removeUploadedImagesFromCollection
{
    // Show HUD during download
    PiwigoAlbumData *downloadingCategory = [[CategoriesData sharedInstance] getCategoryById:self.categoryId];
    dispatch_async(dispatch_get_main_queue(),
       ^(void){
           [self showHUDwithTitle:NSLocalizedString(@"downloadingImageInfo", @"Downloading Image Info") withDetailLabel:[NSString stringWithFormat:@"%d / %ld", 0, (long)downloadingCategory.numberOfImages]];
       });

    // Remove uploaded images from the collection
    [NotUploadedYet getListOfImageNamesThatArentUploadedForCategory:self.categoryId
                 withImages:self.imagesInSections
                forProgress:^(NSInteger onPage, NSInteger outOf) {
                    
                    // Update HUD
                    dispatch_async(dispatch_get_main_queue(),
                       ^(void){
                           [self showHUDwithTitle:NSLocalizedString(@"downloadingImageInfo", @"Downloading Image Info") withDetailLabel:[NSString stringWithFormat:@"%ld / %ld", (long)onPage, (long)outOf]];
                       });

                } onCompletion:^(NSArray *imagesNotUploaded) {

                    // Update image list
                    self.imagesInSections = imagesNotUploaded;

                    // Initialise locations of sections
                    [self initLocationsOfSections];
                    
                    // Update Select buttons status
                    [self updateSelectButtons];
                    
                    // Hide HUD
                    dispatch_async(dispatch_get_main_queue(),
                       ^(void){
                           [self hideHUDwithSuccess:YES completion:^{
                               self.hudViewController = nil;
                               
                               // Refresh collection view
                               [self.localImagesCollection reloadData];
                           }];
                       });
                }];
}


#pragma mark - HUD methods

-(void)showHUDwithTitle:(NSString *)title withDetailLabel:(NSString*)label
{
    // Determine the present view controller if needed (not necessarily self.view)
    if (!self.hudViewController) {
        self.hudViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (self.hudViewController.presentedViewController) {
            self.hudViewController = self.hudViewController.presentedViewController;
        }
    }
    
    // Create the login HUD if needed
    MBProgressHUD *hud = [self.hudViewController.view viewWithTag:loadingViewTag];
    if (!hud) {
        // Create the HUD
        hud = [MBProgressHUD showHUDAddedTo:self.hudViewController.view animated:YES];
        [hud setTag:loadingViewTag];
        
        // Change the background view shape, style and color.
        hud.square = NO;
        hud.animationType = MBProgressHUDAnimationFade;
        hud.backgroundView.style = MBProgressHUDBackgroundStyleSolidColor;
        hud.backgroundView.color = [UIColor colorWithWhite:0.f alpha:0.5f];
        hud.contentColor = [UIColor piwigoHudContentColor];
        hud.bezelView.color = [UIColor piwigoHudBezelViewColor];
        
        // Will look best, if we set a minimum size.
        hud.minSize = CGSizeMake(200.f, 100.f);
    }
    
    // Set title
    hud.label.text = title;
    hud.label.font = [UIFont piwigoFontNormal];
    
    // Set label
    hud.mode = MBProgressHUDModeIndeterminate;
    hud.detailsLabel.text = label;
    hud.detailsLabel.font = [UIFont piwigoFontSmall];
}

-(void)hideHUDwithSuccess:(BOOL)success completion:(void (^)(void))completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Hide and remove the HUD
        MBProgressHUD *hud = [self.hudViewController.view viewWithTag:loadingViewTag];
        if (hud) {
            if (success) {
                UIImage *image = [[UIImage imageNamed:@"completed"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
                hud.customView = imageView;
                hud.mode = MBProgressHUDModeCustomView;
                hud.label.text = NSLocalizedString(@"completeHUD_label", @"Complete");
                [hud hideAnimated:YES afterDelay:1.f];
            } else {
                [hud hideAnimated:YES];
            }
        }
        if (completion) {
            completion();
        }
    });
}


#pragma mark - Select Images

-(void)initSelectButtons
{
    self.selectedSections = [NSMutableArray arrayWithCapacity:[self.imagesInSections count]];
    for (NSInteger section = 0; section < [self.imagesInSections count]; section++) {
        [self.selectedSections addObject:[NSNumber numberWithBool:NO]];
    }
}

-(void)updateSelectButtons
{
    // Update status of Select buttons
    // Same number of sections, or fewer if uploaded images removed
    for (NSInteger section = 0; section < [self.imagesInSections count]; section++) {
        [self updateSelectButtonForSection:section];
    }
}

-(void)cancelSelect
{
    // Loop over all sections
    for (NSInteger section = 0; section < [self.localImagesCollection numberOfSections]; section++)
    {
        // Loop over images in section
        for (NSInteger row = 0; row < [self.localImagesCollection numberOfItemsInSection:section]; row++)
        {
            // Deselect image
            LocalImageCollectionViewCell *cell = (LocalImageCollectionViewCell*)[self.localImagesCollection cellForItemAtIndexPath:[NSIndexPath indexPathForRow:row inSection:(section+1)]];
            cell.cellSelected = NO;
        }
        
        // Update state of Select button
        [self.selectedSections replaceObjectAtIndex:section withObject:[NSNumber numberWithBool:NO]];
    }
    
    // Clear list of selected images
    self.selectedImages = [NSMutableArray new];
    
    // Update navigation bar
    [self updateNavBar];
    
    // Update collection
    [self.localImagesCollection reloadData];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer;
{
    // Will interpret touches only in horizontal direction
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *gPR = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint translation = [gPR translationInView:self.localImagesCollection];
        if (fabs(translation.x) > fabs(translation.y))
            return YES;
    }
    return NO;
}

-(void)touchedImages:(UIPanGestureRecognizer *)gestureRecognizer
{
    // To prevent a crash
    if (gestureRecognizer.view == nil) return;
    
    // Select/deselect the cell or scroll the view
    if ((gestureRecognizer.state == UIGestureRecognizerStateBegan) ||
        (gestureRecognizer.state == UIGestureRecognizerStateChanged)) {
        
        // Point and direction
        CGPoint point = [gestureRecognizer locationInView:self.localImagesCollection];
        
        // Get item at touch position
        NSIndexPath *indexPath = [self.localImagesCollection indexPathForItemAtPoint:point];
        if ((indexPath.section == NSNotFound) || (indexPath.row == NSNotFound)) return;
        
        // Get cell at touch position
        UICollectionViewCell *cell = [self.localImagesCollection cellForItemAtIndexPath:indexPath];
        PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
        if ((cell == nil) || (imageAsset == nil)) return;
    
        // Only consider image cells
        if ([cell isKindOfClass:[LocalImageCollectionViewCell class]])
        {
            LocalImageCollectionViewCell *imageCell = (LocalImageCollectionViewCell *)cell;
            
            // Update the selection if not already done
            if (![self.touchedImages containsObject:imageAsset]) {
                
                // Store that the user touched this cell during this gesture
                [self.touchedImages addObject:imageAsset];
                
                // Update the selection state
                if(![self.selectedImages containsObject:imageAsset]) {
                    [self.selectedImages addObject:imageAsset];
                    imageCell.cellSelected = YES;
                } else {
                    imageCell.cellSelected = NO;
                    [self.selectedImages removeObject:imageAsset];
                }
                
                // Update navigation bar
                [self updateNavBar];

                // Refresh cell
                [cell reloadInputViews];

                // Update state of Select button if needed
                [self updateSelectButtonForSection:indexPath.section];
            }
        }
    }

    // Is this the end of the gesture?
    if ([gestureRecognizer state] == UIGestureRecognizerStateEnded) {
        self.touchedImages = [NSMutableArray new];
    }
}

-(void)updateSelectButtonForSection:(NSInteger)section
{
    // Number of images in section
    NSInteger nberOfImages = [[self.imagesInSections objectAtIndex:section] count];
    
    // Count selected images in section
    NSInteger nberOfSelectedImages = 0;
    for (NSInteger item = 0; item < nberOfImages; item++) {
        
        // Retrieve image asset
        PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:section] objectAtIndex:item];
        
        // Is this image selected?
        if ([self.selectedImages containsObject:imageAsset]) {
            nberOfSelectedImages++;
        }
    }
    
    // Update state of Select button only if needed
    if (nberOfImages == nberOfSelectedImages)
    {
        if (![[self.selectedSections objectAtIndex:section] boolValue]) {
            [self.selectedSections replaceObjectAtIndex:section withObject:[NSNumber numberWithBool:YES]];
            [self.localImagesCollection reloadSections:[NSIndexSet indexSetWithIndex:section]];
        }
    }
    else {
        if ([[self.selectedSections objectAtIndex:section] boolValue]) {
            [self.selectedSections replaceObjectAtIndex:section withObject:[NSNumber numberWithBool:NO]];
            [self.localImagesCollection reloadSections:[NSIndexSet indexSetWithIndex:section]];
        }
    }
}

-(void)presentImageUploadView
{
    // Present Image Upload View
    ImageUploadViewController *imageUploadVC = [ImageUploadViewController new];
    imageUploadVC.selectedCategory = self.categoryId;
    imageUploadVC.imagesSelected = self.selectedImages;
    [self.navigationController pushViewController:imageUploadVC animated:YES];

    // Clear list of selected images
    self.selectedImages = [NSMutableArray new];

    // Reset Select buttons
    for (NSInteger section = 0; section < self.imagesInSections.count; section++) {
        [self.selectedSections replaceObjectAtIndex:section withObject:[NSNumber numberWithBool:NO]];
    }
}


#pragma mark - UICollectionView - Headers

-(CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    return CGSizeMake(collectionView.frame.size.width, 40.0);
}

-(UICollectionReusableView*)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if (self.imagesInSections.count > 0)    // Display data in header of section
    {
        // Header with place name
        LocalImagesHeaderReusableView *header = nil;
        if (kind == UICollectionElementKindSectionHeader)
        {
            UINib *nib = [UINib nibWithNibName:@"LocalImagesHeaderReusableView" bundle:nil];
            [collectionView registerNib:nib forCellWithReuseIdentifier:@"LocalImagesHeaderReusableView"];
            header = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"LocalImagesHeaderReusableView" forIndexPath:indexPath];
            
            // Any location ?
            CLLocation *location = [self.locationOfImagesInSections objectAtIndex:indexPath.section];
            [header setupWithImages:[self.imagesInSections objectAtIndex:indexPath.section] andLocation:location inSection:indexPath.section andSelectionMode:[[self.selectedSections objectAtIndex:indexPath.section] boolValue]];
            header.headerDelegate = self;
            
            return header;
        }
    } else {
        // No images!
        if (indexPath.section == 0) {
            // Display "No Images"
            NoImagesHeaderCollectionReusableView *header = nil;
            if(kind == UICollectionElementKindSectionHeader)
            {
                header = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"NoImagesHeaderCollection" forIndexPath:indexPath];
                header.noImagesLabel.textColor = [UIColor piwigoHeaderColor];
                
                return header;
            }
        }
    }

    UICollectionReusableView *view = [[UICollectionReusableView alloc] initWithFrame:CGRectZero];
    return view;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplaySupplementaryView:(UICollectionReusableView *)view forElementKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:UICollectionElementKindSectionHeader]) {
        view.layer.zPosition = 0;       // Below scroll indicator
        view.backgroundColor = [[UIColor piwigoBackgroundColor] colorWithAlphaComponent:0.75];
    }
}


#pragma mark - UICollectionView - Sections

-(NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return (self.imagesInSections.count);
}

-(UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section
{
    return UIEdgeInsetsMake(10, kImageMarginsSpacing, 10, kImageMarginsSpacing);
}

-(CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section;
{
    return (CGFloat)kImageCellSpacing;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section;
{
    return (CGFloat)kImageCellSpacing;
}


#pragma mark - UICollectionView - Rows

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [[self.imagesInSections objectAtIndex:section] count];
}

-(CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    // Calculate the optimum image size
    CGFloat size = (CGFloat)[ImagesCollection imageSizeForView:collectionView andNberOfImagesPerRowInPortrait:self.nberOfImagesPerRow];

    return CGSizeMake(size, size);
}

-(UICollectionViewCell*)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    // Create cell
    LocalImageCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"LocalImageCollectionViewCell" forIndexPath:indexPath];
    PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
    [cell setupWithImageAsset:imageAsset andThumbnailSize:(CGFloat)[ImagesCollection imageSizeForView:collectionView andNberOfImagesPerRowInPortrait:self.nberOfImagesPerRow]];

    // For some unknown reason, the asset resource may be empty
    NSArray *resources = [PHAssetResource assetResourcesForAsset:imageAsset];
    NSString *originalFilename;
    if ([resources count] > 0) {
        originalFilename = ((PHAssetResource*)resources[0]).originalFilename;
    } else {
        // No filename => Build filename from 32 characters of local identifier
        NSRange range = [imageAsset.localIdentifier rangeOfString:@"/"];
        originalFilename = [[imageAsset.localIdentifier substringToIndex:range.location] stringByReplacingOccurrencesOfString:@"-" withString:@""];
        // Filename extension required by Piwigo so that it knows how to deal with it
        if (imageAsset.mediaType == PHAssetMediaTypeImage) {
            // Adopt JPEG photo format by default, will be rechecked
            originalFilename = [originalFilename stringByAppendingPathExtension:@"jpg"];
        } else if (imageAsset.mediaType == PHAssetMediaTypeVideo) {
            // Videos are exported in MP4 format
            originalFilename = [originalFilename stringByAppendingPathExtension:@"mp4"];
        } else if (imageAsset.mediaType == PHAssetMediaTypeAudio) {
            // Arbitrary extension, not managed yet
            originalFilename = [originalFilename stringByAppendingPathExtension:@"m4a"];
        }
    }

    // Add pan gesture recognition
    UIPanGestureRecognizer *imageSeriesRocognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(touchedImages:)];
    imageSeriesRocognizer.minimumNumberOfTouches = 1;
    imageSeriesRocognizer.maximumNumberOfTouches = 1;
    imageSeriesRocognizer.cancelsTouchesInView = NO;
    imageSeriesRocognizer.delegate = self;
    [cell addGestureRecognizer:imageSeriesRocognizer];
    cell.userInteractionEnabled = YES;

    // Cell state
    cell.cellSelected = [self.selectedImages containsObject:imageAsset];
    cell.cellUploading = [[ImageUploadManager sharedInstance].imageNamesUploadQueue containsObject:[originalFilename stringByDeletingPathExtension]];
//    if([self.selectedImages containsObject:imageAsset])
//    {
//        cell.cellSelected = YES;
//    }
//    else if ([[ImageUploadManager sharedInstance].imageNamesUploadQueue containsObject:[originalFilename stringByDeletingPathExtension]])
//    {
//        cell.cellUploading = YES;
//    }
    
    return cell;
}


#pragma mark - UICollectionView Delegate Methods

-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    LocalImageCollectionViewCell *selectedCell = (LocalImageCollectionViewCell*)[collectionView cellForItemAtIndexPath:indexPath];
    
    // Image asset
    PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
    
    // Update cell and selection
    if(selectedCell.cellSelected)
    {    // Deselect the cell
        [self.selectedImages removeObject:imageAsset];
        selectedCell.cellSelected = NO;
    }
    else
    {    // Select the cell
        [self.selectedImages addObject:imageAsset];
        selectedCell.cellSelected = YES;
    }
    
    // Update navigation bar
    [self updateNavBar];

    // Refresh cell
    [selectedCell reloadInputViews];
    
    // Update state of Select button if needed
    [self updateSelectButtonForSection:indexPath.section];
}


#pragma mark - ImageUploadProgress Delegate Methods

-(void)imageProgress:(ImageUpload *)image onCurrent:(NSInteger)current forTotal:(NSInteger)total onChunk:(NSInteger)currentChunk forChunks:(NSInteger)totalChunks iCloudProgress:(CGFloat)iCloudProgress
{
//    NSLog(@"UploadViewController[imageProgress:]");
    NSIndexPath *indexPath = [self indexPathOfImageAsset:image.imageAsset];
    LocalImageCollectionViewCell *cell = (LocalImageCollectionViewCell*)[self.localImagesCollection cellForItemAtIndexPath:indexPath];
    
    CGFloat chunkPercent = 100.0 / totalChunks / 100.0;
    CGFloat onChunkPercent = chunkPercent * (currentChunk - 1);
    CGFloat pieceProgress = (CGFloat)current / total;
    CGFloat uploadProgress = onChunkPercent + (chunkPercent * pieceProgress);
    if(uploadProgress > 1)
    {
        uploadProgress = 1;
    }
    
    cell.cellUploading = YES;
    if (iCloudProgress < 0) {
        cell.progress = uploadProgress;
//        NSLog(@"UploadViewController[ImageProgress]: %.2f", uploadProgress);
    } else {
        cell.progress = (iCloudProgress + uploadProgress) / 2.0;
//        NSLog(@"UploadViewController[ImageProgress]: %.2f", ((iCloudProgress + uploadProgress) / 2.0));
    }
}

-(void)imageUploaded:(ImageUpload *)image placeInQueue:(NSInteger)rank outOf:(NSInteger)totalInQueue withResponse:(NSDictionary *)response
{
//    NSLog(@"UploadViewController[imageUploaded:]");
    NSIndexPath *indexPath = [self indexPathOfImageAsset:image.imageAsset];
    LocalImageCollectionViewCell *cell = (LocalImageCollectionViewCell*)[self.localImagesCollection cellForItemAtIndexPath:indexPath];

    // Image upload ended, deselect cell
    cell.cellUploading = NO;
    cell.cellSelected = NO;
    if ([self.selectedImages containsObject:image.imageAsset]) {
        [self.selectedImages removeObject:image.imageAsset];
    }
    
    // Update list of "Not Uploaded" images
    if (self.removeUploadedImages)
    {
        NSMutableArray *newList = [self.imagesInSections mutableCopy];
        [newList removeObject:image.imageAsset];
        self.imagesInSections = newList;
        
        // Update image cell
        [self.localImagesCollection reloadItemsAtIndexPaths:@[indexPath]];
    }
}


#pragma mark - SortSelectViewController Delegate Methods

//-(void)didSelectSortTypeOf:(kPiwigoSortBy)sortType
//{
//    // Sort images according to new choice
//    self.sortType = sortType;
//}


#pragma mark - Changes occured in the Photo library

- (void)photoLibraryDidChange:(PHChange *)changeInfo {
    // Photos may call this method on a background queue;
    // switch to the main queue to update the UI.
    dispatch_async(dispatch_get_main_queue(), ^{

        // Collect new list of images
        switch (self.sortType) {
            case kPiwigoSortByNewest:
                self.imagesInSections = [[PhotosFetch sharedInstance] getImagesForAssetGroup:self.groupAsset inAscendingOrder:NO];
                break;
                
            case kPiwigoSortByOldest:
                self.imagesInSections = [[PhotosFetch sharedInstance] getImagesForAssetGroup:self.groupAsset inAscendingOrder:YES];
                break;
                
            default:
                break;
        }
    });
}


#pragma mark - LocalImagesHeaderReusableView Delegate Methods

-(void)didSelectImagesOfSection:(NSInteger)section
{
    // Change selection mode of whole section
    BOOL wasSelected = [[self.selectedSections objectAtIndex:section] boolValue];
    if (wasSelected) {
        [self.selectedSections replaceObjectAtIndex:section withObject:[NSNumber numberWithBool:NO]];
    }
    else {
        [self.selectedSections replaceObjectAtIndex:section withObject:[NSNumber numberWithBool:YES]];
    }
    
    // Number of images in section
    NSInteger nberOfImages = [[self.imagesInSections objectAtIndex:section] count];
    
    // Loop over all items in section
    for (NSInteger item = 0; item < nberOfImages; item++) {
        
        // Corresponding image asset
        PHAsset *imageAsset = [[self.imagesInSections objectAtIndex:section] objectAtIndex:item];
        
        // Corresponding collection view cell
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
        LocalImageCollectionViewCell *selectedCell = (LocalImageCollectionViewCell*)[self.localImagesCollection cellForItemAtIndexPath:indexPath];
        
        // Select or deselect cell
        if (wasSelected)
        {    // Deselect the cell
            if ([self.selectedImages containsObject:imageAsset]) {
                [self.selectedImages removeObject:imageAsset];
                selectedCell.cellSelected = NO;
            }
        }
        else
        {    // Select the cell
            if (![self.selectedImages containsObject:imageAsset]) {
                [self.selectedImages addObject:imageAsset];
                selectedCell.cellSelected = YES;
            }
        }
    }

    // Update navigation bar
    [self updateNavBar];
    
    // Update section
    [self updateSelectButtonForSection:section];
}

@end

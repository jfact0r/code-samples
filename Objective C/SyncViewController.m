//
//  SyncViewController.m
//
//  Created by Joel Arnott.
//

#import "SyncViewController.h"
#import "GlobalViewController.h"
#import "SchoolDataRequest.h"
#import "UnitSyncListRequest.h"
#import "UnitGetRequest.h"
#import "UnitUpdateRequest.h"
#import "UnitCreateRequest.h"
#import "SyncMergeConflictViewController.h"
#import "SyncLogViewController.h"

/***************************************************************************************************
 * SyncViewController
 */

#define SYNC_DATA_FILENAME @"syncData"

NSString * const SyncViewControllerDidProgressSyncNotification = @"SyncViewControllerDidProgressSyncNotification";

NSString * const SyncLogTextKey = @"text";
NSString * const SyncLogSuccessKey = @"success";
NSString * const SyncLogErrorKey = @"error";
NSString * const SyncLogUnitKey = @"unit";
NSString * const SyncLogParentKey = @"parent";

@interface SyncViewController ()<UPRequestDelegate, UPDialogViewControllerDelegate>

// Common
@property (strong, nonatomic) NSManagedObjectContext *syncRequestContext;
@property (strong, nonatomic) NSMutableArray *requests;
@property (strong, nonatomic) NSMutableArray *log;
@property (strong, nonatomic) SyncLogViewController *logViewController;
@property (assign, nonatomic) BOOL shownLog;
@property (strong, nonatomic) NSMutableDictionary *requestTimestampMap;
@property (assign, nonatomic) BOOL fullSync;

// School
@property (strong, nonatomic) NSMutableArray *schoolDataList;
@property (assign, nonatomic) NSUInteger totalSchoolData;
@property (assign, nonatomic) BOOL schoolDataFailed;
@property (strong, nonatomic) NSMutableDictionary *dataLogItem;

// Units
@property (strong, nonatomic) NSMutableArray *synchronizingUnits;
@property (strong, nonatomic) NSMutableArray *conflictUnits;
@property (strong, nonatomic) NSMutableArray *deleteUnits;
@property (assign, nonatomic) NSUInteger totalUnitsToSync;
@property (strong, nonatomic) NSMutableDictionary *unitsLogItem;

// Other
@property (strong, nonatomic) NSArray *curriculumItemIds;
@property (strong, nonatomic) NSArray *strategyIds;
@property (strong, nonatomic) NSArray *stage1Ids;
@property (strong, nonatomic) NSArray *tagIds;

@end

@implementation SyncViewController

- (void)setSyncStage:(SyncStage)syncStage
{
    _syncStage = syncStage;
    
    // Post notification
    [[NSNotificationCenter defaultCenter] postNotificationName:SyncViewControllerDidProgressSyncNotification
                                                        object:nil];
}

- (void)startSync
{
    if (_syncStage == SyncStageReady) {
        // Initialise properties
        self.requests = [NSMutableArray array];
        self.school = [Global global].school; // We store our school in case it is changed during the sync
        self.conflictUnits = [NSMutableArray array];
        self.deleteUnits = [NSMutableArray array];
        self.log = [NSMutableArray array];
        self.syncStage = SyncStageUnitList;
        
        // Load our request timestamp map
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *filePath = [documentsDirectory stringByAppendingPathComponent:SYNC_DATA_FILENAME];
        self.requestTimestampMap = [[NSDictionary dictionaryWithContentsOfFile:filePath] mutableCopy];
        if (!_requestTimestampMap) {
            self.requestTimestampMap = [NSMutableDictionary dictionary];
        }
        
        // Create contexts (syncContext holds aggregate changes, syncRequestContext handles individual request changes)
        [Global global].syncContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:
                                       NSPrivateQueueConcurrencyType];
        [Global global].syncContext.parentContext = [Global global].localContext;
        
        self.syncRequestContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:
                                   NSPrivateQueueConcurrencyType];
        _syncRequestContext.parentContext = [Global global].syncContext;
        
        // Setup UI
        _progressView.progress = 0;
        _itemLabel.text = @"";
        _cancelButton.hidden = NO;
        
        // Stop idle timer
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        
        // Show ourselves
        [[Global global].globalViewController showSyncView];
        
        // Continue sync
        [self continueSync];
    }
}

- (void)startQuickSync
{
    _fullSync = NO;
    [self startSync];
}

- (void)startFullSync
{
    _fullSync = YES;
    [self startSync];
}

- (void)stopSync
{
    // Reset properties
    
    // Common
    self.syncRequestContext = nil;
    self.requests = nil;
    self.log = nil;
    self.logViewController = nil;
    self.shownLog = NO;
    self.requestTimestampMap = nil;
    self.fullSync = NO;
    
    // School
    self.schoolDataList = nil;
    self.totalSchoolData = 0;
    self.schoolDataFailed = NO;
    self.dataLogItem = nil;
    
    // Units
    self.synchronizingUnits = nil;
    self.conflictUnits = nil;
    self.deleteUnits = nil;
    self.totalUnitsToSync = 0;
    self.unitsLogItem = nil;
    
    // Other
    self.curriculumItemIds = nil;
    self.strategyIds = nil;
    self.stage1Ids = nil;
    
    // Discard context
    [Global global].syncContext = nil;
    
    // Reset UI
    _cancelIcon.hidden = NO;
    [_cancelIndicator stopAnimating];
    
    // Get ready for next sync
    self.syncStage = SyncStageReady;
    
    // Start idle timer
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    
    // Hide ourselves
    [[Global global].globalViewController hideSyncView];
}

- (void)continueSync
{
    if (_syncStage == SyncStageUnitList) {
        // Get list of units
        [self continueUnitsSync];
    } if (_syncStage == SyncStageUnits) {
        // Get units
        [self continueUnitsSync];
    } else if (_syncStage == SyncStageDataList) {
        // Get list of data
        [self continueDataSync];
    } else if (_syncStage == SyncStageData) {
        // Get data
        [self continueDataSync];
    } else if (_syncStage == SyncStageSave) {
        // Show log of sync and ask user if they want to save or rollback
        [self showLog];
    } else if (_syncStage == SyncStageDone) {
        // Done!
        [self stopSync];
    }
}

- (void)continueUnitsSync
{
    if (_syncStage == SyncStageUnitList) {
        // Unit List
        if (!_unitsLogItem) {
            // Build log item and add to log
            self.unitsLogItem = [@{ SyncLogTextKey : @"Units" } mutableCopy];
            [_log addObject:_unitsLogItem];
            
            // Request
            UnitSyncListRequest *request = [UnitSyncListRequest requestWithDelegate:self];
            
            request.managedObjectContext = _syncRequestContext;
            request.silentErrorCodeMask = ~0;
            request.school = _school;
            request.userInfo = @{ @"logItem" : _unitsLogItem };
            
            [_requests addObject:request];
            [request perform];
        }
    } else if (_syncStage == SyncStageUnits) {
        // Units
        NSManagedObjectID *schoolObjectID = _school.objectID;
        
        [[Global global].syncContext performBlock:^{
            School *school = (id)[[Global global].syncContext objectWithID:schoolObjectID];
            
            if ([_synchronizingUnits count] > 0) {
                // Still have units to sync - handle next unit
                
                // Get unit, its name and object ID
                Unit *unit = [_synchronizingUnits objectAtIndex:0];
                [_synchronizingUnits removeObjectAtIndex:0];
                
                NSString *name = [unit nameString];
                NSManagedObjectID *unitObjectID = unit.objectID;
                
                // Mark unit as requiring sync down if it was remotely modified after our last sync
                if (unit.remoteLastModified &&
                    [school.lastUnitSync compare:unit.remoteLastModified] == NSOrderedAscending){
                    NSLog(@"[Sync] Syncing remotely modified unit: %@ > %@", unit.remoteLastModified, school.lastUnitSync);
                    unit.requiresSyncDown = @YES;
                }
                
                // Handle different types of synchronization
                if ([unit.requiresSyncUp boolValue] && [unit.requiresSyncDown boolValue]) {
                    // Conflict
                    DDLogInfo(@"[Sync] Conflicting unit: %@ [%@] (%@) (%@)", name, unit.upid, unit.remoteLastModified,
                              school.lastUnitSync);
                    
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        Unit *unit = (id)[[Global global].localContext objectWithID:unitObjectID];
                        
                        // Add to our list of conflicting units
                        [_conflictUnits addObject:unit];
                        
                        // Build log item and add to log
                        [_log addObject:[@{  SyncLogTextKey : name,
                                             SyncLogErrorKey : [UPRequestError errorWithCode:UPRequestErrorCodeConflict
                                                                                maskingError:nil],
                                             SyncLogUnitKey : unit,
                                             SyncLogParentKey : _unitsLogItem } mutableCopy]];
                        
                        [self continueSync];
                    });
                } else if ([unit.requiresSyncUp boolValue] && ![unit.upid intValue]) {
                    // Create
                    DDLogInfo(@"[Sync] Creating unit: %@ [%@]", name, unit.upid);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        Unit *unit = (id)[[Global global].localContext objectWithID:unitObjectID];
                        
                        // Build log item and add to log
                        NSDictionary *logItem = [@{ SyncLogTextKey : name,
                                                    SyncLogParentKey : _unitsLogItem } mutableCopy];
                        [_log addObject:logItem];
                        
                        // Build request
                        UnitCreateRequest *request = [UnitCreateRequest requestWithDelegate:self];
                        
                        request.managedObjectContext = _syncRequestContext;
                        request.silentErrorCodeMask = ~0;
                        request.school = _school;
                        request.unit = unit;
                        request.userInfo = @{ @"logItem" : logItem };
                        
                        [_requests addObject:request];
                        [request perform];
                        
                        [self performSelector:@selector(continueSync) withObject:nil afterDelay:3];
                    });
                } else if ([unit.requiresSyncUp boolValue]) {
                    // Update
                    DDLogInfo(@"[Sync] Updating unit: %@ [%@]", name, unit.upid);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        Unit *unit = (id)[[Global global].localContext objectWithID:unitObjectID];
                        
                        // Build log item and add to log
                        NSDictionary *logItem = [@{ SyncLogTextKey : name,
                                                    SyncLogParentKey : _unitsLogItem } mutableCopy];
                        [_log addObject:logItem];
                        
                        // Build request
                        UnitUpdateRequest *request = [UnitUpdateRequest requestWithDelegate:self];
                        request.managedObjectContext = _syncRequestContext;
                        request.silentErrorCodeMask = ~0;
                        request.school = _school;
                        request.unit = unit;
                        request.userInfo = @{ @"logItem" : logItem };
                        
                        [_requests addObject:request];
                        [request perform];
                        
                        [self performSelector:@selector(continueSync) withObject:nil afterDelay:3];
                    });
                } else if (![unit isRemoteActive]) {
                    // Delete (as unit has been deleted remotely but not locally)
                    DDLogInfo(@"[Sync] Marking remotely deleted unit for deletion: %@ [%@]", name, unit.upid);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Check if it exists locally
                        BOOL exists = !![[Global global].localContext existingObjectWithID:unitObjectID error:nil];
                        
                        [[Global global].syncContext performBlock:^{
                            // Update log only if the unit hasn't been deleted locally or if it's a new unit
                            if (exists || ![unit.upid intValue]) {
                                [_log addObject:[@{ SyncLogTextKey : name,
                                                    SyncLogSuccessKey : @"Deleted",
                                                    SyncLogParentKey : _unitsLogItem } mutableCopy]];
                            }
                            
                            // Mark unit for deletion
                            [_deleteUnits addObject:unit];
                            
                            // Don't need to perform delete now - we'll do it at the end
                            dispatch_async(dispatch_get_main_queue(), ^{
                                // Continue
                                [self continueSync];
                            });
                        }];
                    });
                } else {
                    // Get
                    DDLogInfo(@"[Sync] Downloading unit: %@ [%@]", name, unit.upid);
                    
                    // Build log item and add to log
                    NSDictionary *logItem = [@{ SyncLogTextKey : name, SyncLogParentKey : _unitsLogItem } mutableCopy];
                    [_log addObject:logItem];
                    
                    // Build request
                    UnitGetRequest *request = [UnitGetRequest requestWithDelegate:self];
                    
                    request.managedObjectContext = _syncRequestContext;
                    request.silentErrorCodeMask = ~0;
                    request.school = _school;
                    request.unit = unit;
                    request.userInfo = @{ @"logItem" : logItem };
                    
                    [_requests addObject:request];
                    [request perform];
                    
                    // Move on to next unit after a slight delay
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self performSelector:@selector(continueSync) withObject:nil afterDelay:0.5];
                    });
                }
            } else if ([_requests count] == 0) {
                // Synchronized all units
                
                // Update UI
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_progressView setProgress:0.5 animated:YES];
                });
                
                // Update log to show how many units we synchronized
                _unitsLogItem[SyncLogTextKey] = [_unitsLogItem[SyncLogTextKey] stringByAppendingFormat:@" (%lu changes)",
                                                 (unsigned long)_totalUnitsToSync];
                
                // Move to next stage of sync
                self.syncStage = SyncStageDataList;
                [self continueSync];
            }
        }];
    }
}

- (void)continueDataSync
{
    if (_syncStage == SyncStageDataList) {
        // Data List
        if (!_dataLogItem) {
            // Get our list of data
            
            // Build log item and add to log
            self.dataLogItem = [@{ SyncLogTextKey : @"School Data" } mutableCopy];
            [_log addObject:_dataLogItem];
            
            // Build request
            SchoolDataRequest *request = [SchoolDataRequest requestWithDelegate:self];
            
            request.managedObjectContext = _syncRequestContext;
            request.silentErrorCodeMask = ~0;
            request.school = _school;
            request.userInfo = @{ @"logItem" : _dataLogItem };
            
            [_requests addObject:request];
            [request perform];
        }
    } else if (_syncStage == SyncStageData) {
        // Data
        if ([_schoolDataList count] > 0) {
            // Still have data to download
            
            // Pop next data info from our list
            GroupData *data = _schoolDataList[0];
            [_schoolDataList removeObjectAtIndex:0];
            
            // Build log item and add to log
            NSDictionary *logItem = [@{ SyncLogTextKey : data.name, SyncLogParentKey : _dataLogItem } mutableCopy];
            [_log addObject:logItem];
            
            // Get timestamp
            NSDate *date = _fullSync ? nil : _requestTimestampMap[data.path];
            if (!date) {
                date = [NSDate dateWithTimeIntervalSince1970:0];
            }
            
            // Build path
            NSString *path = data.path;
            
            NSDateFormatter *fmtr = [[NSDateFormatter alloc] init];
            fmtr.dateFormat = @"yyyyMMddHHmmssZZZ";
            
            path = [path stringByAppendingString:@";timestamp="];
            path = [path stringByAppendingString:[fmtr stringFromDate:date]];
            
            // Build request
            UPRequest *request = [UPRequest requestWithDelegate:self];
            
            request.managedObjectContext = _syncRequestContext;
            request.silentErrorCodeMask = ~0;
            request.path = path;
            request.userInfo = @{ @"logItem" : logItem, @"data" : data };
            
            [_requests addObject:request];
            [request perform];
            
            // Only continue if our next data has the same order
            [self continueSync];
        } else if ([_requests count] == 0) {
            // Finished getting all data in our list
            
            // Update UI
            [_progressView setProgress:1.0 animated:YES];
            
            // Update log to show how many data items we synchronized
            _dataLogItem[SyncLogTextKey] = [_dataLogItem[SyncLogTextKey] stringByAppendingFormat:@" (%lu changes)",
                                            (unsigned long)_totalSchoolData];
            
            NSManagedObjectID *objectID = _school.objectID;
            [[Global global].syncContext performBlock:^{
                // Update our data sync timestamp if we successfully synchronized all school data
                if (!_schoolDataFailed && _totalSchoolData > 0) {
                    School *school = (id)[[Global global].syncContext objectWithID:objectID];
                    school.lastDataSync = [NSDate date];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Move to next stage of sync
                    self.syncStage = SyncStageSave;
                    [self continueSync];
                });
            }];
        }
    }
}

- (void)cancelSync
{
    // Stop sync
    [self stopSync];
}

- (IBAction)cancelButtonTapped:(id)sender
{
    // Prevent multiple taps
    if (!_cancelIcon.hidden) {
        // Setup UI
        _cancelIcon.hidden = YES;
        [_cancelIndicator startAnimating];
        
        // Cancel
        [self cancelSync];
    }
}

- (BOOL)isSynchronizing
{
    return _syncStage != SyncStageReady;
}

- (void)showLog
{
    if (!_shownLog) {
        _shownLog = YES;
        
        // Reorder our log to move conflicting unit log items to the top
        NSMutableArray *log = [NSMutableArray array];
        for (NSMutableDictionary *logItem in _log) {
            if (logItem[SyncLogUnitKey]) {
                // Found conflicting unit log item - move to below our units log item
                [log insertObject:logItem atIndex:[log indexOfObject:_unitsLogItem] + 1];
                
                // Mark our units log item as having an error if we have conflicting units
                _unitsLogItem[SyncLogErrorKey] = [UPRequestError errorWithCode:UPRequestErrorCodeConflict
                                                                  maskingError:nil];
            } else {
                [log addObject:logItem];
            }
        }
        self.log = log;
        
        // Show the log
        [self performSegueWithIdentifier:@"showLog" sender:nil];
    }
}

/***************************************************************************************************
 * UPRequestDelegate
 */

- (void)request:(UPRequest *)request didFailWithError:(NSError *)error
{
    // Update our request's log item
    request.userInfo[@"logItem"][SyncLogErrorKey] = error;
    
    // Remove from requests
    [_requests removeObject:request];
    
    // Handle different sync stages
    if (_syncStage == SyncStageUnitList) {
        // Unit List
        
        // Move to next stage
        self.syncStage = SyncStageDataList;
    } else if (_syncStage == SyncStageDataList) {
        // Data List
        
        // Move to next stage
        self.syncStage = SyncStageSave;
    } else if (_syncStage == SyncStageData) {
        // Data
        self.schoolDataFailed = YES;
    }
    
    // Continue sync
    [self continueSync];
}

- (void)request:(UPRequest *)request didLoadObjectIDs:(NSArray *)objectIDs inContext:(NSManagedObjectContext *)ctx
{
    // Remove from requests
    [_requests removeObject:request];
    
    // Save request context up to our sync context
    [ctx performBlock:^{
        [ctx save];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Handle different sync stages
            if (_syncStage == SyncStageDataList) {
                // Data List
                self.schoolDataList = [objectIDs mutableCopy];
                _totalSchoolData = [_schoolDataList count];
                
                // Move to next stage
                self.syncStage = SyncStageData;
                [self continueSync];
            } else if (_syncStage == SyncStageData) {
                // Data
                
                // Check data
                if ([objectIDs count]) {
                    id object = objectIDs[0];
                    
                    if ([object isKindOfClass:[GroupDataCurriculumItemIds class]]) {
                        self.curriculumItemIds = [object ids];
                    } else if ([object isKindOfClass:[GroupDataStrategyIds class]]) {
                        self.strategyIds = [object ids];
                    } else if ([object isKindOfClass:[GroupDataStage1Ids class]]) {
                        self.stage1Ids = [object ids];
                    } else if ([object isKindOfClass:[GroupDataTagIds class]]) {
                        self.tagIds = [object ids];
                    }
                }
                
                // Get data
                GroupData *data = request.userInfo[@"data"];
                
                
                // Update timestamp
                _requestTimestampMap[data.path] = [NSDate date];
                
                // Update UI
                [_progressView setProgress:(1 - [_requests count]/(float)_totalSchoolData) * 0.5 + 0.5 animated:YES];
                _itemLabel.text = data.name;
                
                // Only continue if there are no other outstanding requests
                [self continueSync];
            } else if (_syncStage == SyncStageUnitList) {
                // Unit List
                
                NSManagedObjectID *objectID = _school.objectID;
                [[Global global].syncContext performBlock:^{
                    School *school = (id)[[Global global].syncContext objectWithID:objectID];
                    
                    // Remove/restore access to units
                    for (Unit *unit in school.units) {
                        if ([unit.upid intValue] > 0) {
                            BOOL inObjectIDs = [objectIDs containsObject:unit.objectID];
                            
                            
                            if ([unit.active boolValue] && !inObjectIDs) {
                                DDLogInfo(@"[Sync] Removing access to unit: %@ [%@]", [unit nameString], unit.upid);
                                
                                NSDictionary *logItem = [@{ SyncLogTextKey : [unit nameString],
                                                            SyncLogSuccessKey : @"Removed Access",
                                                            SyncLogParentKey : _unitsLogItem } mutableCopy];
                                [_log addObject:logItem];
                                
                                unit.active = @NO;
                                unit.requiresSyncUp = @NO;
                            } else if (![unit.active boolValue] && ![unit.requiresSyncUp boolValue] && inObjectIDs) {
                                DDLogInfo(@"[Sync] Restoring access to unit: %@ [%@]", [unit nameString], unit.upid);
                                
                                NSDictionary *logItem = [@{ SyncLogTextKey : [unit nameString],
                                                            SyncLogSuccessKey : @"Restored Access",
                                                            SyncLogParentKey : _unitsLogItem } mutableCopy];
                                [_log addObject:logItem];
                                
                                unit.active = @YES;
                            }
                        }
                    }
                    
                    // Store units that require synchronizing
                    self.synchronizingUnits = [[school unitsRequiringSync] mutableCopy];
                    _totalUnitsToSync = [_synchronizingUnits count];
                    
                    // Get local copies of units (if possible)
                    NSArray *unitObjectIDs = [_synchronizingUnits valueForKey:@"objectID"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.units = [NSMutableArray array];
                        for (NSManagedObjectID *objectID in unitObjectIDs) {
                            Unit *unit = (id)[[Global global].localContext existingObjectWithID:objectID error:nil];
                            if (unit) {
                                [_units addObject:unit];
                            }
                        }
                        
                        // Move to next sync stage
                        self.syncStage = SyncStageUnits;
                        [self continueSync];
                    });
                }];
            } else if (_syncStage == SyncStageUnits) {
                // Unit
                
                // Handle sync'd unit
                NSManagedObjectID *oldObjectID = [[(id)request unit] objectID];
                NSManagedObjectID *newObjectID = [objectIDs lastObject];
                
                [[Global global].syncContext performBlock:^{
                    // Get our new unit and old unit
                    Unit *newUnit = (id)[[Global global].syncContext objectWithID:newObjectID];
                    Unit *oldUnit = (id)[[Global global].syncContext objectWithID:oldObjectID];
                    
                    // Store new name
                    NSString *name = [newUnit nameString];
                    
                    // Delete old unit if it is not same as new unit
                    if (newUnit != oldUnit) {
                        DDLogInfo(@"[Sync] Marking redundant copy of unit for deletion: %@ [%@]", name, newUnit.upid);
                        [_deleteUnits addObject:oldUnit];
                    }
                    
                    // Mark as not requiring a sync anymore (including pedigree units)
                    Unit *temp = newUnit;
                    for (int i = 0; i < 10 && temp; i++) {
                        temp.requiresSyncUp = @NO;
                        temp.requiresSyncDown = @NO;
                        
                        temp = temp.pedigreeUnit;
                    }
                    
                    // Handle inactive units and update our log depending on our action
                    if (![newUnit isActive]) {
                        // Delete (because the unit has been deleted remotely)
                        [[Global global].syncContext deleteObject:newUnit];
                        request.userInfo[@"logItem"][SyncLogSuccessKey] = @"Deleted";
                    } else if ([request isKindOfClass:[UnitGetRequest class]]) {
                        // Downloaded
                        request.userInfo[@"logItem"][SyncLogSuccessKey] = @"Downloaded";
                    } else if ([request isKindOfClass:[UnitUpdateRequest class]]) {
                        // Uploaded
                        request.userInfo[@"logItem"][SyncLogSuccessKey] = @"Uploaded";
                    } else if ([request isKindOfClass:[UnitCreateRequest class]]) {
                        // Created
                        request.userInfo[@"logItem"][SyncLogSuccessKey] = @"Created";
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Update UI
                        [_progressView setProgress:(1 - [_requests count]/(float)_totalUnitsToSync) * 0.5 animated:YES];
                        _itemLabel.text = name;
                        
                        // Continue
                        [self continueSync];
                    });
                }];
            }
        });
    }];
}

/***************************************************************************************************
 * UIViewController
 */

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Store ourselves on our global singleton
    [Global global].syncViewController = self;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    [super prepareForSegue:segue sender:sender];
    
    if ([segue.identifier isEqualToString:@"showLog"]) {
        // Showing log of sync and asking if user wants to save or rollback
        SyncLogViewController *vc = (SyncLogViewController *)segue.destinationViewController;
        
        // Pass on log
        vc.delegate = self;
        vc.log = _log;
        vc.school = _school;
        
        // Store reference
        self.logViewController = vc;
    }
}

/***************************************************************************************************
 * UPDialogViewControllerDelegate
 */

- (void)dialogDidCancel:(UPDialogViewController *)dialog
{
    // Rollback!
    
    // Just call our cancel button handler - it will handle rolling back
    [self cancelButtonTapped:self];
}

- (void)dialogDidComplete:(UPDialogViewController *)dialog
{
    // Save!
    
    // Start loading animation
    [[Global global].globalViewController.view startLoadingAnimationWithFade:YES andText:@"Finishing Sync"];
    
    // Start save
    NSManagedObjectID *objectID = _school.objectID;
    __block NSManagedObjectContext *ctx = [Global global].syncContext;
    
    [ctx performBlock:^{
        // Update our last sync date
        School *school = (id)[ctx objectWithID:objectID];
        [school setLastUnitSync:[NSDate date]];
        
        // Delete any units that were marked for deletion
        for (Unit *unit in _deleteUnits) {
            DDLogInfo(@"[Sync] Deleting unit that was marked for deletion: %@ [%@]", [unit nameString], unit.upid);
            [ctx deleteObject:unit];
        }
        
        // Save
        [ctx save];
        [ctx reset];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Discard sync context
            [Global global].syncContext = nil;
            ctx = nil;
            
            // Save local context
            [[Global global].localContext save];
            
            // Associate data in new context
            NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] initWithConcurrencyType:
                                           NSPrivateQueueConcurrencyType];
            ctx.parentContext = [Global global].localContext;
            
            [ctx performBlock:^{
                School *school = (id)[ctx objectWithID:objectID];
                
                // Curriculum Items
                if ([_curriculumItemIds count]) {
                    DDLogInfo(@"[Sync] Curriculum Association Started");
                    NSMutableSet *schoolCurriculumItems = [school.schoolCurriculumItems mutableCopy];
                    NSPredicate *p;
                    
                    // Get items
                    p = [NSPredicate predicateWithFormat:@"upid IN %@", _curriculumItemIds];
                    NSArray *items = [CurriculumItem findAllWithPredicate:p inContext:ctx];
                    
                    // Get existing items
                    p = [NSPredicate predicateWithFormat:@"ANY schoolCurriculumItems IN %@", schoolCurriculumItems];
                    NSArray *existingItems = [CurriculumItem findAllWithPredicate:p inContext:ctx];
                    
                    // Add items
                    NSMutableArray *addItems = [items mutableCopy];
                    [addItems removeObjectsInArray:existingItems];
                    for (CurriculumItem *item in addItems) {
                        SchoolCurriculumItem *schoolCurriculumItem = [SchoolCurriculumItem createInContext:ctx];
                        
                        schoolCurriculumItem.curriculumItem = item;
                        schoolCurriculumItem.active = @YES;
                        [schoolCurriculumItems addObject:schoolCurriculumItem];
                    }
                    
                    // Remove items
                    NSMutableArray *removeItems = [existingItems mutableCopy];
                    [removeItems removeObjectsInArray:items];
                    p = [NSPredicate predicateWithFormat:@"school = %@ AND (curriculumItem IN %@)",
                         school,
                         removeItems];
                    NSArray *removeSchoolItems = [SchoolCurriculumItem findAllWithPredicate:p inContext:ctx];
                    for (SchoolCurriculumItem *schoolItem in removeSchoolItems) {
                        [schoolItem deleteInContext:ctx];
                    }
                    
                    school.schoolCurriculumItems = schoolCurriculumItems;
                    DDLogInfo(@"[Sync] Curriculum Association Finished (-%lu, +%lu)",
                              (unsigned long)[removeSchoolItems count], (unsigned long)[addItems count]);
                    
                    // Save
                    [ctx save];
                }
                
                // Strategies
                if ([_strategyIds count]) {
                    DDLogInfo(@"[Sync] Goal Association Started");
                    NSMutableSet *schoolStrategies = [school.schoolStrategies mutableCopy];
                    NSPredicate *p;
                    
                    // Get items
                    p = [NSPredicate predicateWithFormat:@"upid IN %@", _strategyIds];
                    NSArray *items = [Strategy findAllWithPredicate:p inContext:ctx];
                    
                    // Get existing items
                    p = [NSPredicate predicateWithFormat:@"ANY schoolStrategies IN %@", schoolStrategies];
                    NSArray *existingItems = [Strategy findAllWithPredicate:p inContext:ctx];
                    
                    // Add items
                    NSMutableArray *addItems = [items mutableCopy];
                    [addItems removeObjectsInArray:existingItems];
                    for (Strategy *item in addItems) {
                        SchoolStrategy *schoolStrategy = [SchoolStrategy createInContext:ctx];
                        
                        schoolStrategy.strategy = item;
                        schoolStrategy.active = @YES;
                        [schoolStrategies addObject:schoolStrategy];
                    }
                    
                    // Remove items
                    NSMutableArray *removeItems = [existingItems mutableCopy];
                    [removeItems removeObjectsInArray:items];
                    p = [NSPredicate predicateWithFormat:@"school = %@ AND (strategy IN %@)",
                         school,
                         removeItems];
                    NSArray *removeSchoolItems = [SchoolStrategy findAllWithPredicate:p inContext:ctx];
                    for (SchoolStrategy *schoolItem in removeSchoolItems) {
                        [schoolItem deleteInContext:ctx];
                    }
                    
                    school.schoolStrategies = schoolStrategies;
                    DDLogInfo(@"[Sync] Goal Association Finished (-%lu, +%lu)",
                              (unsigned long)[removeSchoolItems count], (unsigned long)[addItems count]);
                    
                    // Save
                    [ctx save];
                }
                
                // Stage 1s
                if ([_stage1Ids count]) {
                    DDLogInfo(@"[Sync] Stage1 Association Started");
                    NSMutableSet *schoolStage1s = [school.schoolStage1s mutableCopy];
                    NSPredicate *p;
                    
                    // Get items
                    p = [NSPredicate predicateWithFormat:@"upid IN %@", _stage1Ids];
                    NSArray *items = [Stage1 findAllWithPredicate:p inContext:ctx];
                    
                    // Get existing items
                    p = [NSPredicate predicateWithFormat:@"ANY schoolStage1s IN %@", schoolStage1s];
                    NSArray *existingItems = [Stage1 findAllWithPredicate:p inContext:ctx];
                    
                    // Add items
                    NSMutableArray *addItems = [items mutableCopy];
                    [addItems removeObjectsInArray:existingItems];
                    for (Stage1 *item in addItems) {
                        SchoolStage1 *schoolStage1 = [SchoolStage1 createInContext:ctx];
                        
                        schoolStage1.stage1 = item;
                        schoolStage1.active = @YES;
                        [schoolStage1s addObject:schoolStage1];
                    }
                    
                    // Remove items
                    NSMutableArray *removeItems = [existingItems mutableCopy];
                    [removeItems removeObjectsInArray:items];
                    p = [NSPredicate predicateWithFormat:@"school = %@ AND (stage1 IN %@)",
                         school,
                         removeItems];
                    NSArray *removeSchoolItems = [SchoolStage1 findAllWithPredicate:p inContext:ctx];
                    for (SchoolStage1 *schoolItem in removeSchoolItems) {
                        [schoolItem deleteInContext:ctx];
                    }
                    
                    school.schoolStage1s = schoolStage1s;
                    DDLogInfo(@"[Sync] Stage1 Association Finished (-%lu, +%lu)",
                              (unsigned long)[removeSchoolItems count], (unsigned long)[addItems count]);
                    
                    // Save
                    [ctx save];
                }
                
                // Tags
                if ([_tagIds count]) {
                    DDLogInfo(@"[Sync] Tag Association Started");
                    NSMutableSet *schoolTags = [school.schoolTags mutableCopy];
                    NSPredicate *p;
                    
                    // Get items
                    p = [NSPredicate predicateWithFormat:@"upid IN %@", _tagIds];
                    NSArray *items = [Tag findAllWithPredicate:p inContext:ctx];
                    
                    // Get existing items
                    p = [NSPredicate predicateWithFormat:@"ANY schoolTags IN %@", schoolTags];
                    NSArray *existingItems = [Tag findAllWithPredicate:p inContext:ctx];
                    
                    // Add items
                    NSMutableArray *addItems = [items mutableCopy];
                    [addItems removeObjectsInArray:existingItems];
                    for (Tag *item in addItems) {
                        SchoolTag *schoolTag = [SchoolTag createInContext:ctx];
                        
                        schoolTag.tag = item;
                        schoolTag.active = @YES;
                        [schoolTags addObject:schoolTag];
                    }
                    
                    // Remove items
                    NSMutableArray *removeItems = [existingItems mutableCopy];
                    [removeItems removeObjectsInArray:items];
                    p = [NSPredicate predicateWithFormat:@"school = %@ AND (tag IN %@)",
                         school,
                         removeItems];
                    NSArray *removeSchoolItems = [SchoolTag findAllWithPredicate:p inContext:ctx];
                    for (SchoolTag *schoolItem in removeSchoolItems) {
                        [schoolItem deleteInContext:ctx];
                    }
                    
                    school.schoolTags = schoolTags;
                    DDLogInfo(@"[Sync] Tag Association Finished (-%lu, +%lu)",
                              (unsigned long)[removeSchoolItems count], (unsigned long)[addItems count]);
                    
                    // Save
                    [ctx save];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Save local context
                    [[Global global].localContext save];
                    
                    // Save our request timestamp map
                    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                    NSString *documentsDirectory = [paths objectAtIndex:0];
                    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:SYNC_DATA_FILENAME];
                    [_requestTimestampMap writeToFile:filePath atomically:YES];
                    
                    // Must exclude app files from iCloud backup!
                    [[NSURL fileURLWithPath:filePath] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
                    
                    // Stop loading animation
                    [[Global global].globalViewController.view stopLoadingAnimation];
                    
                    // Finished
                    self.syncStage = SyncStageDone;
                    [self continueSync];
                });
            }];
        });
    }];
}

@end

//
//  InitViewController.m
//
//  Created by Joel Arnott.
//

#import "InitViewController.h"
#import <CocoaLumberjack/DDASLLogger.h>
#import <CocoaLumberjack/DDTTYLogger.h>
#import <CocoaLumberjack/DDFileLogger.h>
#import <sqlite3.h>
#import <RMStore/RMStore.h>
#import <RMStore/RMAppReceipt.h>
#import <RMStore/RMStoreAppReceiptVerificator.h>
#import "NSData+Gzip.h"

/***************************************************************************************************
 * InitViewController
 */

@interface InitViewController ()

@property (assign, nonatomic) BOOL initialising;

@property (assign, nonatomic) int migrationTotal;
@property (assign, nonatomic) int migrationCount;

@property (strong, nonatomic) RMStoreAppReceiptVerificator *receiptVerificator;

@end

@implementation InitViewController

/**
 * Replaces our persistent store if we have a replacement URL.
 */
- (void)replaceStoreIfNeeded
{
    NSError *error;
    
    // Check if we have a replacement URL
    NSURL *repUrl = [Global global].replacementStoreURL;
    if (repUrl) {
        // Get documents directory
        NSURL *docUrl = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                inDomains:NSUserDomainMask] lastObject];
        
        // Get source URL
        NSURL *srcUrl = [docUrl URLByAppendingPathComponent:STORE_NAME];
        if (![[NSFileManager defaultManager] fileExistsAtPath:[srcUrl path]]) {
            // No source URL - copy
            [[NSFileManager defaultManager] copyItemAtURL:repUrl toURL:srcUrl error:&error];
        } else {
            // Have source URL - create temp file and use it to replace source
            NSURL *tmpUrl = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:STORE_NAME]];

            if ([[NSFileManager defaultManager] copyItemAtURL:repUrl toURL:tmpUrl error:&error]) {
                [[NSFileManager defaultManager] replaceItemAtURL:srcUrl
                                                   withItemAtURL:tmpUrl
                                                  backupItemName:nil
                                                         options:NSFileManagerItemReplacementUsingNewMetadataOnly
                                                resultingItemURL:nil
                                                           error:&error];
            }
        }
        
        // Handle gzip
        NSData *data = [[NSData dataWithContentsOfURL:srcUrl] gzipInflate];
        [data writeToURL:srcUrl atomically:NO];
        
        // Check for error
        if (error) {
            DDLogInfo(@"[Replace] Error restoring replacement store: %@", error);
            return;
        }
        
        [Global global].replacementStoreURL = nil;
    }
}

/**
 * Migrates our persistent store if our managed object model version has changed. Handles migrating sequentially through
 * versions. Returns success.
 */
- (BOOL)migrateStoreIfNeeded
{
    NSError *error = nil;
    
    // Map model version identifiers to their associated destination model name and mapping model name for migration
    NSDictionary *migrationMap = @{ @"1.0" : @{ @"model" : @"MainModel_v1_4", @"mapping" : @"MainModel_v1_0_v1_4" },
                                    @"1.4" : @{ @"model" : @"MainModel_v1_5", @"mapping" : @"MainModel_v1_4_v1_5" },
                                    @"1.5" : @{ @"model" : @"MainModel_v1_6", @"mapping" : @"MainModel_v1_5_v1_6" },
                                    @"1.6" : @{ @"model" : @"MainModel_v1_7", @"mapping" : @"MainModel_v1_6_v1_7" },
                                    @"1.7" : @{ @"model" : @"MainModel_v2_0", @"mapping" : @"MainModel_v1_7_v2_0" },
                                    @"2.0" : @{ @"model" : @"MainModel_v2_2", @"mapping" : @"MainModel_v2_0_v2_2" },
                                    @"2.2" : @{ @"model" : @"MainModel_v3_1", @"mapping" : @"MainModel_v2_2_v3_1" },
                                    @"3.1" : @{ @"model" : @"MainModel_v3_2", @"mapping" : @"MainModel_v3_1_v3_2" } };
    
    // Get documents directory
    NSURL *docUrl = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                            inDomains:NSUserDomainMask] lastObject];
    
    // Get URLs
    NSURL *srcUrl = [docUrl URLByAppendingPathComponent:STORE_NAME];
    NSURL *bckUrl = [docUrl URLByAppendingPathComponent:STORE_BACKUP_NAME];
    NSURL *tmpUrl = [docUrl URLByAppendingPathComponent:STORE_TEMP_NAME];
    
    // Get source store
    if (![[NSFileManager defaultManager] fileExistsAtPath:[srcUrl path]]) {
        // No source store
        return YES;
    }
    
    // Handle WAL file
    NSURL *walUrl = [[srcUrl URLByDeletingPathExtension] URLByAppendingPathExtension:@"sqlite-wal"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[walUrl path]]) {
        sqlite3 *db;
        
        DDLogInfo(@"[SQL] Opening database");
        if (sqlite3_open([[srcUrl path] UTF8String], &db) == SQLITE_OK) {
            sqlite3_stmt *stmt;
            
            DDLogInfo(@"[SQL] Performing WAL checkpoint");
            if (sqlite3_prepare_v2(db, "PRAGMA wal_checkpoint(FULL);", -1, &stmt, NULL) == SQLITE_OK) {
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    int col = sqlite3_column_int(stmt, 0);
                    DDLogInfo(@"[SQL] WAL checkpoint result: %d", col);
                }
            } else {
                DDLogInfo(@"[SQL] Error performing WAL checkpoint: %s", sqlite3_errmsg(db));
            }
            sqlite3_finalize(stmt);
            sqlite3_close(db);
        } else {
            DDLogInfo(@"[SQL] Error opening database: %s", sqlite3_errmsg(db));
        }
    }
    
    // Get source store metadata
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                                                        URL:srcUrl
                                                                                      error:&error];
    if (error) {
        // Error getting our store metadata
        DDLogInfo(@"Error getting persistent store metadata: %@", error);
        return NO;
    }
    
    // Get source model
    NSManagedObjectModel *srcModel = [NSManagedObjectModel mergedModelFromBundles:[NSBundle allBundles]
                                                                 forStoreMetadata:metadata];
    if (!srcModel) {
        // No source model?
        DDLogInfo(@"Error getting source model");
        return NO;
    }
    
    // Get identifier for our store and use it to determine if we need to migrate
    NSString *srcIdentifier = [metadata[NSStoreModelVersionIdentifiersKey] lastObject];
    if (!srcIdentifier || ![srcIdentifier length]) {
        srcIdentifier = @"1.0";
    }
    NSDictionary *migrationInfo = migrationMap[srcIdentifier];
    _migrationTotal = 0;
    _migrationCount = 0;
    
    while (migrationInfo) {
        // Migration required
        DDLogInfo(@"[Migration] Migrating using mapping %@", migrationInfo[@"mapping"]);
        
        // Calculate our total and increment our count
        if (!_migrationTotal) {
            NSArray *keys = [[migrationMap allKeys] sortedArrayUsingSelector:@selector(compare:)];
            _migrationTotal = (int)[keys count] - (int)[keys indexOfObject:srcIdentifier];
        }
        _migrationCount++;
        
        // Update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            _titleLabel.text = @"Migrating App Data";
            _infoLabel.text = @"Please wait while your data is migrated.\nThis may take a few minutes to complete.";
            
            _titleLabel.hidden = NO;
            _infoLabel.hidden = NO;
            _progressView.hidden = NO;
            _spinnerView.hidden = NO;
            _supportButton.hidden = YES;
        });
        
        // Get mapping model
        NSURL *mappingModelUrl = [[NSBundle mainBundle] URLForResource:migrationInfo[@"mapping"] withExtension:@"cdm"];
        NSMappingModel *mappingModel = [[NSMappingModel alloc] initWithContentsOfURL:mappingModelUrl];
        
        // Get destination store and model
        NSString *tmpModelName = [NSString stringWithFormat:@"MainModel.momd/%@", migrationInfo[@"model"]];
        NSURL *tmpModelUrl = [[NSBundle mainBundle] URLForResource:tmpModelName withExtension:@"mom"];
        NSManagedObjectModel *dstModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:tmpModelUrl];
        
        // Delete old temp destination store if needed
        if ([tmpUrl checkResourceIsReachableAndReturnError:nil]) {
            [[NSFileManager defaultManager] removeItemAtURL:tmpUrl error:&error];
        }
        
        // Xcode incorrectly creates mapping models for v1.0 and v1.4 of our model due to this bug:
        // http://lists.apple.com/archives/cocoa-dev/2013/Mar/msg00192.html
        // We must manually set our mapping's version hashes to match our models to resolve this
        for (NSEntityMapping *entityMapping in mappingModel.entityMappings) {
            NSData *srcHash = [srcModel.entityVersionHashesByName valueForKey:entityMapping.sourceEntityName];
            NSData *dstHash = [dstModel.entityVersionHashesByName valueForKey:entityMapping.destinationEntityName];
            
            NSData *mapSrcHash = entityMapping.sourceEntityVersionHash;
            NSData *mapDstHash = entityMapping.destinationEntityVersionHash;
            
            if (![mapSrcHash isEqualToData:srcHash] && mapSrcHash && srcHash) {
                DDLogInfo(@"[Migration] Source hash mismatch for %@", entityMapping.destinationEntityName);
            }
            
            if (![mapDstHash isEqualToData:dstHash] && mapDstHash && dstHash) {
                DDLogInfo(@"[Migration] Destination hash mismatch for %@", entityMapping.destinationEntityName);
            }
            
            [entityMapping setSourceEntityVersionHash:srcHash];
            [entityMapping setDestinationEntityVersionHash:dstHash];
        }
        
        // Perform migration
        NSMigrationManager *mgr = [[NSMigrationManager alloc] initWithSourceModel:srcModel destinationModel:dstModel];
        [mgr addObserver:self forKeyPath:@"migrationProgress" options:0 context:NULL];
        NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption : @YES,
                                   NSInferMappingModelAutomaticallyOption : @NO,
                                   NSSQLitePragmasOption: @{@"journal_mode": @"delete"} };
        BOOL ok = [mgr migrateStoreFromURL:srcUrl
                                      type:NSSQLiteStoreType
                                   options:options
                          withMappingModel:mappingModel
                          toDestinationURL:tmpUrl
                           destinationType:NSSQLiteStoreType
                        destinationOptions:nil
                                     error:&error];
        [mgr removeObserver:self forKeyPath:@"migrationProgress"];
        
        if (!ok || error) {
            DDLogInfo(@"[Migration] Error migrating store: %@", error);
            return NO;
        }
        
        // Replace store with our migrated store
        [[NSFileManager defaultManager] replaceItemAtURL:srcUrl
                                           withItemAtURL:tmpUrl
                                          backupItemName:STORE_BACKUP_NAME
                                                 options:NSFileManagerItemReplacementUsingNewMetadataOnly |
                                                         NSFileManagerItemReplacementWithoutDeletingBackupItem
                                        resultingItemURL:nil
                                                   error:&error];
        
        if (error) {
            DDLogInfo(@"[Migration] Error replacing store with migrated store: %@", error);
            return NO;
        }
        
        // Finish migration - our destination model is now our source model
        srcModel = dstModel;
        
        // Get migration info for our new source model as we may need to continue migrating
        
        // Finished migration - check if we need to continue migrating
        srcIdentifier = [srcModel.versionIdentifiers anyObject];
        migrationInfo = migrationMap[srcIdentifier];
    }
    
    // Finally test that our store is valid
    NSURL *modelUrl = [[NSBundle mainBundle] URLForResource:@"MainModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelUrl];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption : @YES,
                               NSInferMappingModelAutomaticallyOption : @NO,
                               NSSQLitePragmasOption: @{@"journal_mode": @"delete"} };
    
    BOOL result;
    
    if (![psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:srcUrl options:options error:&error]) {
        // Failed
        DDLogInfo(@"[Validation] Error adding persistent store: %@", error);
        
        // Restore backup
        if ([[NSFileManager defaultManager] fileExistsAtPath:[bckUrl path]]) {
            [[NSFileManager defaultManager] replaceItemAtURL:srcUrl
                                               withItemAtURL:bckUrl
                                              backupItemName:nil
                                                     options:NSFileManagerItemReplacementUsingNewMetadataOnly
                                            resultingItemURL:nil
                                                       error:&error];
            
            if (error) {
                DDLogInfo(@"[Validation] Error restoring backup store: %@", error);
            }
        }
        
        result = NO;
    } else {
        // Success
        
        
        // Delete backup
        if ([[NSFileManager defaultManager] fileExistsAtPath:[bckUrl path]]) {
            [[NSFileManager defaultManager] removeItemAtURL:bckUrl error:&error];
            
            if (error) {
                DDLogInfo(@"[Validation] Error removing backup store: %@", error);
            }
        }
        
        result = YES;
    }
    
    // Must exclude app files from iCloud backup!
    [bckUrl setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    [tmpUrl setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    
    return result;
}

/**
 * When our observed value (migrationProgress) changes.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    dispatch_async(dispatch_get_main_queue(), ^{
        float rawProgress = [(NSMigrationManager *)object migrationProgress];
        float total = _migrationTotal;
        float finalProgress = (_migrationCount - 1)/total + rawProgress*1/total;
        
        if (finalProgress > [_progressView progress]) {
            [_progressView setProgress:finalProgress animated:YES];
        }
    });
}

/**
 * Creates basic entities that should always be available (similar to seeding).
 */
- (void)createBasicEntities
{
    // Seed all entity classes
    for (Class<UPEntity> entityClass in [UPEntity entityClasses]) {
        [entityClass seed];
    }
    
    // Save
    [[Global global].localContext save];
}

/**
 * Fixes potential issues with our data (e.g. invalid data caused by incorrect logic that has been patched).
 */
- (void)fixDataIfNeeded
{
    // Fix units with offline author in online school
    for (Unit *unit in [Unit findAll]) {
        if ([unit.author isLocal] && ![unit.school isLocal]) {
            DDLogInfo(@"[Fix] Changing author of online unit '%@' to our account person", unit.nameString);
            unit.author = [Global global].account;
        }
    }
    
    // Save
    [[Global global].localContext save];
}

/**
 * Sets up RestKit.
 */
- (void)setupRestKit
{
    // Create object manager
    RKObjectManager *manager = [RKObjectManager managerWithBaseURLString:@"http://example.com/"];
    
    // Create store
    NSURL *modelUrl = [[NSBundle mainBundle] URLForResource:@"MainModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelUrl];
    manager.objectStore = [RKManagedObjectStore objectStoreWithStoreFilename:STORE_NAME
                                                       usingSeedDatabaseName:nil
                                                          managedObjectModel:model
                                                                    delegate:self];
    [manager.objectStore setCacheStrategy:[UPManagedObjectCache new]];
    
    // Create local context
    dispatch_sync(dispatch_get_main_queue(), ^{
        [Global global].localContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:
                                        NSMainQueueConcurrencyType];
        [Global global].localContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
        [Global global].localContext.undoManager = nil;
        [Global global].localContext.persistentStoreCoordinator = manager.objectStore.persistentStoreCoordinator;
        
        // Set as context for main thread
        [manager.objectStore setManagedObjectContextForCurrentThread:[Global global].localContext];
    });
    
    // Setup mapping provider
    manager.mappingProvider = [UPMappingProvider sharedProvider];
    
    // Setup mapping dates
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZ";
    
    [RKObjectMapping setPreferredDateFormatter:formatter]; // Serializing
    [RKObjectMapping addDefaultDateFormatter:formatter]; // Deserializing
    
    // Setup client
    manager.client.requestQueue.showsNetworkActivityIndicatorWhenBusy = YES;
    manager.client.cachePolicy = RKRequestCachePolicyNone;
    manager.client.timeoutInterval = 60.0;
    manager.client.disableCertificateValidation = YES;
    manager.client.requestCache.storagePolicy = RKRequestCacheStoragePolicyForDurationOfSession;
    [manager.client setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
    
    // Setup parsers
    Class<RKParser> parser;
    parser = [[RKParserRegistry sharedRegistry] parserClassForMIMEType:@"application/json"];
    [[RKParserRegistry sharedRegistry] setParserClass:parser forMIMEType:@"text/plain"];
    parser = [[RKParserRegistry sharedRegistry] parserClassForMIMEType:@"application/xml"];
    [[RKParserRegistry sharedRegistry] setParserClass:parser forMIMEType:@"application/rss+xml"];
    
    // Setup logging
    RKLogConfigureByName("RestKit", RKLogLevelError);
    RKLogConfigureByName("RestKit/ObjectMapping", RKLogLevelError);
    RKLogConfigureByName("RestKit/Network", RKLogLevelError);
    RKLogConfigureByName("RestKit/Network/Reachability", RKLogLevelError);
    RKLogConfigureByName("RestKit/Network/Queue", RKLogLevelError);
    RKLogConfigureByName("RestKit/CoreData", RKLogLevelError);
    RKLogConfigureByName("RestKit/CoreData/Cache", RKLogLevelError);
    RKLogConfigureByName("RestKit/Support", RKLogLevelError);
    
    // Set our URL
    manager.client.baseURL = [RKURL URLWithString:SERVER_URL];
    DDLogInfo(@"[App] Using URL <%@>", SERVER_URL);
}

/**
 * Sets up GRMustache.
 */
- (void)setupGRMustache
{
    GRMustacheConfiguration *config = [GRMustacheConfiguration defaultConfiguration];
    
    // Add literal support
    config.baseContext = [config.baseContext contextByAddingObject:[MustacheLiterals new]];
    
    // Add setting/string support
    config.baseContext = [config.baseContext contextByAddingObject:@{
        @"settingBoolForKey" : [GRMustacheFilter filterWithBlock:^id(NSString *key) {
            key = [key stringByReplacingOccurrencesOfString:@"-" withString:@"."];
            return [[[Global global] settingForKey:key] boolValue] ? @YES : nil;
        }],
        @"stringForKey" : [GRMustacheFilter filterWithBlock:^id(NSString *key) {
            key = [key stringByReplacingOccurrencesOfString:@"-" withString:@"."];
            return [[Global global] stringForKey:key];
        }]
    }];
}

/**
 * Sets up logging.
 */
- (void)setupLogging
{
    // Log to Xcode and Console.app only in debug mode
#ifdef DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
#endif
    
    // Always log to file
    DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
    fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
    [Global global].logFileManager = fileLogger.logFileManager;
    
    [DDLog addLogger:fileLogger];
}

/**
 * Main initialisation method.
 */
- (void)initialise
{
    // Reset UI
    _titleLabel.text = @"";
    _infoLabel.text = @"";
    
    _titleLabel.hidden = YES;
    _infoLabel.hidden = YES;
    _progressView.hidden = YES;
    _spinnerView.hidden = YES;
    _supportButton.hidden = YES;
    
    // Init logging
    static BOOL initLoggingSuccess = NO;
    void (^initLogging)(void (^)()) = ^(void (^block)()){
        if (initLoggingSuccess) {
            block();
        }
        
        [self setupLogging];
        initLoggingSuccess = YES;
        block();
    };
    
    // Init freemium
    static BOOL initFreemiumSuccess = NO;
    void (^initFreemium)(void (^)()) = ^(void (^block)()){
        if (initFreemiumSuccess) {
            block();
        }
        
        [[Global global] updateFreemiumWithRefresh:NO success:nil failure:nil];
        initFreemiumSuccess = YES;
        block();
    };
    
    // Init replacement store
    void (^initReplacementStore)(void (^)()) = ^(void (^block)()){
        // Check if we have a replacement store
        if ([Global global].replacementStoreURL) {
            CCAlertView *alert = [[CCAlertView alloc] initWithTitle:@"Restore Backup"
                                                            message:
                                  @"Are you sure you want to restore this App Data backup? Your existing data will be "
                                  "replaced."];
            [alert addButtonWithTitle:@"Cancel" block:^{
                [Global global].replacementStoreURL = nil;
                
                block();
            }];
            [alert addButtonWithTitle:@"Restore" block:^{
                [self replaceStoreIfNeeded];
                
                block();
            }];
            [alert show];
        } else {
            block();
        }
    };
    
    // Start initialising
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    initLogging(^{
        initFreemium(^{
            initReplacementStore(^{
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    if ([self migrateStoreIfNeeded]) {
                        // Success
                        [UIApplication sharedApplication].idleTimerDisabled = NO;
                        
                        [self setupRestKit];
                        [self setupGRMustache];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self createBasicEntities];
                            [self fixDataIfNeeded];
                            
                            [[Global global] updateICloudBackupSettings];
                            
                            // Done
                            [self performSegueWithIdentifier:@"complete" sender:nil];
                        });
                    } else {
                        // Failed
                        [UIApplication sharedApplication].idleTimerDisabled = NO;
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Update UI
                            _titleLabel.text = @"Error Migrating App Data";
                            _infoLabel.text = @"An error occurred while migrating your data.\nPlease contact support.";
                            [_spinnerView stopAnimation];
                            
                            _titleLabel.hidden = NO;
                            _infoLabel.hidden = NO;
                            _supportButton.hidden = NO;
                            _progressView.hidden = YES;
                            _spinnerView.hidden = NO;
                        });
                    }
                });
            });
        });
    });
}

/***************************************************************************************************
 * UIViewController
 */

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Setup notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(initialise)
                                                 name:UnitPlannerMobileDidOpenURLNotification
                                               object:nil];
    
    // Setup UI
    _titleLabel.hidden = YES;
    _infoLabel.hidden = YES;
    _progressView.hidden = YES;
    _spinnerView.hidden = YES;
    _supportButton.hidden = YES;
    
    [_supportButton addTarget:[Global global]
                       action:@selector(showContactSupport)
             forControlEvents:UIControlEventTouchUpInside];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self initialise];
}

@end

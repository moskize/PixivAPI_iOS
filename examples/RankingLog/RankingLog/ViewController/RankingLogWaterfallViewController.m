//
//  RankingLogWaterfallViewController.m
//  RankingLog
//
//  Created by Zhou Hao on 14/10/30.
//  Copyright (c) 2014年 Zhou Hao. All rights reserved.
//

#import "RankingLogWaterfallViewController.h"
#import <SVProgressHUD/SVProgressHUD.h>

#import "DatePickerViewController.h"
#import "PixivDetailScrollImageViewController.h"
#import "ModelSettings.h"

#import "AppDelegate.h"
#import "PixivAPI.h"

//#define __DISABLE_R18
#define _USERNAME @"grave1"
#define _PASSWORD @"6654321"

@interface RankingLogWaterfallViewController ()

@property (nonatomic) NSInteger currentPage;

@end

@implementation RankingLogWaterfallViewController

- (void)updateTitle
{
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    dateFormat.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"];
    dateFormat.dateFormat = @"yyyy-MM-dd";
    
    NSString *title = [NSString stringWithFormat:@"%@:p%ld/%ld - [%@]", [ModelSettings sharedInstance].mode,
                       (long)self.currentPage, (long)[ModelSettings sharedInstance].pageLimit,
                       [dateFormat stringFromDate:[ModelSettings sharedInstance].date]];
    if (![ModelSettings sharedInstance].isShowLargeImage) {
        title = [title stringByAppendingString:@" (M)"];
    }
    
    __weak RankingLogWaterfallViewController *weakSelf = self;
    [[PixivAPI sharedInstance] onMainQueue:^{
        weakSelf.navigationItem.title = title;
    }];
}

- (NSArray *)fetchNextRankingLog
{
    // 检查翻页是否达到深度限制，达到则自动日期前移
    NSString *mode = [ModelSettings sharedInstance].mode;
    if (self.currentPage >= [ModelSettings sharedInstance].pageLimit) {
        if ([mode isEqualToString:@"weekly"] || [mode isEqualToString:@"weekly_r18"]) {
            [[ModelSettings sharedInstance] updateDateIntervalAgo:7*86400.0];
        } else if ([mode isEqualToString:@"monthly"]) {
            [[ModelSettings sharedInstance] updateDateIntervalAgo:30*86400.0];
        } else {
            [[ModelSettings sharedInstance] updateDateIntervalAgo:86400.0];
        }
        
        [ModelSettings sharedInstance].isChanged = NO;
        self.currentPage = 0;
        //self.illusts = @[];
    }
    
    self.currentPage += 1;
    [self updateTitle];
    
    NSCalendarUnit flags = NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear;
    NSDateComponents *components = [[NSCalendar currentCalendar] components:flags fromDate:[ModelSettings sharedInstance].date];

    NSLog(@"get RankingLog(%@, %ld-%ld-%ld, page=%ld)", mode, (long)[components year], (long)[components month], (long)[components day], (long)self.currentPage);
    
#ifndef __DISABLE_R18
    return [[PixivAPI sharedInstance] SAPI_ranking_log:[components year] month:[components month] day:[components day]
                                                  mode:mode page:self.currentPage requireAuth:YES];
#else
    return [[PixivAPI sharedInstance] SAPI_ranking_log:[components year] month:[components month] day:[components day]
                                                  mode:mode page:self.currentPage requireAuth:NO];
#endif
}

- (void)asyncGetRankingLog
{
    __weak RankingLogWaterfallViewController *weakSelf = self;
    [ApplicationDelegate setNetworkActivityIndicatorVisible:YES];
    [[PixivAPI sharedInstance] asyncBlockingQueue:^{
        
        NSArray *SAPI_illusts = [weakSelf fetchNextRankingLog];
        [[PixivAPI sharedInstance] onMainQueue:^{
            [ApplicationDelegate setNetworkActivityIndicatorVisible:NO];
            if (SAPI_illusts) {
                weakSelf.illusts = [weakSelf.illusts arrayByAddingObjectsFromArray:SAPI_illusts];
            } else {
                NSLog(@"fetchNextRankingLog: failed.");
            }
        }];
        
    }];
}

- (void)loginAndRefreshView
{
    self.illusts = @[];
    self.currentPage = 0;
    
#ifndef __DISABLE_R18
    __weak RankingLogWaterfallViewController *weakSelf = self;
    
    [SVProgressHUD showWithStatus:@"Login..." maskType:SVProgressHUDMaskTypeBlack];
    
    [[PixivAPI sharedInstance] asyncBlockingQueue:^{
        NSString *username = [ModelSettings sharedInstance].username;
        NSString *password = [ModelSettings sharedInstance].password;
        BOOL success = [[PixivAPI sharedInstance] loginIfNeeded:username password:password];
        
        [[PixivAPI sharedInstance] onMainQueue:^{
            if (!success) {
                [SVProgressHUD showErrorWithStatus:@"Login failed! Check your pixiv ID and password."];
                return;
            }
            
            [SVProgressHUD dismiss];
            [weakSelf asyncGetRankingLog];
        }];
    }];
#else
    [self asyncGetRankingLog];
#endif
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    //[[ModelSettings sharedInstance] clearSettingFromUserDefaults];
    
    if (![[ModelSettings sharedInstance] loadSettingFromUserDefaults]) {
        // 第一次进入先跳转设置页卡
        [self performSegueWithIdentifier:@"DatePicker" sender:self];
    } else {
        [self loginAndRefreshView];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if ([ModelSettings sharedInstance].isChanged) {
        // 发生过变化，重新刷新RankingLog
        NSLog(@"refresh RankingLog");
        [ModelSettings sharedInstance].isChanged = NO;
        
        [self loginAndRefreshView];
    }
    
    [self updateTitle];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"DatePicker"]) {
        if ([segue.destinationViewController isKindOfClass:[DatePickerViewController class]]) {
            DatePickerViewController *dpvc = (DatePickerViewController *)segue.destinationViewController;
            // modeArray for RankingLog
            dpvc.modeArray = @[
                @"daily", @"weekly", @"monthly", @"male", @"female", @"rookie",
#ifndef __DISABLE_R18
                @"daily_r18", @"weekly_r18", @"male_r18", @"female_r18", @"r18g",
#endif
            ];
        }
    } else if ([segue.identifier isEqualToString:@"ImageDetail"]) {
        if ([segue.destinationViewController isKindOfClass:[PixivDetailScrollImageViewController class]]) {
            PixivDetailScrollImageViewController *ivc = (PixivDetailScrollImageViewController *)segue.destinationViewController;
            NSArray *indexPaths = [self.collectionView indexPathsForSelectedItems];
            NSIndexPath *indexPath = [indexPaths objectAtIndex:0];
            ivc.illusts = self.illusts;
            ivc.index = indexPath.row;
        }
    }
}

#pragma mark - UICollectionView

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == [self.illusts count]-1) {
        // fetch next
        [self asyncGetRankingLog];
    }
    return [super collectionView:collectionView cellForItemAtIndexPath:indexPath];
}

@end

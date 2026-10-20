#import "CTRootListController.h"
#import <Preferences/PSSpecifier.h>
#import "../src/Auth.h"

@implementation CTRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSArray *hosts = CTAuthListHosts();
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Paired Computers"];
        [group setProperty:hosts.count ? @"Swipe left on a computer to revoke it."
                                       : @"No computers paired." forKey:@"footerText"];
        [specs addObject:group];
        for (NSDictionary *h in hosts) {
            PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:h[@"name"] target:self set:nil get:nil
                                                            detail:nil cell:PSStaticTextCell edit:nil];
            [s setProperty:h[@"id"] forKey:@"hostID"];
            [specs addObject:s];
        }
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers]; // another computer may have paired since this was last shown
}

- (NSString *)hostIDAtIndexPath:(NSIndexPath *)indexPath {
    return [[self specifierAtIndexPath:indexPath] propertyForKey:@"hostID"];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self hostIDAtIndexPath:indexPath] != nil;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self hostIDAtIndexPath:indexPath] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
                                             forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *hostID = [self hostIDAtIndexPath:indexPath];
    NSString *name = [self specifierAtIndexPath:indexPath].name;
    if (style != UITableViewCellEditingStyleDelete || !hostID) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Revoke this computer?"
        message:[@"“" stringByAppendingFormat:@"%@” will need to be paired again.", name]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) { [self reloadSpecifiers]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Revoke" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) { [self revoke:hostID]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)revoke:(NSString *)hostID {
    if (CTAuthRemoveHost(hostID)) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR(CT_REVOKED_NOTIFICATION), NULL, NULL, YES);
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't revoke"
            message:@"The pairing file couldn't be changed." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    [self reloadSpecifiers];
}

@end

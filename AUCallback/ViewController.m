//
//  ViewController.m
//  AUCallback
//
//  Edited by Chinh Nguyen on 11/05/13.
//  Copyright (c) 2013 Chinh Nguyen. All rights reserved.
//

#import "ViewController.h"
#import "AudioController.h"
@interface ViewController (){
    
}
@property (strong, nonatomic) AudioController *audioController;
@property (weak, nonatomic) IBOutlet UISwitch *passingThroughSwitch;
@property (strong, nonatomic) AVAudioPlayer* player;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.audioController = [[AudioController alloc] init];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
// Dispose of any resources that can be recreated.
}
- (IBAction)togglePassingThrough:(id)sender {
    if(self.passingThroughSwitch.on){
        [self.audioController startRecording];
        [self.audioController startRendering];
    } else{
        [self.audioController stopRecording];
        [self.audioController stopRendering];
    }
}
- (IBAction)play:(id)sender {
    NSArray *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *url = [urls[0] URLByAppendingPathComponent:@"audio.caf"];
    NSError *error = nil;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    [self.player play];
}

@end

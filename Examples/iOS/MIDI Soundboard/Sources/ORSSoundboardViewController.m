//
//  ORSSoundboardViewController.m
//  MIDI Soundboard
//
//  Created by Andrew Madsen on 6/2/13.
//  Copyright (c) 2013 Open Reel Software. All rights reserved.
//
#import <Foundation/NSRange.h>
#import "ORSSoundboardViewController.h"
#import <MIKMIDI/MIKMIDI.h>
#import <MIKMIDI/MIKMIDISequence.h>
#import <MIKMIDI/MIKMIDIPlayer.h>

@interface ORSSoundboardViewController ()

@property (nonatomic, strong) MIKMIDIDeviceManager *deviceManager;
@property (nonatomic, strong) MIKMIDIDevice	*device;
@property (nonatomic, strong) id connectionToken;

@property (nonatomic, strong, readonly) MIKMIDISynthesizer *synthesizer;

@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *pianoButtons;

@end

@implementation ORSSoundboardViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	for (UIButton *button in self.pianoButtons) {
		[button addTarget:self action:@selector(pianoKeyDown:) forControlEvents:UIControlEventTouchDown];
		[button addTarget:self action:@selector(pianoKeyUp:) forControlEvents:UIControlEventTouchUpInside];
		[button addTarget:self action:@selector(pianoKeyUp:) forControlEvents:UIControlEventTouchUpOutside];
		[button addTarget:self action:@selector(pianoKeyUp:) forControlEvents:UIControlEventTouchCancel];
	}
    
    NSString *itunesDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *midiPath = [NSString stringWithFormat:@"%@/%@", itunesDir,  @"song.mid"];
    NSURL *midiUrl = [NSURL fileURLWithPath:midiPath];
    
    NSError* err;
    MIKMIDISequence* sequence = [MIKMIDISequence sequenceWithFileAtURL:midiUrl error:&err];
    MIKMIDISequencer *sequencer = [MIKMIDISequencer sequencerWithSequence:sequence];
    NSURL *soundfontURL = [[NSBundle mainBundle] URLForResource:@"MagicSFver2" withExtension:@"sf2"];
    
    
//    self.sequencer.sequence = sequence;
//    for (MIKMIDITrack *track in sequence.tracks) {
//        MIKMIDISynthesizer *synth = [self.sequencer builtinSynthesizerForTrack:track];
//        XCTAssertNotNil(synth, @"-builtinSynthesizerForTrack: test failed, because it returned nil.");
//    }

    
    for (MIKMIDITrack *track in sequence.tracks) {
        NSArray *trackEvents = [track events];
        u_char instId = 0;
        for (MIKMIDIEvent *event in trackEvents)
        {
            if (event.eventType == MIKMIDIEventTypeMIDIProgramChangeMessage)
            {
                NSData *instData = [event.data subdataWithRange: NSMakeRange(1, 1)];
                instId = CFSwapInt32BigToHost(*(u_char*)([instData bytes]));
            }
        }
        MIKMIDISynthesizer *synth = [sequencer builtinSynthesizerForTrack:track];
        NSError *error = @"";
        if (![synth loadSoundfontFromFileAtURL:soundfontURL presetID:instId error:&error]) {
            NSLog(@"Error loading soundfont (%@) into synthesizer for track (%@): %@", soundfontURL, track, sequencer);
        }
    }
    [sequencer startPlayback];
    
    
}

#pragma mark - Actions

- (IBAction)pianoKeyDown:(id)sender
{
	UInt8 note = 60 + [sender tag];
	MIKMIDINoteOnCommand *noteOn = [MIKMIDINoteOnCommand noteOnCommandWithNote:note velocity:127 channel:0 timestamp:[NSDate date]];
    [self.synthesizer handleMIDIMessages:@[noteOn]];
}

- (IBAction)pianoKeyUp:(id)sender
{
	UInt8 note = 60 + [sender tag];
	MIKMIDINoteOffCommand *noteOff = [MIKMIDINoteOffCommand noteOffCommandWithNote:note velocity:127 channel:0 timestamp:[NSDate date]];
	[self.synthesizer handleMIDIMessages:@[noteOff]];
}

#pragma mark - Private

- (void)disconnectFromDevice:(MIKMIDIDevice *)device
{
	if (!device) return;
	[self.deviceManager disconnectConnectionForToken:self.connectionToken];
	
	self.textView.text = @"";
}

- (void)connectToDevice:(MIKMIDIDevice *)device
{
	if (!device) return;
	NSArray *sources = [device.entities valueForKeyPath:@"@unionOfArrays.sources"];
	if (![sources count]) return;
	MIKMIDISourceEndpoint *source = [sources objectAtIndex:0];
	NSError *error = nil;
	
	id connectionToken = [self.deviceManager connectInput:source error:&error eventHandler:^(MIKMIDISourceEndpoint *source, NSArray *commands) {
		
		NSMutableString *textViewString = [self.textView.text mutableCopy];
		for (MIKMIDIChannelVoiceCommand *command in commands) {
			if ((command.commandType | 0x0F) == MIKMIDICommandTypeSystemMessage) continue;
			
			[[UIApplication sharedApplication] handleMIDICommand:command];
			
			[textViewString appendFormat:@"Received: %@\n", command];
			NSLog(@"Received: %@", command);
		}
		self.textView.text = textViewString;
	}];
	if (!connectionToken) NSLog(@"Unable to connect to input: %@", error);
	self.connectionToken = connectionToken;
}

#pragma mark ORSAvailableDevicesTableViewControllerDelegate

- (void)availableDevicesTableViewController:(ORSAvailableDevicesTableViewController *)controller midiDeviceWasSelected:(MIKMIDIDevice *)device
{
	self.device = device;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"availableDevices"]) {
		if (![self.deviceManager.availableDevices containsObject:self.device]) {
			self.device = nil;
		}
	}
}

#pragma mark - Properties

@synthesize deviceManager = _deviceManager;

- (void)setDeviceManager:(MIKMIDIDeviceManager *)deviceManager
{
	if (deviceManager != _deviceManager) {
		[_deviceManager removeObserver:self forKeyPath:@"availableDevices"];
		_deviceManager = deviceManager;
		[_deviceManager addObserver:self forKeyPath:@"availableDevices" options:NSKeyValueObservingOptionInitial context:NULL];
	}
}

- (MIKMIDIDeviceManager *)deviceManager
{
	if (!_deviceManager) {
		self.deviceManager = [MIKMIDIDeviceManager sharedDeviceManager];
	}
	return _deviceManager;
}

- (void)setDevice:(MIKMIDIDevice *)device
{
	if (device != _device) {
		[self disconnectFromDevice:_device];
		_device = device;
		[self connectToDevice:_device];
	}
}

@synthesize synthesizer = _synthesizer;
- (MIKMIDISynthesizer *)synthesizer
{
	if (!_synthesizer) {
		_synthesizer = [[MIKMIDISynthesizer alloc] init];
		NSURL *soundfont = [[NSBundle mainBundle] URLForResource:@"Grand Piano" withExtension:@"sf2"];
		NSError *error = nil;
		if (![_synthesizer loadSoundfontFromFileAtURL:soundfont error:&error]) {
			NSLog(@"Error loading soundfont for synthesizer. Sound will be degraded. %@", error);
		}
	}
	return _synthesizer;
}

@end

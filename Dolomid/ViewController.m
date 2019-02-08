//
//  ViewController.m
//  Dolomid
//
//  Created by Christopher Cahoon on 2/5/19.
//  Copyright © 2019 Chairpeople. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic)                   BOOL midiInitialized;   /// Has MIDI been initialized for the application?

@property (nonatomic, strong, nullable) SMVirtualInputStream *virtualInputStream; // our virtual MIDI endpoint destination.*/

@property (nonatomic, strong, nullable) SMPortInputStream *linnstrumentIn;

@property (nonatomic, strong, nullable) SMPortOutputStream *linnstrumentOut;

@property (nonatomic, strong, nullable) SMPortOutputStream *portOut;

@property (assign) BOOL linnstrumentInUserMode;

@property (nonatomic, strong, nullable) NSMutableDictionary *linnstrumentState;

@property (nonatomic, assign) NSString *lastSelectedOutput;

@property (weak) IBOutlet NSTextField *linnConnectedLabel;
@property (weak) IBOutlet NSPopUpButton *linnLayoutsButton;
@property (weak) IBOutlet NSPopUpButton *availableOutputsButton;

@property (weak) IBOutlet NSButton *linnConnectButton;

@property (weak) IBOutlet NSTextField *statusTextField;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.linnLayoutsButton removeAllItems];
    [self.linnLayoutsButton addItemWithTitle:@"56 EDO - 7x8"];
    self.linnLayoutsButton.lastItem.representedObject = @"7x8";

    [self.linnLayoutsButton addItemWithTitle:@"49 EDO 7x7 with Low Row Ribbon"];
    self.linnLayoutsButton.lastItem.representedObject = @"7x7";

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_MIDISetupChanged:) name:@"SMClientSetupChangedNotification" object:nil];

    // Insert code here to initialize your application
    // MIDI
  /*  @try */
    {
        self.linnstrumentIn = [[SMPortInputStream alloc] init];
        self.linnstrumentOut =  [[SMPortOutputStream alloc] init];
        self.portOut =  [[SMPortOutputStream alloc] init];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _MIDISetupChanged:nil];
    });

/*    @catch ( NSException *exception )
    {
        NSLog( @"Error: Could not create MIDI input port stream: Caught %@: %@", [exception name], [exception reason] );
        self.portInputStream = nil;
    }*/
}

- (void) connectToLinnstrument
{
    if ( self.linnstrumentOut )
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSLog(@"found linnstrument: %@", self.linnstrumentOut.endpoints.anyObject);

            SMVoiceMessage *setCol = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusControl];
            setCol.channel = 1;
            setCol.dataByte1 = 20; // Sets Column coordinate for cell color change with CC 22 (starts from 0)
            setCol.dataByte2 = 2; // Column

            SMVoiceMessage *setRow = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusControl];
            setRow.channel = 1;
            setRow.dataByte1 = 21; // Row coordinate for cell color change with CC 22 (starts from 0)
            setRow.dataByte2 = 2; // Row

            SMVoiceMessage *setColor = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusControl];
            setColor.channel = 1;
            setColor.dataByte1 = 22; // Row coordinate for cell color change with CC 22 (starts from 0)

            NSMutableArray *settings = [NSMutableArray array];

            // Enable firmware user mode: https://github.com/rogerlinndesign/linnstrument-firmware/blob/master/user_firmware_mode.txt
            [settings addObjectsFromArray:[self messagesForNRPNMessage:245 value:1]];

            for ( int row = 0; row < 8; row++ )
            {
                for ( int col = 1; col < 20; col ++ )
                {
                    setRow.dataByte2 = row;
                    setCol.dataByte2 = col;
                    setColor.dataByte2 = arc4random_uniform(12); // Color

                    [settings addObjectsFromArray:@[[setCol copy], [setRow copy], [setColor copy]]];
                }
            }

            // NSLog(@"settings: %@", settings);

            // NSLog(@"messages: %@ to outstream %@", [setColorMessages valueForKey:@"dataForDisplay"], linnstrumentOutStream);

            NSLog(@"setting up user mode and random colors");
            [self.linnstrumentOut takeMIDIMessages:settings];

            self.linnstrumentInUserMode = YES; // TODO verify with a quick communication
            self.linnstrumentState = [NSMutableDictionary dictionaryWithCapacity:8 * 20];

            /*
             0   Off
             1   Red
             2   Yellow
             3   Green
             4   Cyan
             5   Blue
             6   Magenta
             7   Black
             8   White
             9   Orange
             10  Lime
             11 Pink */
        });

    }
}

- (NSArray <SMMessage *>*) messagesForNRPNMessage:(int16_t)number value:(int16_t)value
{
    /* https://github.com/rogerlinndesign/linnstrument-firmware/blob/master/midi.txt
     NRPN 245 Enabling/disabling User Firmware mode (0: disable, 1: enable)


     1011nnnn   01100011 ( 99)  0vvvvvvv         NRPN parameter number MSB CC
     1011nnnn   01100010 ( 98)  0vvvvvvv         NRPN parameter number LSB CC
     1011nnnn   00000110 (  6)  0vvvvvvv         NRPN parameter value MSB CC
     1011nnnn   00100110 ( 38)  0vvvvvvv         NRPN parameter value LSB CC
     1011nnnn   01100101 (101)  01111111 (127)   RPN parameter number Reset MSB CC
     1011nnnn 01100100 (100) 01111111 (127) RPN parameter number Reset LSB CC */

    Byte numberMSB = (number >> 7) & 0x7F;
    Byte numberLSB = (number & 0x7F);

    Byte valueMSB = (value >> 7) & 0x7F;
    Byte valueLSB = (value & 0x7F);

    Byte NRPNMessageBytes[] = {
        99, numberMSB,
        98, numberLSB,
        6, valueMSB,
        38, valueLSB,
        101, 127,
        100, 127
    };

    NSMutableArray *ccMessages = [NSMutableArray array];
    for ( int i = 0; i < 6; i++ )
    {
        SMVoiceMessage *cc = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusControl];
        cc.channel = 1;
        cc.dataByte1 = NRPNMessageBytes[i * 2];
        cc.dataByte2 = NRPNMessageBytes[1 + (i * 2)];

        [ccMessages addObject:cc];
    }

    return ccMessages;
}

- (void) takeMIDIMessages:(NSArray *)messages
{
    // NSLog( @"received MIDI message: %@ of (%lu)", [messages firstObject], (unsigned long)[messages count] );

    for ( SMMessage *message in messages )
    {
        if ( self.linnstrumentInUserMode )
        {
            [self updateLinnstrumentState:message];
            continue;
        }

        if ( [message matchesMessageTypeMask:SMMessageTypeAllVoiceMask] )
        {
            NSLog(@"got voice message %@ %@ from %@", message.dataForDisplay, message.expertDataForDisplay, message.originatingEndpointForDisplay);
            [self playPeakNoteWithVoiceMessage:(SMVoiceMessage *)message];
        }
        else
        {
            NSLog(@"got non voice message type: %@ from %@", message.typeForDisplay, message.originatingEndpointForDisplay );
        }
    }
}

- (void) updateLinnstrumentState:(SMMessage *)message
{
    if ( [message matchesMessageTypeMask:SMMessageTypeAllVoiceMask] )
    {
        SMVoiceMessage *voiceMsg = (SMVoiceMessage *)message;
        // For all voice messages — Note Number: Column, Channel: Row

        NSString *coord = [NSString stringWithFormat:@"%@x%@", @(voiceMsg.dataByte1), @(voiceMsg.channel)];
        if ( self.linnstrumentState[coord] == nil )
        {
            self.linnstrumentState[coord] = [@{} mutableCopy];
        }

        if ( voiceMsg.status == SMVoiceMessageStatusNoteOn )
        {
            self.linnstrumentState[coord][@"velocity"] = @(voiceMsg.dataByte2);
        }
        else if ( voiceMsg.status == SMVoiceMessageStatusNoteOff )
        {
            NSLog(@"note off at %@", coord);
            // self.linnstrumentState[coord][@"release-velocity"] = @(voiceMsg.dataByte2);
            [self.linnstrumentState removeObjectForKey:coord];
        }
    }
    else
    {
        NSLog(@"unhandled message: %@ %@ %@", (message.typeForDisplay), (message.channelForDisplay), (message.dataForDisplay));
    }

    NSLog(@"current state: %@", self.linnstrumentState);
    NSLog(@"held buttons: %@", @(self.linnstrumentState.count));

}

-  (void) playPeakNoteWithVoiceMessage:(SMVoiceMessage *)message
{
    if ( !self.portOut )
    {
        return;
    }

    if ( message.status == SMVoiceMessageStatusNoteOn )
    {
        /*
         SMVoiceMessage *playC = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusNoteOn];
         playC.channel = 1;
         playC.dataByte1 = 60; // Note
         playC.dataByte2 = 80; // Velocity*/

        [self.portOut takeMIDIMessages:@[message]];
    }
    if (message.status == SMVoiceMessageStatusNoteOff )
    {
        /*
         SMVoiceMessage *offC = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusNoteOff];
         offC.channel = 1;
         offC.dataByte1 = 60; // Note
         offC.dataByte2 = 80; // Velocity*/

        [self.portOut takeMIDIMessages:@[message]];
    }

    if ( message.status == SMVoiceMessageStatusAftertouch )
    {
        // Pitch bend value
        int pitchBend = message.dataByte2 * 100;
        SMVoiceMessage *bend = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusPitchWheel];
        bend.channel = 1;
        bend.dataByte1 = (pitchBend & 0x7F); // LSB
        bend.dataByte2 = (pitchBend >> 7) & 0x7F; // MSB

        [self.portOut takeMIDIMessages:@[bend]];
    }
}

- (void) _MIDISetupChanged:(NSNotification *)note
{
    NSString *linnName = nil;

    [self.availableOutputsButton removeAllItems];

    for ( SMDestinationEndpoint *destination in [SMDestinationEndpoint destinationEndpoints] )
    {
        NSLog(@"destination: %@", destination);
        if ( [destination.name containsString:@"Linn"] )
        {
            if ( linnName != nil )
            {
                NSLog(@"Multiple LinnStruments attached");
                continue;
            }
            [self.linnstrumentOut setEndpoints:[NSSet setWithObject:destination]];
            self.linnConnectedLabel.stringValue = [NSString stringWithFormat:@"%@ - Connected", destination.name];

            linnName = destination.name;
        }
        else
        {
            [self.availableOutputsButton addItemWithTitle:destination.uniqueName];
            self.availableOutputsButton.lastItem.representedObject = destination.uniqueName;

            if ( [destination.name isEqualToString:self.lastSelectedOutput] )
            {
                [self.availableOutputsButton selectItemWithTitle:destination.uniqueName];
            }
        }
    }

    if ( linnName == nil )
    {
          self.linnConnectedLabel.stringValue = [NSString stringWithFormat:@"Couldn't find LinnStrument"];
    }
    else
    {
        SMSourceEndpoint *linnIn = [SMSourceEndpoint sourceEndpointWithName:linnName];
        if ( linnIn == nil )
        {
            self.linnConnectedLabel.stringValue = [NSString stringWithFormat:@"No LinnStrument Input, but found output"];
            [self.linnstrumentIn addEndpoint:linnIn]             ;
        }
    }

    NSString *destinationName = self.availableOutputsButton.selectedItem.representedObject;
    if ( !destinationName )
    {
        destinationName = self.availableOutputsButton.lastItem.representedObject;
    }

    if ( destinationName )
    {
        SMDestinationEndpoint *outEndpoint = [SMDestinationEndpoint destinationEndpointWithName:destinationName];
        if ( outEndpoint == nil )
        {
            NSLog(@"couldn't connect to output");
        }
        else
        {
            [self.portOut setEndpoints:[NSSet setWithObject:outEndpoint]];
        }
    }
    else
    {
        NSLog(@"no selected destination");
        [self.availableOutputsButton addItemWithTitle:@"(No connected outputs)"];
    }

    self.linnConnectButton.enabled = self.linnstrumentOut.endpoints.count > 0;

    if ( self.linnConnectButton.enabled )
    {
        [self.linnConnectButton setTitle:@"Refresh LinnStrument Layout"];
    }

//    [[NSNotificationCenter defaultCenter] postNotificationName:@"QLabMIDIHardwareDeviceListDidChange" object:nil];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)connectToLinnstrument:(id)sender
{
    [self connectToLinnstrument];
}


@end

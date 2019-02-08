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

@property (strong) NSMutableDictionary *layouts;
@property (strong) NSMutableDictionary *grid;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.linnLayoutsButton removeAllItems];
    [self.linnLayoutsButton addItemWithTitle:@"56 EDO - 7x8"];
    self.linnLayoutsButton.lastItem.representedObject = @"7x8";

    [self.linnLayoutsButton addItemWithTitle:@"49 EDO 7x7 with Low Row Ribbon"];
    self.linnLayoutsButton.lastItem.representedObject = @"7x7";

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(MIDISetupChanged:) name:@"SMClientSetupChangedNotification" object:nil];

    // Insert code here to initialize your application
    // MIDI
  /*  @try */
    {
        self.linnstrumentIn = [[SMPortInputStream alloc] init];
        self.linnstrumentOut =  [[SMPortOutputStream alloc] init];
        self.portOut =  [[SMPortOutputStream alloc] init];
    }

    [self MIDISetupChanged:nil];

/*    @catch ( NSException *exception )
    {
        NSLog( @"Error: Could not create MIDI input port stream: Caught %@: %@", [exception name], [exception reason] );
        self.portInputStream = nil;
    }*/
}

- (NSDictionary <NSString *, NSNumber *>*)linnstrumentColorsByName
{
    return @{
                                  @"off": @0,
                                  @"red": @1,
                                  @"yellow": @2,
                                  @"green": @3,
                                  @"cyan": @4,
                                  @"blue": @5,
                                  @"magenta": @6,
                                  @"black": @7,
                                  @"white": @8,
                                  @"orange": @9,
                                  @"lime": @10,
                                  @"pink": @11,
                                  };
}

- (void) connectToLinnstrument
{
    if ( !self.linnstrumentOut )
        return;

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

    NSString *layout = self.selectedLayout;

    NSMutableDictionary *grid = nil;

    int notesPerColumn = 7;
    int firstNoteRow = 0;
    NSArray <NSString *>*colorsByRow = nil;
    if ( [layout isEqualToString:@"7x8"] )
    {
        grid = [NSMutableDictionary dictionaryWithCapacity:7*8];
        notesPerColumn = 8;
        firstNoteRow = 0;
        colorsByRow = @[@"red", @"orange", @"yellow", @"lime", @"green", @"cyan", @"blue", @"magenta"];
    }
    else if ( [layout isEqualToString:@"7x7"] )
    {
        grid = [NSMutableDictionary dictionaryWithCapacity:7*7];
        firstNoteRow = 1;
        colorsByRow = @[@"off", @"red", @"orange", @"yellow", @"lime", @"green", @"blue", @"magenta"];
    }
    else
    {
        colorsByRow = nil;
    }

    NSDictionary <NSString *, NSNumber *>*linnColorsByName = self.linnstrumentColorsByName;
    NSMutableDictionary *cell = [NSMutableDictionary dictionary];

    // Row is bottom up, col is left right
    // Incoming data from Linnstrument is 1 based x/y, color setting data is 0 based x/y.
    for ( int y = 0; y < 8; y++ )
    {
        // Big Linnstrument has 21 columns.
        for ( int x = 0; x < 21; x++ )
        {
            [cell removeAllObjects];
            cell[@"y"] = @(y);
            cell[@"x"] = @(x);

            setRow.dataByte2 = y;
            setCol.dataByte2 = x+1;
            setColor.dataByte2 = linnColorsByName[colorsByRow[y]].intValue;// Color

            if ( y < firstNoteRow )
            {
                cell[@"type"] = @"ribbon";
            }
            else
            {
                cell[@"type"] = @"note";

                int note = (x * notesPerColumn + y);
                int channel = note / 127 + 1;

                int channelNote = note;
                if ( channel > 0 )
                    channelNote = (note % (channel * 127)) - 1;

                cell[@"note"] = @(channelNote);
                cell[@"channel"] = @(channel);
                cell[@"index"] = @(note);
            }

            cell[@"colorName"] = colorsByRow[y];
            cell[@"color"] = linnColorsByName[colorsByRow[y]];
            cell[@"color-setting-messages"] = @[[setCol copy], [setRow copy], [setColor copy]];

            grid[[NSString stringWithFormat:@"%dx%d", x, y]] = [cell copy];
        }
    }

    self.grid = grid;
    for ( NSDictionary <NSString *, NSString *>*cell in self.grid.allValues )
    {
        NSArray *colorSettings = (NSArray <SMMessage *>*)cell[@"color-setting-messages"];
        if ( colorSettings )
        {
            [settings addObjectsFromArray:colorSettings];
        }
    }

    // NSLog(@"settings: %@", settings);

    // NSLog(@"messages: %@ to outstream %@", [setColorMessages valueForKey:@"dataForDisplay"], linnstrumentOutStream);

    NSLog(@"setting up user mode and random colors");
    [self.linnstrumentOut takeMIDIMessages:settings];

    self.linnstrumentInUserMode = YES; // TODO verify with a quick communication
    self.linnstrumentState = [NSMutableDictionary dictionaryWithCapacity:8 * 20];
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
    NSLog( @"received MIDI message: %@ of (%lu)", [messages firstObject], (unsigned long)[messages count] );

    for ( SMMessage *message in messages )
    {
        if ( self.linnstrumentInUserMode )
        {
            [self interpretMessageForCurrentLayout:message];
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

- (NSString *)selectedLayout
{
    NSString *layout = self.linnLayoutsButton.selectedItem.representedObject;
    return layout;
}

- (void)interpretMessageForCurrentLayout:(SMMessage *)message
{
    [self updateLinnstrumentState:message];

    if ( [message matchesMessageTypeMask:SMMessageTypeAllVoiceMask] )
    {
        SMVoiceMessage *voiceMsg = (SMVoiceMessage *)message;
        // For all voice messages — Note Number: Column, Channel: Row

        NSString *coord = [NSString stringWithFormat:@"%dx%d",voiceMsg.dataByte1-1, voiceMsg.channel-1];

        NSDictionary *cell = self.grid[coord];
        if ( cell == nil )
        {
            NSLog(@"no cell: %@ %@", coord, self.grid[coord]);

            return;
        }

        NSLog(@"grid cell: %@ %@", coord, self.grid[coord]);

        if ( voiceMsg.status == SMVoiceMessageStatusNoteOn && [cell[@"type"] isEqualToString:@"note"] )
        {
             SMVoiceMessage *noteOn = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusNoteOn];
             noteOn.channel = 1;
             noteOn.dataByte1 = ((NSNumber *)cell[@"note"]).intValue; // Note
             noteOn.dataByte2 = voiceMsg.dataByte2; // Velocity

            NSLog(@"note: %@ %@", noteOn.channelForDisplay, noteOn.dataForDisplay);
            [self.portOut takeMIDIMessages:@[noteOn]];
        }
        if (voiceMsg.status == SMVoiceMessageStatusNoteOff )
        {

             SMVoiceMessage *noteOff = [[SMVoiceMessage alloc] initWithTimeStamp:SMGetCurrentHostTime() statusByte:SMVoiceMessageStatusNoteOff];
             noteOff.channel = 1;
             noteOff.dataByte1 = ((NSNumber *)cell[@"note"]).intValue; // Note
             noteOff.dataByte2 = voiceMsg.dataByte2; // Velocity

            [self.portOut takeMIDIMessages:@[noteOff]];
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

- (void) MIDISetupChanged:(NSNotification *)note
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self _MIDISetupChanged:note];
    });
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
        }
        else
        {
            [self.linnstrumentIn addEndpoint:linnIn]             ;
            [self.linnstrumentIn setMessageDestination:self];
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

- (IBAction)changeOutput:(id)sender
{
    NSString *outputName = self.availableOutputsButton.selectedItem.representedObject;
    if ( !outputName )
    {
        NSLog(@"no output name on outputs selection");
        return;
    }

    SMDestinationEndpoint *outEndpoint = [SMDestinationEndpoint destinationEndpointWithName:outputName];
    if ( outEndpoint == nil )
    {
        NSLog(@"couldn't connect to output");
    }
    else
    {
        NSLog(@"switched to %@", outputName);
        [self.portOut setEndpoints:[NSSet setWithObject:outEndpoint]];
        self.lastSelectedOutput = outputName;
    }
}

@end

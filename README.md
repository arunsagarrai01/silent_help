# Silent Help - Emergency Assistance Calculator

A disguised calculator application that secretly functions as a Silent Emergency Assistance system.

## Features

### Calculator Functionality
- Fully functional calculator with standard operations
- Clean, Material Design interface
- Looks and behaves exactly like a normal calculator

### Hidden Emergency Features
- **Secret Calculator Pattern**: Enter a specific sequence (default: 123==) to trigger silent emergency
- **Shake Detection**: Shake the phone multiple times to trigger emergency alert
- **Trusted Contacts**: Manage emergency contacts who receive alerts
- **GPS Location**: Automatically includes location in emergency messages
- **Silent Operation**: No visible changes to calculator interface when triggered

### Emergency Triggers
1. **Fake Calculator Trigger**: Secret calculation pattern
2. **Phone Shake Trigger**: Configurable shake count detection
3. **Background Operation**: Works even when app is minimized

## Setup

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Build and run on Android device
4. Add trusted contacts through the hidden menu (three dots in top-left)
5. Configure emergency triggers in settings

## Usage

1. **Normal Use**: Use as a regular calculator
2. **Emergency Access**: Tap the three-dot menu in top-left corner
3. **Silent Emergency**: 
   - Enter secret pattern in calculator, OR
   - Shake phone the configured number of times

## Technical Stack

- **Flutter**: Cross-platform mobile development
- **Sensors**: Accelerometer for shake detection
- **Location Services**: GPS coordinates for emergency alerts
- **Local Storage**: Secure contact and settings storage
- **Background Services**: Continuous monitoring

## Security & Privacy

- All data stored locally on device
- No external servers or cloud dependencies
- Disguised as innocent calculator app
- Silent operation with no visible emergency indicators

## Academic Project

This is a final year BSc (Hons) Software Engineering project demonstrating:
- Mobile app development
- Sensor integration
- Emergency system design
- User experience design
- Security considerations

---

**Important**: This app is designed for emergency situations. Test thoroughly and ensure trusted contacts are aware of the system.

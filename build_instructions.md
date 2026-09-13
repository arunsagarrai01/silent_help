# Build Instructions for Silent Help

## Prerequisites

1. **Flutter SDK**: Install Flutter (latest stable version)
2. **Android Studio**: Install with Android SDK
3. **Android Device**: Physical device recommended for testing sensors

## Setup Steps

1. **Clone and Setup**:
   ```bash
   git clone <repository-url>
   cd silent_help
   flutter pub get
   ```

2. **Android Configuration**:
   - Ensure Android SDK is installed
   - Enable Developer Options on Android device
   - Enable USB Debugging

3. **Build Commands**:
   ```bash
   # Debug build
   flutter build apk --debug
   
   # Release build
   flutter build apk --release
   
   # Install on connected device
   flutter install
   
   # Run in development mode
   flutter run
   ```

## Testing the App

### Calculator Functionality
1. Open the app (appears as "Calculator")
2. Test basic math operations
3. Verify calculator works normally

### Emergency Features
1. **Access Hidden Menu**:
   - Tap the three-dot menu (⋮) in top-left corner
   - Access "Trusted Contacts", "Emergency Triggers", etc.

2. **Add Trusted Contacts**:
   - Go to "Trusted Contacts"
   - Add emergency contacts with names and phone numbers

3. **Configure Emergency Triggers**:
   - Go to "Emergency Triggers" or "App Settings"
   - Set secret calculator pattern (default: 123==)
   - Configure shake detection count (default: 3 shakes)
   - Customize emergency message

4. **Test Emergency System**:
   - Use "Test Emergency System" in settings
   - Try secret pattern: Enter "123==" in calculator
   - Try shake detection: Shake phone 3 times quickly

## Important Notes

- **Permissions**: App will request location and SMS permissions
- **Real Device**: Shake detection requires physical device
- **SMS Testing**: Test with trusted contacts who know about the system
- **Background Operation**: App continues monitoring when minimized

## Troubleshooting

1. **Build Issues**:
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --debug
   ```

2. **Permission Issues**:
   - Check Android settings for app permissions
   - Manually grant location and SMS permissions

3. **Sensor Issues**:
   - Test on physical device (not emulator)
   - Check device has accelerometer sensor

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── contact.dart
│   └── emergency_alert.dart
├── screens/                  # UI screens
│   ├── calculator_screen.dart
│   ├── contacts_screen.dart
│   └── settings_screen.dart
├── services/                 # Business logic
│   ├── emergency_service.dart
│   ├── location_service.dart
│   ├── sensor_service.dart
│   └── storage_service.dart
└── widgets/                  # Reusable widgets
    └── calculator_button.dart
```

## Security Considerations

- All data stored locally on device
- No external network dependencies
- Disguised as innocent calculator app
- Silent operation with no visible emergency indicators
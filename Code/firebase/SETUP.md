# SilentHelp — Firebase Backend Setup

This is the **secondary cloud layer**. The app runs fully (local SOS: shake /
voice / hidden trigger → location → SMS → local history) even if none of this
is configured. Firebase only adds cloud sync, notifications, and admin tooling.

## 0. Prerequisites
- Node.js 20+  (`node -v`)
- Firebase CLI: `npm i -g firebase-tools`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`

## 1. Create the Firebase project
1. Go to console.firebase.google.com → Add project.
2. Add an Android app with package `com.arunsagarrai.example.silent_help`.
   - Download `google-services.json` → place in `android/app/`.
3. (Optional) Add an iOS app → `GoogleService-Info.plist` into `ios/Runner/`.

## 2. Wire the Flutter app to your project
From the `Code/` folder:
```bash
flutterfire configure
```
This overwrites `lib/firebase_options.dart` with your real keys. Until you run
this, the app detects the placeholder and stays in local-only mode.

## 3. Enable services in the console
- Authentication → enable **Anonymous** (and **Email/Password** if you want).
- Firestore Database → create in production mode.
- Cloud Messaging → enabled by default.
- App Check → register providers:
  - Android: **Play Integrity**
  - iOS: **App Attest**
  - For local testing, enable the **debug provider** and register the debug
    token printed in logcat.

## 4. Deploy rules, indexes, functions
From the `firebase/` folder (this directory):
```bash
firebase use <your-project-id>
cd functions && npm install && npm run build && cd ..
firebase deploy --only firestore:rules,firestore:indexes,functions
```

## 5. Make yourself admin (one-time)
After first sign-in, get your UID from the Auth console, then either:
- Use the Admin SDK locally, or
- Temporarily call `setUserRole` from a trusted admin context.
Roles are stored as **custom claims** and can never be set by the client.

## 6. Firestore TTL (privacy retention)
Console → Firestore → TTL → add policy on `emergencyEvents.expireAt`.
The `cleanupExpiredEvents` scheduled function is a backstop.

## Notes
- Never put the Admin SDK service-account key inside the Flutter app.
- Location is coarsened to ~100 m before syncing; phone numbers are never
  synced (store a hash if you need matching).

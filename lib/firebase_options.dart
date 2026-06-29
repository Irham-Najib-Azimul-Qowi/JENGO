import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBd-KtZcZYM6sLP81IXf314F_O7Jz5TTgA',
    appId: '1:781605410912:android:72f6f9fb86af82a97c8b05',
    messagingSenderId: '781605410912',
    projectId: 'jengo-772e8',
    storageBucket: 'jengo-772e8.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBd-KtZcZYM6sLP81IXf314F_O7Jz5TTgA',
    appId: '1:781605410912:ios:72f6f9fb86af82a97c8b05', // Mapped placeholder
    messagingSenderId: '781605410912',
    projectId: 'jengo-772e8',
    storageBucket: 'jengo-772e8.firebasestorage.app',
    iosBundleId: 'com.example.jengo',
  );
}

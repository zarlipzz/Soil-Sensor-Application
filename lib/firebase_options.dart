// File generated for Firebase initialization across Android and Web
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDc2qAJZvE_2zLMJcTrAl10I_ZbgbOAegM',
    appId: '1:179331473264:web:soil_app',
    messagingSenderId: '179331473264',
    projectId: 'phone-soil',
    authDomain: 'phone-soil.firebaseapp.com',
    storageBucket: 'phone-soil.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDc2qAJZvE_2zLMJcTrAl10I_ZbgbOAegM',
    appId: '1:179331473264:android:abebc76eadb9688397b9b5',
    messagingSenderId: '179331473264',
    projectId: 'phone-soil',
    storageBucket: 'phone-soil.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDc2qAJZvE_2zLMJcTrAl10I_ZbgbOAegM',
    appId: '1:179331473264:ios:soil_app',
    messagingSenderId: '179331473264',
    projectId: 'phone-soil',
    storageBucket: 'phone-soil.firebasestorage.app',
  );
}

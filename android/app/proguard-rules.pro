# SQLCipher / SQLite JNI and reflection surface.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-dontwarn net.sqlcipher.**

# WebRTC uses JNI callbacks into Java classes.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# flutter_local_notifications keeps scheduled receivers by name.
-keep class com.dexterous.** { *; }

# CallKit is started by name from the manifest and from a broadcast receiver.
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-dontwarn com.hiennv.flutter_callkit_incoming.**

# Firebase Messaging service is referenced from the manifest.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Kotlin metadata used by plugins reflecting over generated classes.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

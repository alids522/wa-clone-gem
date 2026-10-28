# SQLCipher / SQLite JNI and reflection surface.
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-dontwarn net.sqlcipher.**

# WebRTC uses JNI callbacks into Java classes.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# flutter_local_notifications keeps scheduled receivers by name.
-keep class com.dexterous.** { *; }

# Firebase Messaging service is referenced from the manifest.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Kotlin metadata used by plugins reflecting over generated classes.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

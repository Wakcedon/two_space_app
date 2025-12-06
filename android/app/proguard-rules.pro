## Keep annotations and common libs referenced by transitive dependencies
-keep class com.google.errorprone.** { *; }
-keep class javax.annotation.** { *; }
-keep class org.jspecify.** { *; }

# Tink (cryptography) often references annotations; keep its classes used via reflection
-keep class com.google.crypto.tink.** { *; }

# Keep Appwrite native reflection usages (safe default)
-keep class io.appwrite.** { *; }

# WebRTC libraries - critical for video calls
-keep class org.webrtc.** { *; }
-keep class org.webrtc.voiceengine.** { *; }

# Matrix SDK and dependencies
-keep class im.vector.** { *; }
-keep class org.matrix.** { *; }
-keep class org.java_websocket.** { *; }

# Keep Dart/Flutter JNI bindings
-keep class com.google.dart.** { *; }
-keep class android.** { *; }
-keep class com.flutter.** { *; }

# OkHttp and network libraries
-keep class okhttp3.** { *; }
-keep class javax.net.ssl.** { *; }
-keep class com.squareup.okhttp3.** { *; }

# Keep Retrofit and Gson for API calls
-keep class retrofit2.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.** { *; }

# Suppress warnings from unused dependencies
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn sun.misc.Unsafe
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep model classes for serialization
-keep class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}


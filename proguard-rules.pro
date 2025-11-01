# Temporary keep rules to help R8/ProGuard when needed
# Keep annotations and Tink/Google API classes referenced by some plugins
-keep class com.google.crypto.tink.** { *; }
-keep class com.google.api.client.** { *; }
-keep class javax.annotation.** { *; }
-keep class com.google.errorprone.annotations.** { *; }
# Keep all classes referenced by reflective access (broad, for safety)
-keep class * {
    public *;
}

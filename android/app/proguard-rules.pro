## Keep annotations and common libs referenced by transitive dependencies
-keep class com.google.errorprone.** { *; }
-keep class javax.annotation.** { *; }
-keep class org.jspecify.** { *; }

# Tink (cryptography) often references annotations; keep its classes used via reflection
-keep class com.google.crypto.tink.** { *; }

# Keep Appwrite native reflection usages (safe default)
-keep class io.appwrite.** { *; }

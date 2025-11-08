plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.synapse.two_space_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.synapse.two_space_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Disable code shrinking/minification temporarily to avoid R8 missing
            // classes issues caused by transitive dependencies. This keeps the
            // release build simpler while we fix dependency proguard rules.
            isMinifyEnabled = false
            isShrinkResources = false
            // Keep proguard rules file available for future use
            proguardFiles("${project.rootDir}/proguard-rules.pro")
        }
    }

    // Packaging options: avoid failures when multiple input AARs/JARs include
    // the same META-INF entries (happens with some dependency bundles). We
    // prefer the first occurrence for harmless metadata files.
    packagingOptions {
        resources {
            excludes += "META-INF/DEPENDENCIES"
            excludes += "META-INF/LICENSE"
            excludes += "META-INF/LICENSE.txt"
            excludes += "META-INF/NOTICE"
            excludes += "META-INF/NOTICE.txt"
            pickFirsts += "META-INF/com/android/build/gradle/app-metadata.properties"
        }
    }
}

flutter {
    source = "../.."
}

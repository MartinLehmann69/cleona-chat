import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "chat.cleona.cleona"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "chat.cleona.cleona"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Only include arm64-v8a and x86_64 (emulator). Skip armeabi-v7a (32-bit, EOL).
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    flavorDimensions += "channel"
    productFlavors {
        create("live") {
            dimension = "channel"
            // Live: chat.cleona.cleona (unchanged)
            resValue("string", "app_name", "Cleona Chat")
        }
        create("beta") {
            dimension = "channel"
            applicationIdSuffix = ".beta"
            // Beta: chat.cleona.cleona.beta — parallel installierbar
            resValue("string", "app_name", "Cleona Beta")
        }
    }

    // S406-DELTA, owner decision 07.10.2026 E-D1 B (v4_2 §26.6.2): the Dart
    // kernel of a debug/beta build is stored UNCOMPRESSED. Deflated, any
    // change rewrites the compressed stream from the first changed byte on,
    // and the update delta 4.2.1 -> 4.2.2 was 33.6 MB; stored, the same change
    // is a few KB. Price: the APK grows by the deflate gain of this one entry
    // (measured in the S406-DELTA session report). Release builds carry no
    // kernel_blob.bin (AOT `lib/<abi>/libapp.so`, stored anyway), so the entry
    // only matters for beta. Gate: scripts/check-apk-kernel-stored.sh.
    androidResources {
        noCompress += "kernel_blob.bin"
    }

    packaging {
        // Exclude Vulkan validation layer (debug artifact, ~15 MB)
        jniLibs.excludes += "lib/*/libVkLayer_khronos_validation.so"
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // CameraX for video capture (Phase 3b)
    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("com.google.guava:guava:32.1.3-android")
    // OS Keyring: EncryptedSharedPreferences backed by AndroidKeyStore (§3.7)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}

flutter {
    source = "../.."
}

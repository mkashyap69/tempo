import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter passes --dart-define values to Gradle as base64 "KEY=value"
// entries, comma-separated. A store build (TEMPO_STORE=true, see
// lib/src/core/build_info.dart) overlays src/store/AndroidManifest.xml on
// release builds.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
        ?.mapNotNull { it.split("=", limit = 2).takeIf { p -> p.size == 2 } }
        ?.associate { it[0] to it[1] }
        ?: emptyMap()
val storeBuild = dartDefines["TEMPO_STORE"] == "true"

// Release signing from android/key.properties (untracked; CI writes it from
// secrets). Without it, release builds fall back to the debug key so
// `flutter run --release` keeps working locally.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "dev.tempo.tempo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO(launch): move to a reverse domain we own before the first Play
        // upload (L1); also tempoAppId in packages/health_source.
        applicationId = "dev.tempo.tempo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect needs 26.
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }

    if (storeBuild) {
        sourceSets.getByName("release").manifest.srcFile("src/store/AndroidManifest.xml")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.15.0")
    // registerForActivityResult(OpenDocumentTree) for the backup folder.
    implementation("androidx.activity:activity-ktx:1.9.3")
}

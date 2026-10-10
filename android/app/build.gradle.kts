import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") apply false
    // END: FlutterFire Configuration
    // AGP 9 provides Built-in Kotlin; the standalone Kotlin Gradle Plugin is no longer applied.
    id("dev.flutter.flutter-gradle-plugin")
}

apply(plugin = "com.google.gms.google-services")

// 加载签名配置（永久专属固化签名保障独立应用平滑升级）
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}
val rawStoreFile = keystoreProperties.getProperty("storeFile") ?: "purelive-release.jks"
val releaseStoreFile = listOf(
    file(rawStoreFile),
    rootProject.file(rawStoreFile),
    file("purelive-release.jks"),
    rootProject.file("app/purelive-release.jks")
).firstOrNull { it.isFile }

val resolvedKeyAlias = keystoreProperties.getProperty("keyAlias") ?: "purelive"
val resolvedKeyPassword = keystoreProperties.getProperty("keyPassword") ?: "purelive123"
val resolvedStorePassword = keystoreProperties.getProperty("storePassword") ?: "purelive123"
val hasReleaseSigning = releaseStoreFile?.isFile == true && !resolvedKeyAlias.isNullOrBlank()

val requireReleaseSigning =
    providers.gradleProperty("pureLive.requireReleaseSigning").orNull.toBoolean() ||
        providers.gradleProperty("pureLiveRequireReleaseSigning").orNull.toBoolean()
if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException("Release signing is required but release keystore is missing.")
}

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.liwo.purelive"
    buildFeatures {
        buildConfig = true
    }
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    lint {
        disable.add("NullSafeMutableLiveData")
        checkReleaseBuilds = false
        abortOnError = false
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.liwo.purelive"
        // ffmpeg_kit_extended_flutter 0.6.2 ships native binaries with an
        // Android API 26 floor. Advertising an older app floor lets installs
        // succeed on devices where the recording engine cannot be loaded.
        minSdk = 26
        multiDexEnabled = true 
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "纯粹直播 Pro"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = resolvedKeyAlias
                keyPassword = resolvedKeyPassword
                storeFile = releaseStoreFile
                storePassword = resolvedStorePassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
       release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Release key not configured; using the local debug key for a test-only formal-package build.")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                  getDefaultProguardFile("proguard-android-optimize.txt"),
                  file("proguard-rules.pro")
              )
        }
       debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
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

// Flutter's build tasks currently use Project at execution time, while the
// aggregate assemble task captures live AGP Built-in Kotlin variant state.
// Keep Configuration Cache enabled for compatible Android tasks, but make
// every Flutter-owned task plus its aggregate entry explicit so Gradle discards
// them instead of failing or reusing incomplete state.
tasks.matching {
    it.name.contains("flutter", ignoreCase = true) || it.name.startsWith("assemble")
}.configureEach {
    notCompatibleWithConfigurationCache(
        "Flutter Gradle tasks are not yet compatible with AGP Built-in Kotlin state",
    )
}

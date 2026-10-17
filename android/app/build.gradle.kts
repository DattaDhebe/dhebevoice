import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val deviceTestBuild = providers.gradleProperty("dhebeVoiceTestBuild").orNull == "true"
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { stream ->
        keystoreProperties.load(stream)
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dhebe.dhebevoice"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = rootProject.file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.dhebe.dhebevoice"
        resValue("string", "app_name", "DhebeVoice")
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "com.dhebe.dhebevoice.SpeechRuntimeBenchmark"
    }

    buildTypes {
        debug {
            if (deviceTestBuild) {
                applicationIdSuffix = ".test"
                resValue("string", "app_name", "DhebeVoice Test")
            }
        }
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.24.3")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("com.microsoft.onnxruntime:onnxruntime:1.24.3")
    androidTestImplementation("androidx.core:core-ktx:1.15.0")
}

// Older Android Studio JBRs bundle a Windows C++ runtime incompatible with ONNX.
// A newer local Java executable can be used for JVM tests without changing the Android build JDK.
tasks.withType<org.gradle.api.tasks.testing.Test>().configureEach {
    System.getenv("DHEBEVOICE_TEST_JAVA")?.let { executable = it }
}

// JVM/debug tests do not run R8, so also inspect the actual release mapping.
val verifyReleaseOnnxBindings by tasks.registering {
    group = "verification"
    description = "Verify that release optimization preserves ONNX JNI bindings."
    dependsOn(tasks.matching { it.name == "minifyReleaseWithR8" })
    onlyIf { android.buildTypes.getByName("release").isMinifyEnabled }
    val mapping = layout.buildDirectory.file("outputs/mapping/release/mapping.txt")
    inputs.file(mapping)
    doLast {
        val classes = mapping.get().asFile.useLines { lines ->
            lines.filter { it.startsWith("ai.onnxruntime.") && it.endsWith(":") }
                .map { it.removeSuffix(":").split(" -> ") }
                .filterNot { it[0].contains("\$\$ExternalSynthetic") }
                .associate { it[0] to it[1] }
        }
        val required = listOf(
            "ai.onnxruntime.OnnxTensor",
            "ai.onnxruntime.TensorInfo",
            "ai.onnxruntime.OnnxJavaType",
            "ai.onnxruntime.OrtException",
            "ai.onnxruntime.OrtSession",
            "ai.onnxruntime.OrtEnvironment",
            "ai.onnxruntime.NodeInfo",
            "ai.onnxruntime.ValueInfo",
        )
        check(required.all { classes[it] == it } && classes.all { it.key == it.value }) {
            "ONNX JNI classes were removed or renamed. Check app/proguard-rules.pro before releasing."
        }
        logger.lifecycle("Verified release ONNX JNI bindings retain their original class names.")
    }
}

tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }.configureEach {
    dependsOn(verifyReleaseOnnxBindings)
}

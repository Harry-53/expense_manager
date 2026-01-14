plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Logic: namespace must use = and double quotes in KTS
    namespace = "com.example.expense_manager"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        // Logic: KTS requires = for boolean flags and JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.expense_manager"
        // Logic: Function calls like minSdkVersion() need parentheses ()
        minSdkVersion(24) 
        targetSdkVersion(34)
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
        
        multiDexEnabled = true
    }

    buildTypes {
        getByName("release") {
            // Logic: KTS syntax for release signing
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Logic: This is the correct way to add desugaring in a .kts file
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
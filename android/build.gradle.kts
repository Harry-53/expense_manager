// Use Case: The root-level build file for the entire Android project.
// Essence: Configures the repositories and plugins needed to build the APK.

buildscript {
    // Variable: repositories | Use Case: Tells Gradle where to find the Android tools.
    repositories {
        google()
        mavenCentral()
    }

    // Variable: dependencies | Use Case: Defines the build-time libraries.
    dependencies {
        // Essence: The Android Gradle Plugin (AGP) version. 
        // 8.1.0 is stable for Java 17/Flutter projects.
        classpath("com.android.tools.build:gradle:8.1.0")
        
        // Essence: The Kotlin compiler used to compile the Biometric and SMS bridge code.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.8.22")
    }
}

allprojects {
    // Use Case: Ensures all sub-modules (like telephony and local_auth) download from stable sources.
    repositories {
        google()
        mavenCentral()
    }
}

// Variable: rootProject.buildDir | Use Case: Defines where the S23 APK and temporary files are stored.
rootProject.buildDir = file("../build")

subprojects {
    // Logic: Ensures every package (like shared_preferences) builds in its own subfolder.
    project.buildDir = file("${rootProject.buildDir}/${project.name}")
}

subprojects {
    // Essence: Forces all plugins to use a consistent evaluation order.
    project.evaluationDependsOn(":app")
}

// Function: clean | Use Case: Allows you to run './gradlew clean' to wipe old S23 build cache.
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
// Use Case: Fix for "Namespace not specified" in telephony/older plugins
// Essence: Injects namespace immediately or post-evaluation to satisfy AGP 8.1.0
subprojects {
    val project = this
    project.evaluationDependsOn(":app")
    fun applyNamespaceFix() {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as? com.android.build.gradle.BaseExtension
            android?.let {
                if (it.namespace == null) {
                    it.namespace = project.group.toString()
                }
            }
        }
    }

    if (project.state.executed) {
        applyNamespaceFix()
    } else {
        project.afterEvaluate { applyNamespaceFix() }
    }
}

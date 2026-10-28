allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (file_picker 8.x among them) still pin their own compileSdk 34,
// while current AndroidX artifacts such as flutter_plugin_android_lifecycle
// require 36. Compile every Android library module against the SDK the app uses
// so the release AAR metadata check passes.
subprojects {
    afterEvaluate {
        val androidExtension =
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
        if (androidExtension != null) {
            androidExtension.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Add annotation libraries as buildscript dependencies so R8 sees them during
// minification. Some transitive dependencies (e.g. Tink) reference annotation
// classes that may not be present in the final apk without explicit inclusion.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.errorprone:error_prone_annotations:2.17.0")
        classpath("com.google.code.findbugs:jsr305:3.0.2")
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

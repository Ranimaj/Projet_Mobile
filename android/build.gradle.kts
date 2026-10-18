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

// Plusieurs plugins (file_picker, connectivity_plus, firebase_auth, geocoding,
// flutter_image_compress, jni) compilent encore contre l'API 33/34/35 alors
// que flutter_plugin_android_lifecycle exige l'API 36 : AGP refuse alors le
// build (« checkDebugAarMetadata »). On aligne tous les modules Android sur le
// compileSdk de l'application. Cela ne change ni minSdk ni targetSdk.
val requiredCompileSdk = 36
subprojects {
    fun Project.alignCompileSdk() {
        extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.let { android ->
            if ((android.compileSdk ?: 0) < requiredCompileSdk) {
                android.compileSdk = requiredCompileSdk
            }
        }
    }
    // `:app` est déjà évalué à ce stade (evaluationDependsOn ci-dessus) ;
    // les modules de plugins ne le sont pas encore.
    if (state.executed) alignCompileSdk() else afterEvaluate { alignCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

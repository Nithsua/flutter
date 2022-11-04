// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// import org.gradle.kotlin.dsl.`kotlin-dsl`

// Apply the plugin
apply<FlutterPluginKts>()

class FlutterPluginKts : Plugin<Project> {
    override fun apply(project: Project) {
        project.withGroovyBuilder {
            getProperty("android").withGroovyBuilder {
                getProperty("defaultConfig").withGroovyBuilder {
                    if (project.hasProperty("multidex-enabled") &&
                        project.property("multidex-enabled").toString().toBoolean() &&
                        getProperty("minSdkVersion").toString().toInt() <= 20) {
                        setProperty("multiDexEnabled", true)
                        getProperty("manifestPlaceholders").withGroovyBuilder {
                            setProperty("applicationName", "io.flutter.app.FlutterMultiDexApplication")
                        }
                    } else {
                        var baseApplicationName: String = "android.app.Application"
                        if (project.hasProperty("base-application-name")) {
                            baseApplicationName = project.property("base-application-name").toString()
                        }
                        // Setting to android.app.Application is the same as omitting the attribute.
                        getProperty("manifestPlaceholders").withGroovyBuilder {
                            setProperty("applicationName", baseApplicationName)
                        }
                    }
                }
            }
        }
    }
}
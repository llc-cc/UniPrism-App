package com.example.uniprism_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uniprism/auth_storage")
        channel.setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences("uniprism_auth", MODE_PRIVATE)
            when (call.method) {
                "read" -> result.success(
                    mapOf(
                        "uniprism.token" to preferences.getString("uniprism.token", null),
                        "uniprism.user" to preferences.getString("uniprism.user", null),
                        "uniprism.anonymousId" to preferences.getString("uniprism.anonymousId", null),
                        "uniprism.anonymousCookie" to preferences.getString("uniprism.anonymousCookie", null),
                        "uniprism.exploreSessionId" to preferences.getString("uniprism.exploreSessionId", null),
                    ),
                )
                "write" -> {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val editor = preferences.edit()
                    listOf("uniprism.token", "uniprism.user", "uniprism.anonymousId", "uniprism.anonymousCookie", "uniprism.exploreSessionId").forEach { key ->
                        if (!values.containsKey(key)) return@forEach
                        val value = values[key] as? String
                        if (value.isNullOrEmpty()) editor.remove(key) else editor.putString(key, value)
                    }
                    editor.apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

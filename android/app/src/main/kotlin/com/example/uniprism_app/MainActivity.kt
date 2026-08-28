package com.example.uniprism_app

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

private const val AUTH_CHANNEL = "uniprism/auth_storage"
private const val REPORT_CHANNEL = "uniprism/report_notifications"
private const val REPORT_PREFERENCES = "uniprism_report_notifications"
private const val NOTIFICATION_CHANNEL_ID = "report_generation"
private const val NOTIFICATION_CHANNEL_NAME = "报告生成通知"
private const val REPORT_READY_ACTION = "com.example.uniprism_app.REPORT_READY"
private const val MESSAGE_READY_ACTION = "com.example.uniprism_app.MESSAGE_READY"
private const val EXTRA_MESSAGE_ID = "uniprism.messageId"
private const val EXTRA_MESSAGE_SOURCE = "uniprism.messageSource"
private const val EXTRA_MESSAGE_ROUTE = "uniprism.messageRoute"
private const val EXTRA_REPORT_ID = "uniprism.reportId"
private const val EXTRA_NOTIFICATION_TYPE = "uniprism.notificationType"
private const val NOTIFICATION_TYPE_REPORT_READY = "report_ready"
private const val NOTIFICATION_PERMISSION_REQUEST = 4102

class MainActivity : FlutterActivity() {
    private var reportChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val authChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTH_CHANNEL)
        authChannel.setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences("uniprism_auth", MODE_PRIVATE)
            when (call.method) {
                "read" -> result.success(
                    mapOf(
                        "uniprism.token" to preferences.getString("uniprism.token", null),
                        "uniprism.user" to preferences.getString("uniprism.user", null),
                        "uniprism.anonymousId" to preferences.getString("uniprism.anonymousId", null),
                        "uniprism.anonymousCookie" to preferences.getString("uniprism.anonymousCookie", null),
                        "uniprism.exploreSessionId" to preferences.getString("uniprism.exploreSessionId", null),
                        "uniprism.messages" to preferences.getString("uniprism.messages", null),
                        "uniprism.agentChatSessions.v1" to preferences.getString("uniprism.agentChatSessions.v1", null),
                        "uniprism.privacyAcceptedVersion" to preferences.getString("uniprism.privacyAcceptedVersion", null),
                        "uniprism.practiceParticipantToken" to preferences.getString("uniprism.practiceParticipantToken", null),
                    ),
                )
                "write" -> {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val editor = preferences.edit()
                    listOf("uniprism.token", "uniprism.user", "uniprism.anonymousId", "uniprism.anonymousCookie", "uniprism.exploreSessionId", "uniprism.messages", "uniprism.agentChatSessions.v1", "uniprism.privacyAcceptedVersion", "uniprism.practiceParticipantToken").forEach { key ->
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

        ReportNotifications.createChannel(this)
        reportChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REPORT_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "scheduleReportReady" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val reportId = arguments?.get("reportId")?.toString().orEmpty()
                        val title = arguments?.get("title")?.toString().orEmpty()
                        val body = arguments?.get("body")?.toString().orEmpty()
                        val delaySeconds = (arguments?.get("delaySeconds") as? Number)?.toLong() ?: 20L
                        if (reportId.isBlank()) {
                            result.error("invalid_report", "缺少报告编号", null)
                        } else {
                            result.success(
                                ReportNotifications.schedule(
                                    context = this,
                                    reportId = reportId,
                                    title = title.ifBlank { "你的测评报告已生成" },
                                    body = body.ifBlank { "点击查看完整报告和专业推荐" },
                                    delaySeconds = delaySeconds.coerceAtLeast(1L),
                                ),
                            )
                        }
                    }
                    "readTaskState" -> result.success(ReportNotifications.readTaskState(this))
                    "scheduleMessageNotification" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val messageId = arguments?.get("messageId")?.toString().orEmpty()
                        val source = arguments?.get("source")?.toString().orEmpty()
                        val title = arguments?.get("title")?.toString().orEmpty()
                        val body = arguments?.get("body")?.toString().orEmpty()
                        val route = arguments?.get("route")?.toString().orEmpty()
                        val delaySeconds = (arguments?.get("delaySeconds") as? Number)?.toLong() ?: 10L
                        if (messageId.isBlank() || title.isBlank() || body.isBlank()) {
                            result.error("invalid_message", "消息参数不完整", null)
                        } else {
                            result.success(
                                ReportNotifications.scheduleMessage(
                                    context = this,
                                    messageId = messageId,
                                    source = source.ifBlank { "local" },
                                    title = title,
                                    body = body,
                                    route = route.ifBlank { "/messages" },
                                    delaySeconds = delaySeconds.coerceAtLeast(1L),
                                ),
                            )
                        }
                    }
                    "consumeLaunchPayload" -> result.success(consumeNotificationPayload(intent))
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_in_progress", "通知权限正在申请中", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeNotificationPayload(intent)?.let { payload ->
            reportChannel?.invokeMethod("notificationTapped", payload)
        }
    }

    private fun consumeNotificationPayload(source: Intent?): Map<String, String>? {
        val reportId = source?.getStringExtra(EXTRA_REPORT_ID).orEmpty()
        val messageId = source?.getStringExtra(EXTRA_MESSAGE_ID).orEmpty()
            .ifBlank { if (reportId.isBlank()) "" else "report-$reportId" }
        if (messageId.isBlank()) return null
        val type = source?.getStringExtra(EXTRA_NOTIFICATION_TYPE)
            ?: if (reportId.isBlank()) "message" else NOTIFICATION_TYPE_REPORT_READY
        val messageSource = source?.getStringExtra(EXTRA_MESSAGE_SOURCE) ?: "local"
        val route = source?.getStringExtra(EXTRA_MESSAGE_ROUTE)
            ?: if (reportId.isBlank()) "/messages" else "/report-result"
        source?.removeExtra(EXTRA_MESSAGE_ID)
        source?.removeExtra(EXTRA_MESSAGE_SOURCE)
        source?.removeExtra(EXTRA_MESSAGE_ROUTE)
        source?.removeExtra(EXTRA_REPORT_ID)
        source?.removeExtra(EXTRA_NOTIFICATION_TYPE)
        return buildMap {
            put("type", type)
            put("messageId", messageId)
            put("source", messageSource)
            put("route", route)
            if (reportId.isNotBlank()) put("reportId", reportId)
        }
    }
}

class ReportReadyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reportId = intent.getStringExtra(EXTRA_REPORT_ID).orEmpty()
        if (reportId.isBlank()) return

        val title = intent.getStringExtra("title") ?: "你的测评报告已生成"
        val body = intent.getStringExtra("body") ?: "点击查看完整报告和专业推荐"
        ReportNotifications.markCompleted(context, reportId)
        InternalMessages.add(
            context = context,
            id = "report-$reportId",
            source = "report",
            title = title,
            body = body,
            route = "/report-result",
            reportId = reportId,
        )
        ReportNotifications.showCompletedNotification(context, reportId, title, body)
    }
}

class MessageNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val messageId = intent.getStringExtra(EXTRA_MESSAGE_ID).orEmpty()
        if (messageId.isBlank()) return
        val source = intent.getStringExtra(EXTRA_MESSAGE_SOURCE) ?: "local"
        val title = intent.getStringExtra("title") ?: "万有棱镜"
        val body = intent.getStringExtra("body") ?: "你有一条新消息"
        val route = intent.getStringExtra(EXTRA_MESSAGE_ROUTE) ?: "/messages"
        InternalMessages.add(context, messageId, source, title, body, route, null)
        ReportNotifications.showMessageNotification(
            context = context,
            messageId = messageId,
            source = source,
            title = title,
            body = body,
            route = route,
        )
    }
}

private object InternalMessages {
    private const val STORAGE_KEY = "uniprism.messages"
    private const val MAX_MESSAGES = 100

    fun add(
        context: Context,
        id: String,
        source: String,
        title: String,
        body: String,
        route: String,
        reportId: String?,
    ) {
        val preferences = context.getSharedPreferences("uniprism_auth", Context.MODE_PRIVATE)
        val existing = try {
            JSONArray(preferences.getString(STORAGE_KEY, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        val next = JSONArray()
        next.put(
            JSONObject().apply {
                put("id", id)
                put("source", source)
                put("title", title)
                put("body", body)
                put("route", route)
                put("createdAt", System.currentTimeMillis())
                put("isRead", false)
                if (!reportId.isNullOrBlank()) put("reportId", reportId)
            },
        )
        for (index in 0 until existing.length()) {
            val item = existing.optJSONObject(index) ?: continue
            if (item.optString("id") == id) continue
            if (next.length() >= MAX_MESSAGES) break
            next.put(item)
        }
        preferences.edit().putString(STORAGE_KEY, next.toString()).apply()
    }
}

private object ReportNotifications {
    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "测评报告生成完成后的提醒"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    fun schedule(
        context: Context,
        reportId: String,
        title: String,
        body: String,
        delaySeconds: Long,
    ): Map<String, Any> {
        createChannel(context)
        val scheduledAt = System.currentTimeMillis()
        val triggerAt = scheduledAt + delaySeconds * 1000L
        val intent = Intent(context, ReportReadyReceiver::class.java).apply {
            action = REPORT_READY_ACTION
            putExtra(EXTRA_REPORT_ID, reportId)
            putExtra("title", title)
            putExtra("body", body)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            reportId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)

        context.getSharedPreferences(REPORT_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString("reportId", reportId)
            .putString("status", "generating")
            .putLong("scheduledAt", scheduledAt)
            .putLong("triggerAt", triggerAt)
            .remove("completedAt")
            .apply()

        return mapOf(
            "reportId" to reportId,
            "status" to "generating",
            "scheduledAt" to scheduledAt,
            "triggerAt" to triggerAt,
        )
    }

    fun scheduleMessage(
        context: Context,
        messageId: String,
        source: String,
        title: String,
        body: String,
        route: String,
        delaySeconds: Long,
    ): Map<String, Any> {
        createChannel(context)
        val scheduledAt = System.currentTimeMillis()
        val triggerAt = scheduledAt + delaySeconds * 1000L
        val intent = Intent(context, MessageNotificationReceiver::class.java).apply {
            action = MESSAGE_READY_ACTION
            putExtra(EXTRA_MESSAGE_ID, messageId)
            putExtra(EXTRA_MESSAGE_SOURCE, source)
            putExtra(EXTRA_MESSAGE_ROUTE, route)
            putExtra("title", title)
            putExtra("body", body)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            messageId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        return mapOf(
            "messageId" to messageId,
            "source" to source,
            "scheduledAt" to scheduledAt,
            "triggerAt" to triggerAt,
        )
    }

    fun markCompleted(context: Context, reportId: String) {
        context.getSharedPreferences(REPORT_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString("reportId", reportId)
            .putString("status", "completed")
            .putLong("completedAt", System.currentTimeMillis())
            .apply()
    }

    fun readTaskState(context: Context): Map<String, Any?> {
        val preferences = context.getSharedPreferences(REPORT_PREFERENCES, Context.MODE_PRIVATE)
        return mapOf(
            "reportId" to preferences.getString("reportId", null),
            "status" to preferences.getString("status", "idle"),
            "scheduledAt" to preferences.getLong("scheduledAt", 0L),
            "triggerAt" to preferences.getLong("triggerAt", 0L),
            "completedAt" to preferences.getLong("completedAt", 0L),
        )
    }

    fun showCompletedNotification(
        context: Context,
        reportId: String,
        title: String,
        body: String,
    ) {
        createChannel(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_MESSAGE_ID, "report-$reportId")
            putExtra(EXTRA_MESSAGE_SOURCE, "report")
            putExtra(EXTRA_MESSAGE_ROUTE, "/report-result")
            putExtra(EXTRA_REPORT_ID, reportId)
            putExtra(EXTRA_NOTIFICATION_TYPE, NOTIFICATION_TYPE_REPORT_READY)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            reportId.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationBuilder(context)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(reportId.hashCode(), builder.build())
    }

    fun showMessageNotification(
        context: Context,
        messageId: String,
        source: String,
        title: String,
        body: String,
        route: String,
    ) {
        createChannel(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_MESSAGE_ID, messageId)
            putExtra(EXTRA_MESSAGE_SOURCE, source)
            putExtra(EXTRA_MESSAGE_ROUTE, route)
            putExtra(EXTRA_NOTIFICATION_TYPE, "message")
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            messageId.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationBuilder(context)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(messageId.hashCode(), builder.build())
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun notificationBuilder(context: Context) =
        Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
}

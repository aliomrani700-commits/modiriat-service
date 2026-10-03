package com.modiriatservice.modiriat_service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "modiriat_service/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleSms" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val timeMillis = call.argument<Number>("timeMillis")?.toLong() ?: 0L
                    if (phone.isBlank() || message.isBlank() || timeMillis <= 0L) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, SmsReceiver::class.java).apply {
                        putExtra("phone", phone)
                        putExtra("message", message)
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        this,
                        id,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

package com.modiriatservice.modiriat_service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "modiriat_service/sms"

    private fun smsIntent(id: Int, phone: String = "", message: String = ""): PendingIntent {
        val intent = Intent(this, SmsReceiver::class.java).apply {
            putExtra("phone", phone)
            putExtra("message", message)
        }
        return PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun sendSmsNow(phone: String, message: String): Boolean {
        if (phone.isBlank() || message.isBlank()) return false
        return try {
            val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = manager.divideMessage(message)
            if (parts.size > 1) {
                manager.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                manager.sendTextMessage(phone, null, message, null, null)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

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
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timeMillis,
                        smsIntent(id, phone, message)
                    )
                    result.success(true)
                }
                "cancelSms" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    alarmManager.cancel(smsIntent(id))
                    result.success(true)
                }
                "sendSmsNow" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    result.success(sendSmsNow(phone, message))
                }
                "saveBackup" -> {
                    val json = call.argument<String>("json") ?: ""
                    val fileName = call.argument<String>("fileName") ?: "modiriat-service-backup.json"
                    if (json.isBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                                put(MediaStore.Downloads.MIME_TYPE, "application/json")
                                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/ModiriatService")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                ?: throw IllegalStateException("Unable to create backup")
                            contentResolver.openOutputStream(uri)?.use { it.write(json.toByteArray(Charsets.UTF_8)) }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            result.success(true)
                        } else {
                            val dir = java.io.File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "ModiriatService")
                            if (!dir.exists()) dir.mkdirs()
                            java.io.File(dir, fileName).writeText(json, Charsets.UTF_8)
                            result.success(true)
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

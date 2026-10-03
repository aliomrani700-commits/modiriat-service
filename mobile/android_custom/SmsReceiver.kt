package com.modiriatservice.modiriat_service

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.util.Log

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (context.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            Log.w("ModiriatService", "SEND_SMS permission missing")
            return
        }
        val phone = intent.getStringExtra("phone") ?: return
        val message = intent.getStringExtra("message") ?: return
        try {
            val sms = SmsManager.getDefault()
            val parts = sms.divideMessage(message)
            if (parts.size > 1) {
                sms.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                sms.sendTextMessage(phone, null, message, null, null)
            }
        } catch (e: Exception) {
            Log.e("ModiriatService", "SMS send failed", e)
        }
    }
}

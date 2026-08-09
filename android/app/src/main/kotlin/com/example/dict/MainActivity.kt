package com.example.dict

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val LOOKUP_CHANNEL = "com.example.dict/process_text"
        private const val LOOKUP_METHOD = "lookupText"
        private const val CHANNEL = "com.example.dict/quick_lookup"
        private const val METHOD_ENABLE = "enable"
        private const val METHOD_DISABLE = "disable"
        private const val METHOD_IS_ENABLED = "isEnabled"
        private const val METHOD_HAS_PERMISSION = "hasPermission"
        private const val REQUEST_NOTIF_PERMISSION = 1001
        private const val PREFS = "quick_lookup"
        private const val KEY_ENABLED = "enabled"
    }

    private var lookupChannel: MethodChannel? = null
    private var pendingLookupText: String? = null
    private var channel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lookupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOOKUP_CHANNEL)
        pendingLookupText?.let {
            lookupChannel?.invokeMethod(LOOKUP_METHOD, it)
            pendingLookupText = null
        }

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD_ENABLE -> handleEnable(result)
                METHOD_DISABLE -> handleDisable(result)
                METHOD_IS_ENABLED -> result.success(isEnabled())
                METHOD_HAS_PERMISSION ->
                    result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                else -> result.notImplemented()
            }
        }
        if (isEnabled()) {
            QuickLookupNotifications.show(this)
        }
    }

    private fun isEnabled(): Boolean =
        getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    private fun handleEnable(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            !NotificationManagerCompat.from(this).areNotificationsEnabled()
        ) {
            pendingPermissionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIF_PERMISSION
            )
        } else {
            QuickLookupNotifications.show(this)
            getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ENABLED, true)
                .apply()
            result.success(true)
        }
    }

    private fun handleDisable(result: MethodChannel.Result) {
        QuickLookupNotifications.hide(this)
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, false)
            .apply()
        result.success(true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIF_PERMISSION) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            QuickLookupNotifications.show(this)
            getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ENABLED, true)
                .apply()
        }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isEnabled()) {
            QuickLookupNotifications.show(this)
        }
        intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
            lookupChannel?.invokeMethod(LOOKUP_METHOD, text)
        }
    }
}

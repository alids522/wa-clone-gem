package com.adoetzchat.messenger

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * [FlutterFragmentActivity] is required by local_auth's BiometricPrompt.
 * FLAG_SECURE keeps message previews out of the recent-apps snapshot and
 * blocks screenshots/recording of the conversation surface.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}

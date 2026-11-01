package com.sudosoc.sudosend

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Owns the Flutter engine for the whole process, not just the Activity.
 * Transfers keep running when the user leaves the app or swipes it away,
 * as long as [TransferService] keeps the process in the foreground.
 */
class SudoSendApp : Application() {
    companion object {
        const val ENGINE_ID = "sudosend-main"
    }

    override fun onCreate() {
        super.onCreate()
        Bridge.app = this
        Notifications.createChannels(this)
        val engine = FlutterEngine(this)
        Bridge.attach(engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}

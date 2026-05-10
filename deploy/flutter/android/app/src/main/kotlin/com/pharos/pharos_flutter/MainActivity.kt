package com.pharos.pharos_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity
//
// Exposes two Flutter channels:
//   MethodChannel  "com.pharos/litert"           — commands (init, analyze, …)
//   EventChannel   "com.pharos/inference_stream" — streaming tokens back to Dart
//
// All blocking work is dispatched to a background thread via the module's
// coroutine scope; results are posted back to the main thread for Flutter.
// ─────────────────────────────────────────────────────────────────────────────
class MainActivity : FlutterActivity() {

    private val methodChannelName = "com.pharos/litert"
    private val eventChannelName  = "com.pharos/inference_stream"

    private val module: PharosLiteRTModule by lazy { PharosLiteRTModule(this) }
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var eventSink: EventChannel.EventSink? = null

    // ── Flutter engine setup ─────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EventChannel — Dart side opens a broadcast stream and receives tokens
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // MethodChannel — Dart side calls invokeMethod(...)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── initialize ──────────────────────────────────────────
                    "initialize" -> {
                        val modelPath = call.argument<String>("modelPath")
                            ?: return@setMethodCallHandler result.error(
                                "MISSING_ARG", "modelPath is required", null)

                        val settings = settingsFromCall(call)

                        module.initialize(
                            modelPath = modelPath,
                            settings  = settings,
                            // Return the backend that was actually used so Dart
                            // can show "Running on CPU (GPU unavailable)" in the UI.
                            onSuccess = { usedCpu ->
                                mainHandler.post {
                                    result.success(
                                        mapOf("usedCpu" to usedCpu,
                                              "backend" to module.activeBackend)
                                    )
                                }
                            },
                            onError = { msg -> mainHandler.post {
                                result.error("INIT_FAILED", msg, null)
                            }},
                        )
                    }

                    // ── analyzeImage ────────────────────────────────────────
                    "analyzeImage" -> {
                        val imageBytes    = call.argument<ByteArray>("imageBytes")
                        val systemPrompt  = call.argument<String>("systemPrompt") ?: ""
                        val userPrompt    = call.argument<String>("userPrompt")   ?: ""

                        if (imageBytes == null) {
                            return@setMethodCallHandler result.error(
                                "MISSING_ARG", "imageBytes is required", null)
                        }

                        module.analyzeImage(
                            imageBytes   = imageBytes,
                            systemPrompt = systemPrompt,
                            userPrompt   = userPrompt,
                            onToken = { token ->
                                mainHandler.post {
                                    eventSink?.success(
                                        mapOf("type" to "token", "value" to token))
                                }
                            },
                            onDone = {
                                mainHandler.post {
                                    eventSink?.success(mapOf("type" to "done"))
                                    result.success(null)
                                }
                            },
                            onError = { msg ->
                                mainHandler.post {
                                    result.error("INFERENCE_FAILED", msg, null)
                                }
                            },
                        )
                    }

                    // ── resetSession ────────────────────────────────────────
                    "resetSession" -> {
                        module.resetSession(settingsFromCall(call))
                        result.success(null)
                    }

                    // ── dispose ─────────────────────────────────────────────
                    "dispose" -> {
                        module.dispose()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun settingsFromCall(call: io.flutter.plugin.common.MethodCall): PharosSettings =
        PharosSettings(
            maxTokens      = call.argument<Int>("maxTokens")         ?: 4096,
            topK           = call.argument<Int>("topK")              ?: 64,
            topP           = (call.argument<Double>("topP")          ?: 0.95).toFloat(),
            temperature    = (call.argument<Double>("temperature")   ?: 1.0).toFloat(),
            enableThinking = call.argument<Boolean>("enableThinking") ?: false,
            useGpu         = call.argument<Boolean>("useGpu")        ?: true,
        )

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onDestroy() {
        module.dispose()
        super.onDestroy()
    }
}

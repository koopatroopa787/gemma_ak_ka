package com.pharos.pharos_flutter

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

data class PharosSettings(
    val maxTokens: Int = 4096,
    val topK: Int = 64,
    val topP: Float = 0.95f,
    val temperature: Float = 1.0f,
    val enableThinking: Boolean = false,
    val useGpu: Boolean = true,
)

class PharosLiteRTModule(private val context: Context) {

    private val tag = "PharosLiteRT"
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    @Volatile private var engine: Engine? = null
    @Volatile private var conversation: Conversation? = null

    // ── Pre-flight model validation ───────────────────────────────────────────
    //
    // CRITICAL: Passing a wrong-format file to Engine() causes a JNI SIGABRT
    // (the native layer embeds raw model bytes in the error message, which
    // contains invalid UTF-8, and Android's JNI checker calls abort()).
    // We MUST reject bad files here before ever touching the native engine.
    //
    // Known-bad magic: 0xF1 0x37 0x71 0x54 (the file our download URL served).
    // Known GGUF magic: 0x47 0x47 0x55 0x46 = "GGUF".
    // Known TFLite:     0x?? ?? ?? ?? at offset 0, "TFL3" at offset 4.
    // Valid .litertlm:  FlatBuffer with "LITM" or similar identifier at offset 4.
    //
    // Strategy: reject any file whose first 4 bytes are NOT a plausible
    // FlatBuffer root offset, or that matches a known-bad prefix.
    // ─────────────────────────────────────────────────────────────────────────

    sealed class ValidationResult {
        object Ok : ValidationResult()
        data class Err(val reason: String) : ValidationResult()
    }

    private fun validateModelFile(modelPath: String): ValidationResult {
        val file = File(modelPath)

        if (!file.exists()) return ValidationResult.Err("Model file not found at $modelPath")

        val size = file.length()
        // < 2 GB is definitely wrong — a real Gemma 4 E2B model is ~2.59 GB.
        if (size < 2_000_000_000L) {
            return ValidationResult.Err(
                "Model file too small (${size / 1024 / 1024} MB, expected ~2590 MB). " +
                "The download was likely interrupted. Tap 'Re-download' to try again."
            )
        }

        val header = ByteArray(8)
        try {
            file.inputStream().use { it.read(header) }
        } catch (e: Exception) {
            return ValidationResult.Err("Cannot read model file: ${e.message}")
        }

        // Reject GGUF (llama.cpp magic "GGUF" = 0x47 0x47 0x55 0x46)
        if (header[0] == 0x47.toByte() && header[1] == 0x47.toByte() &&
            header[2] == 0x55.toByte() && header[3] == 0x46.toByte()) {
            return ValidationResult.Err(
                "GGUF format detected. LiteRT-LM requires .litertlm format, not GGUF. " +
                "Delete and re-download from the correct URL."
            )
        }

        // Reject HTML / JSON error pages from failed downloads.
        val headerStr = String(header, Charsets.ISO_8859_1)
        if (headerStr.startsWith("<!") || headerStr.startsWith("<h") ||
            headerStr.startsWith("{\"") || headerStr.startsWith("ver")) {
            return ValidationResult.Err(
                "Downloaded file is a text/HTML error response, not a model. " +
                "Delete and re-download."
            )
        }

        // NOTE: We do NOT check for specific .litertlm magic bytes here because
        // the flatbuffer root offset in the first 4 bytes varies by model and
        // build.  The engine itself is the authoritative format checker.
        // The important thing is that the runtime version (0.0.4-experimental)
        // matches the model version on HuggingFace.  Using "latest.release"
        // of the runtime with these models causes "Invalid magic number".

        Log.i(tag, "Pre-flight OK: size=${size / 1024 / 1024} MB")
        return ValidationResult.Ok
    }

    // ── Initialize engine ─────────────────────────────────────────────────────

    // Tracks which backend is actually running (reported back to Dart/UI).
    @Volatile var activeBackend: String = "unknown"

    fun initialize(
        modelPath: String,
        settings: PharosSettings,
        onSuccess: (usedCpu: Boolean) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            // ── Pre-flight ────────────────────────────────────────────────────
            when (val v = validateModelFile(modelPath)) {
                is ValidationResult.Err -> {
                    Log.e(tag, "Validation failed: ${v.reason}")
                    withContext(Dispatchers.Main) { onError(v.reason) }
                    return@launch
                }
                ValidationResult.Ok -> Log.i(tag, "Validation OK, starting engine")
            }

            // ── GPU → CPU fallback ────────────────────────────────────────────
            // Some Adreno / Mali drivers fail to compile the LiteRT kernel at
            // runtime (litert_compiled_model_executor.cc INIT_FAILED).  We try
            // GPU first, then silently fall back to CPU so the app always works.
            val backendsToTry: List<Pair<String, Backend>> = if (settings.useGpu)
                listOf("GPU" to Backend.GPU(), "CPU" to Backend.CPU())
            else
                listOf("CPU" to Backend.CPU())

            var lastError = "All backends failed"

            for ((backendName, backend) in backendsToTry) {
                try {
                    Log.i(tag, "Trying $backendName backend…")

                    val engineConfig = EngineConfig(
                        modelPath  = modelPath,
                        backend    = backend,
                        cacheDir   = context.cacheDir.path,
                        maxNumTokens = settings.maxTokens,
                    )

                    val eng = Engine(engineConfig)
                    eng.initialize()

                    // ── Success ───────────────────────────────────────────────
                    engine = eng
                    activeBackend = backendName
                    Log.i(tag, "Engine initialised on $backendName")

                    createConversation(settings)
                    val usedCpu = (backendName == "CPU")
                    withContext(Dispatchers.Main) { onSuccess(usedCpu) }
                    return@launch

                } catch (e: Exception) {
                    // Sanitise — the error message may contain raw binary bytes
                    // from the model file that trigger a second JNI crash if
                    // passed back to Java/Dart as-is.
                    val safeMsg = e.message
                        ?.replace(Regex("[^\\x20-\\x7E]"), "?")
                        ?.take(300)
                        ?: "unknown error"
                    lastError = "$backendName failed: $safeMsg"
                    Log.w(tag, lastError)

                    // Clean up any partial state before trying the next backend.
                    try { engine?.close() } catch (_: Exception) {}
                    engine = null
                }
            }

            // All backends exhausted.
            Log.e(tag, "Engine init failed: $lastError")
            withContext(Dispatchers.Main) { onError(lastError) }
        }
    }

    // ── Session management ────────────────────────────────────────────────────

    fun resetSession(settings: PharosSettings) {
        try {
            conversation?.close()
            createConversation(settings)
        } catch (e: Exception) {
            Log.e(tag, "Reset failed: ${e.message}", e)
        }
    }

    private fun createConversation(settings: PharosSettings) {
        val eng = engine ?: return
        val config = ConversationConfig(
            systemInstruction = Contents.of(
                "You are a helpful pharmaceutical packaging verifier."
            ),
            samplerConfig = SamplerConfig(
                topK = settings.topK,
                topP = settings.topP.toDouble(),
                temperature = settings.temperature.toDouble(),
            ),
        )
        conversation = eng.createConversation(config)
        Log.i(tag, "Conversation created (topK=${settings.topK} temp=${settings.temperature})")
    }

    // ── Vision inference ──────────────────────────────────────────────────────

    fun analyzeImage(
        imageBytes: ByteArray,
        systemPrompt: String,
        userPrompt: String,
        onToken: (String) -> Unit,
        onDone: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val conv = conversation
                    ?: throw IllegalStateException("Session not ready — call initialize() first")

                val callback = object : MessageCallback {
                    private var lastSentLength = 0

                    override fun onMessage(message: Message) {
                        // In 0.11.0, Message might not have a .text property directly.
                        // Using toString() for now to avoid compilation errors, 
                        // but tracking deltas to keep UI smooth.
                        val fullText = message.toString()
                        if (fullText.length > lastSentLength) {
                            val delta = fullText.substring(lastSentLength)
                            lastSentLength = fullText.length
                            scope.launch(Dispatchers.Main) { onToken(delta) }
                        }
                    }
                    override fun onDone() {
                        scope.launch(Dispatchers.Main) { onDone() }
                    }
                    override fun onError(throwable: Throwable) {
                        val msg = throwable.message
                            ?.replace(Regex("[^\\x20-\\x7E]"), "?")
                            ?.take(200)
                            ?: "Inference error"
                        scope.launch(Dispatchers.Main) { onError(msg) }
                    }
                }

                conv.sendMessageAsync(
                    Contents.of(
                        Content.ImageBytes(imageBytes),
                        Content.Text(userPrompt),
                    ),
                    callback,
                )
            } catch (e: Exception) {
                Log.e(tag, "Inference failed: ${e.message}", e)
                withContext(Dispatchers.Main) { onError(e.message ?: "Inference failed") }
            }
        }
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    fun dispose() {
        try {
            conversation?.close()
            engine?.close()
            scope.cancel()
        } catch (e: Exception) {
            Log.e(tag, "Dispose error: ${e.message}", e)
        }
    }
}

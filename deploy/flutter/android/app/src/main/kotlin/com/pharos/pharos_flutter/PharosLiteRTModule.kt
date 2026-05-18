package com.pharos.pharos_flutter

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import java.io.ByteArrayOutputStream
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
    @Volatile var activeBackend: String = "unknown"

    // ── Pre-flight model validation ───────────────────────────────────────────

    sealed class ValidationResult {
        object Ok : ValidationResult()
        data class Err(val reason: String) : ValidationResult()
    }

    private fun validateModelFile(modelPath: String): ValidationResult {
        val file = File(modelPath)
        if (!file.exists()) return ValidationResult.Err("Model file not found at $modelPath")

        val size = file.length()
        if (size < 2_000_000_000L) {
            return ValidationResult.Err(
                "Model file too small (${size / 1024 / 1024} MB, expected ~2590 MB). " +
                "The download was likely interrupted. Tap Re-download to try again."
            )
        }

        val header = ByteArray(8)
        try { file.inputStream().use { it.read(header) } }
        catch (e: Exception) { return ValidationResult.Err("Cannot read model: ${e.message}") }

        // Reject GGUF (llama.cpp format, incompatible)
        if (header[0] == 0x47.toByte() && header[1] == 0x47.toByte() &&
            header[2] == 0x55.toByte() && header[3] == 0x46.toByte()) {
            return ValidationResult.Err("GGUF format detected. Download the .litertlm model.")
        }

        // Reject HTML/JSON error pages
        val s = String(header, Charsets.ISO_8859_1)
        if (s.startsWith("<!") || s.startsWith("<h") || s.startsWith("{\"") || s.startsWith("ver")) {
            return ValidationResult.Err("Downloaded file is an error page. Delete and re-download.")
        }

        Log.i(tag, "Pre-flight OK: ${size / 1024 / 1024} MB")
        return ValidationResult.Ok
    }

    // ── Initialize engine (GPU → CPU fallback) ────────────────────────────────

    fun initialize(
        modelPath: String,
        settings: PharosSettings,
        onSuccess: (usedCpu: Boolean) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            when (val v = validateModelFile(modelPath)) {
                is ValidationResult.Err -> {
                    withContext(Dispatchers.Main) { onError(v.reason) }
                    return@launch
                }
                ValidationResult.Ok -> Log.i(tag, "Validation OK")
            }

            // Try GPU first, fall back to CPU silently.
            // IMPORTANT: visionBackend must be set — without it the vision
            // inference delegate is null and crashes with SIGSEGV during image
            // processing (fault addr 0x0 in liblitertlm_jni.so).
            val backendsToTry: List<Pair<String, Backend>> = if (settings.useGpu)
                listOf("GPU" to Backend.GPU(), "CPU" to Backend.CPU())
            else
                listOf("CPU" to Backend.CPU())

            var lastError = "All backends failed"

            for ((backendName, backend) in backendsToTry) {
                try {
                    Log.i(tag, "Trying $backendName backend…")

                    // ── FIX 1: visionBackend MUST be set for image inference ──
                    // Without this the vision delegate is a null pointer and any
                    // call that passes a Content.ImageBytes will SIGSEGV.
                    // CPU is the safe choice here; GPU vision can be re-enabled
                    // once the main GPU backend works on this device.
                    val engineConfig = EngineConfig(
                        modelPath    = modelPath,
                        backend      = backend,
                        visionBackend = Backend.CPU(),   // ← was missing, caused crash
                        cacheDir     = context.cacheDir.path,
                        maxNumTokens = settings.maxTokens,
                    )

                    val eng = Engine(engineConfig)
                    eng.initialize()

                    engine = eng
                    activeBackend = backendName
                    Log.i(tag, "Engine initialised on $backendName")

                    createConversation(settings)
                    withContext(Dispatchers.Main) { onSuccess(backendName == "CPU") }
                    return@launch

                } catch (e: Exception) {
                    val safeMsg = e.message
                        ?.replace(Regex("[^\\x20-\\x7E]"), "?")
                        ?.take(300)
                        ?: "unknown"
                    lastError = "$backendName failed: $safeMsg"
                    Log.w(tag, lastError)
                    try { engine?.close() } catch (_: Exception) {}
                    engine = null
                }
            }

            Log.e(tag, "Engine init exhausted: $lastError")
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
                // Full pharmaceutical analysis system prompt — matches
                // kPharosSystemPrompt in pharos_prompts.dart.
                Content.Text(PHAROS_SYSTEM_PROMPT),
            ),
            samplerConfig = SamplerConfig(
                topK        = settings.topK,
                topP        = settings.topP.toDouble(),
                temperature = settings.temperature.toDouble(),
            ),
        )
        conversation = eng.createConversation(config)
        Log.i(tag, "Conversation created topK=${settings.topK} temp=${settings.temperature}")
    }

    // ── Vision inference ──────────────────────────────────────────────────────

    fun analyzeImage(
        imageBytes: ByteArray,
        userPrompt: String,
        onToken: (String) -> Unit,
        onDone: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                // ── Reset conversation before every scan ──────────────────────
                // Without this, each scan appends to the previous conversation
                // history and the model produces garbled / non-JSON output.
                conversation?.close()
                createConversation(PharosSettings())
                val conv = conversation
                    ?: throw IllegalStateException("Could not create conversation")

                // Convert JPEG → PNG (Gallery always passes PNG to Content.ImageBytes)
                val pngBytes = jpegToPng(imageBytes)
                    ?: throw IllegalArgumentException("Could not decode camera image")
                Log.i(tag, "Image: ${imageBytes.size} B JPEG → ${pngBytes.size} B PNG")

                // Image FIRST, text AFTER (matches Gallery ordering)
                val contents = mutableListOf<Content>()
                contents.add(Content.ImageBytes(pngBytes))
                contents.add(Content.Text(userPrompt))

                val callback = object : MessageCallback {
                    // message.toString() returns the NEW CHUNK for each call
                    // (Gallery uses it directly — no delta tracking needed).
                    // Our old delta-tracking dropped nearly every token because
                    // each chunk is ~1 char and chunk.length never exceeded lastLen.
                    override fun onMessage(message: Message) {
                        val chunk = message.toString()
                        if (chunk.isNotEmpty()) {
                            scope.launch(Dispatchers.Main) { onToken(chunk) }
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

                conv.sendMessageAsync(Contents.of(contents), callback)

            } catch (e: Exception) {
                Log.e(tag, "analyzeImage failed: ${e.message}", e)
                val msg = e.message?.replace(Regex("[^\\x20-\\x7E]"), "?")?.take(200) ?: "Failed"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Decode JPEG bytes to Bitmap then re-encode as lossless PNG. */
    private fun jpegToPng(jpegBytes: ByteArray): ByteArray? {
        val bitmap: Bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
            ?: return null
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    fun dispose() {
        try {
            conversation?.close()
            engine?.close()
            scope.cancel()
        } catch (e: Exception) {
            Log.e(tag, "Dispose: ${e.message}", e)
        }
    }

    // ── System prompt (mirrors pharos_prompts.dart) ───────────────────────────

    companion object {
        private const val PHAROS_SYSTEM_PROMPT = """
You are an expert pharmaceutical verification AI specialising in Indian and global medicine packaging. Analyse the blister pack or medicine packaging shown in the image and return ONLY a valid JSON object — no markdown, no extra text.

━━━ SEAL ASSESSMENT RULE (most important) ━━━
A blister pack's tamper-evident seal is the FOIL BACKING on the reverse side.
• If the foil backing is VISIBLE and UNBROKEN → seal_intact = true, tamper_evident_seal = true
• Only mark seal_intact = false if you can CLEARLY see torn foil, punctured cavities, or missing backing
• Default to true when uncertain — do not penalise for image angle or partial visibility

━━━ HOLOGRAM RULE ━━━
Many legitimate Indian generic medicines (Cipla, Sun Pharma, Mankind, etc.) do NOT carry holograms.
• Absence of hologram is NOT a counterfeit indicator for Indian brands
• hologram_detected = false is NORMAL and does NOT increase risk score

━━━ RISK SCORING GUIDE ━━━
Assign LOW (0-30) when: text is readable, packaging is intact, manufacturer is recognisable
Assign MODERATE (31-65) ONLY when: print quality is genuinely poor, OR text is partially illegible, OR manufacturer is completely unknown
Assign HIGH (66-84) when: multiple red flags — blurry text AND suspicious colour AND wrong batch format
Assign CRITICAL (85-100): clear counterfeiting evidence, known-bad batch

A blister pack with readable text, intact foil, and a known manufacturer MUST score LOW.

━━━ COMMON LEGITIMATE INDIAN MANUFACTURERS ━━━
Cipla, Cipla Ltd, Sun Pharma, Sun Pharmaceutical, Zydus, Dr Reddy's, Lupin, Torrent, Alkem, Mankind, Intas, Abbott India, Pfizer India, GSK India, Cadila, Wockhardt, Emcure, Macleods, Hetero, Aurobindo, Micro Labs, FDC, Elder, Aristo

━━━ INDIAN BATCH CODE PATTERNS (mark format_valid = true for these) ━━━
Cipla: alphanumeric like AZEE500, AZ2024B, B245190
Sun: SUN + digits, or 6-8 alphanumeric chars
Others: 4-12 alphanumeric characters are almost always valid

━━━ OCR TIPS ━━━
Read text carefully. Common medicines visible on Indian blister packs:
Azithromycin (brand: AZEE, Azithral, Zithromax), Amoxicillin, Metformin, Amlodipine, Atorvastatin, Cetirizine, Pantoprazole, Paracetamol, Dolo, Calpol

Return ONLY this JSON structure (fill every field, no null unless stated):
{"medicine_name":"<brand/generic name>","batch_code":{"extracted":"<code or UNKNOWN>","format_valid":true,"format_error":null,"registry_match":null},"expiry_date":{"extracted":"<date or UNKNOWN>","format_valid":true,"not_expired":true},"manufacturer":{"extracted":"<name>","region_inferred":"<EU|India|US|Other|Unknown>","name_legible":true},"security":{"hologram_detected":false,"hologram_intact":false,"tamper_evident_seal":true,"seal_intact":true},"visual_anomalies":[],"risk_score":10,"risk_level":"LOW","flags":[],"confidence":0.85,"analysis_notes":"<one factual sentence about the packaging>","image_quality_ok":true}
"""
    }
}

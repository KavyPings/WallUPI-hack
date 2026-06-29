package com.example.wallupi.sms

import android.content.Context
import android.util.Log
import org.json.JSONObject
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.FileUtil
import java.io.Closeable

class TinyBertTFLiteClassifier(private val context: Context) : Closeable {

    data class ClassifierConfig(
        val modelAssetPath: String,
        val vocabAssetPath: String,
        val tokenizerAssetPath: String,
        val labels: List<String>,
        val maxSeqLength: Int,
        val lowConfidenceThreshold: Float,
        val uncertainGapThreshold: Float,
        val cloudEscalationMinRisk: Float,
        val flaggedRiskThreshold: Float,
        val ruleHighRiskThreshold: Float
    )

    // Lazy initialization is thread-safe (SYNCHRONIZED mode by default in Kotlin).
    // This ensures the model and tokenizer are loaded at most once, even under concurrent access.
    private val config: ClassifierConfig? by lazy { loadConfig() }

    private val tokenizer: TinyBertTokenizer? by lazy {
        val cfg = config ?: return@lazy null
        try {
            val vocabLines = context.assets.open(cfg.vocabAssetPath)
                .bufferedReader()
                .use { it.readLines() }
            TinyBertTokenizer(vocabLines, cfg.maxSeqLength).takeIf { it.isReady }
        } catch (e: Exception) {
            Log.w(TAG, "Tokenizer vocab load failed: ${e.message}")
            null
        }
    }

    private val interpreter: Interpreter? by lazy {
        val cfg = config ?: return@lazy null
        try {
            val mappedModel = FileUtil.loadMappedFile(context, cfg.modelAssetPath)
            val options = Interpreter.Options().apply {
                setNumThreads(2)
                setUseXNNPACK(true)
            }
            Interpreter(mappedModel, options)
        } catch (e: Exception) {
            Log.w(TAG, "TFLite model load failed: ${e.message}")
            null
        }
    }

    val classifierConfig: ClassifierConfig?
        get() = config

    val modelAvailable: Boolean
        get() = interpreter != null && tokenizer != null

    val vocabAvailable: Boolean
        get() = tokenizer != null

    fun classify(text: String): ModelClassification? {
        val activeInterpreter = interpreter ?: return null
        val activeTokenizer = tokenizer ?: return null
        val activeConfig = config ?: return null

        return try {
            val tokenized = activeTokenizer.tokenize(text)

            // Each input is int[1][maxSeqLength] — batch size 1.
            val inputIds = Array(1) { tokenized.inputIds }
            val attentionMask = Array(1) { tokenized.attentionMask }
            val tokenTypeIds = Array(1) { tokenized.tokenTypeIds }

            val inputCount = activeInterpreter.inputTensorCount
            Log.d(TAG, "Model input count: $inputCount")

            // Output: float[1][numLabels] — logits for each class.
            val output = Array(1) { FloatArray(activeConfig.labels.size) }

            @Suppress("UNCHECKED_CAST")
            val inputs = if (inputCount >= 3) {
                arrayOf(inputIds, attentionMask, tokenTypeIds)
            } else {
                arrayOf(inputIds, attentionMask)
            }

            activeInterpreter.runForMultipleInputsOutputs(
                inputs,
                mapOf(0 to output as Any)
            )

            val probabilities = softmax(output[0])
            val ranked = probabilities.mapIndexed { i, v -> i to v }
                .sortedByDescending { it.second }

            val top = ranked.firstOrNull() ?: return null
            val second = ranked.getOrNull(1)

            ModelClassification(
                label = activeConfig.labels[top.first],
                confidence = top.second,
                runnerUpLabel = second?.let { activeConfig.labels[it.first] },
                runnerUpConfidence = second?.second ?: 0f,
                confidenceGap = top.second - (second?.second ?: 0f)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Inference failed: ${e.message}")
            null
        }
    }

    override fun close() {
        try { interpreter?.close() } catch (_: Exception) {}
    }

    private fun loadConfig(): ClassifierConfig? {
        return try {
            val json = context.assets.open(CONFIG_ASSET_PATH).bufferedReader().use { it.readText() }
            val parsed = JSONObject(json)
            val labelsArray = parsed.getJSONArray("labels")
            val labels = buildList {
                for (i in 0 until labelsArray.length()) add(labelsArray.getString(i))
            }
            ClassifierConfig(
                modelAssetPath = parsed.getString("modelAssetPath"),
                vocabAssetPath = parsed.getString("vocabAssetPath"),
                tokenizerAssetPath = parsed.optString("tokenizerAssetPath", "ml/tokenizer.json"),
                labels = labels,
                maxSeqLength = parsed.optInt("maxSeqLength", 128),
                lowConfidenceThreshold = parsed.optDouble("lowConfidenceThreshold", 0.62).toFloat(),
                uncertainGapThreshold = parsed.optDouble("uncertainGapThreshold", 0.18).toFloat(),
                cloudEscalationMinRisk = parsed.optDouble("cloudEscalationMinRisk", 0.55).toFloat(),
                flaggedRiskThreshold = parsed.optDouble("flaggedRiskThreshold", 0.45).toFloat(),
                ruleHighRiskThreshold = parsed.optDouble("ruleHighRiskThreshold", 0.85).toFloat()
            )
        } catch (e: Exception) {
            Log.w(TAG, "Config load failed: ${e.message}")
            null
        }
    }

    // Numerically stable softmax: subtract max to prevent overflow before exp().
    private fun softmax(values: FloatArray): FloatArray {
        if (values.isEmpty()) return values
        val max = values.maxOrNull() ?: 0f
        val exps = FloatArray(values.size)
        var sum = 0.0
        for (i in values.indices) {
            val exp = kotlin.math.exp((values[i] - max).toDouble())
            exps[i] = exp.toFloat()
            sum += exp
        }
        if (sum == 0.0) return values
        return FloatArray(values.size) { i -> (exps[i] / sum).toFloat() }
    }

    companion object {
        private const val TAG = "TinyBertClassifier"
        private const val CONFIG_ASSET_PATH = "ml/sms_tinybert_config.json"
    }
}

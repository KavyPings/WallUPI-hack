package com.example.wallupi.sms

import java.util.Locale

class TinyBertTokenizer(
    vocabLines: List<String>,
    private val maxSeqLength: Int
) {

    data class TokenizedInput(
        val inputIds: IntArray,
        val attentionMask: IntArray,
        val tokenTypeIds: IntArray,
        val tokens: List<String>
    )

    private val vocab: Map<String, Int> = vocabLines
        .mapIndexed { index, token -> token.trim() to index }
        .filter { it.first.isNotEmpty() }
        .toMap()

    private val clsToken = "[CLS]"
    private val sepToken = "[SEP]"
    private val padToken = "[PAD]"
    private val unkToken = "[UNK]"

    private val clsId = vocab[clsToken] ?: 101
    private val sepId = vocab[sepToken] ?: 102
    private val padId = vocab[padToken] ?: 0
    private val unkId = vocab[unkToken] ?: 100

    val isReady: Boolean
        get() = vocab.isNotEmpty()

    fun tokenize(text: String): TokenizedInput {
        val basicTokens = basicTokenize(text)
        val wordPieces = mutableListOf<String>()
        for (token in basicTokens) {
            wordPieces += wordPieceTokenize(token)
        }

        val truncatedPieces = wordPieces.take((maxSeqLength - 2).coerceAtLeast(0))
        val finalTokens = buildList {
            add(clsToken)
            addAll(truncatedPieces)
            add(sepToken)
        }

        val ids = IntArray(maxSeqLength) { padId }
        val mask = IntArray(maxSeqLength) { 0 }
        val typeIds = IntArray(maxSeqLength) { 0 }

        finalTokens.forEachIndexed { index, token ->
            if (index < maxSeqLength) {
                ids[index] = vocab[token] ?: unkId
                mask[index] = 1
            }
        }

        return TokenizedInput(
            inputIds = ids,
            attentionMask = mask,
            tokenTypeIds = typeIds,
            tokens = finalTokens
        )
    }

    private fun basicTokenize(text: String): List<String> {
        val cleaned = buildString(text.length) {
            for (char in text) {
                when {
                    char.isWhitespace() -> append(' ')
                    char.isISOControl() -> append(' ')
                    else -> append(char)
                }
            }
        }.lowercase(Locale.US)

        val tokens = mutableListOf<String>()
        val current = StringBuilder()

        fun flushCurrent() {
            if (current.isNotEmpty()) {
                tokens += current.toString()
                current.clear()
            }
        }

        for (char in cleaned) {
            when {
                char.isLetterOrDigit() -> current.append(char)
                char == '@' || char == '.' || char == '_' || char == '-' || char == ':' || char == '/' -> current.append(char)
                char.isWhitespace() -> flushCurrent()
                else -> {
                    flushCurrent()
                    tokens += char.toString()
                }
            }
        }
        flushCurrent()
        return tokens.filter { it.isNotBlank() }
    }

    private fun wordPieceTokenize(token: String): List<String> {
        if (vocab.containsKey(token)) return listOf(token)
        if (token.length > 100) return listOf(unkToken)

        val subTokens = mutableListOf<String>()
        var start = 0
        while (start < token.length) {
            var end = token.length
            var currentSubToken: String? = null

            while (start < end) {
                val piece = token.substring(start, end)
                val candidate = if (start == 0) piece else "##$piece"
                if (vocab.containsKey(candidate)) {
                    currentSubToken = candidate
                    break
                }
                end -= 1
            }

            if (currentSubToken == null) {
                return listOf(unkToken)
            }

            subTokens += currentSubToken
            start = end
        }
        return subTokens
    }
}


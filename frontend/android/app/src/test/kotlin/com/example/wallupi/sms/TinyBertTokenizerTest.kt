package com.example.wallupi.sms

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class TinyBertTokenizerTest {

    private val maxSeqLength = 16

    // Minimal vocabulary with special tokens at standard BERT positions.
    private val vocab = listOf(
        "[PAD]",    // 0
        "[UNK]",    // 1
        "[CLS]",    // 2
        "[SEP]",    // 3
        "hello",    // 4
        "world",    // 5
        "this",     // 6
        "is",       // 7
        "a",        // 8
        "test",     // 9
        "##ing",    // 10
        "urgent",   // 11
        "otp",      // 12
        "click",    // 13
        "here",     // 14
        "http",     // 15
        "##s",      // 16
        "send",     // 17
        "money",    // 18
        "now",      // 19
    )

    private lateinit var tokenizer: TinyBertTokenizer

    @Before
    fun setUp() {
        tokenizer = TinyBertTokenizer(vocab, maxSeqLength)
    }

    @Test
    fun `isReady returns true when vocab is populated`() {
        assertTrue(tokenizer.isReady)
    }

    @Test
    fun `isReady returns false for empty vocab`() {
        assertFalse(TinyBertTokenizer(emptyList(), 16).isReady)
    }

    @Test
    fun `output arrays always have length equal to maxSeqLength`() {
        val result = tokenizer.tokenize("hello world")
        assertEquals(maxSeqLength, result.inputIds.size)
        assertEquals(maxSeqLength, result.attentionMask.size)
        assertEquals(maxSeqLength, result.tokenTypeIds.size)
    }

    @Test
    fun `token type ids are always zero for single-sequence input`() {
        val result = tokenizer.tokenize("hello world this is a test")
        result.tokenTypeIds.forEach { assertEquals(0, it) }
    }

    @Test
    fun `CLS token is first and SEP token follows real tokens`() {
        val result = tokenizer.tokenize("hello world")
        assertEquals("[CLS]", result.tokens.first())
        // SEP should be the last real token (last position with mask=1)
        val lastRealIdx = result.attentionMask.indexOfLast { it == 1 }
        assertEquals("[SEP]", result.tokens[lastRealIdx])
    }

    @Test
    fun `attention mask is 1 for real tokens and 0 for padding`() {
        val result = tokenizer.tokenize("hello")
        // CLS + hello + SEP = 3 real tokens
        assertEquals(1, result.attentionMask[0]) // [CLS]
        assertEquals(1, result.attentionMask[1]) // hello
        assertEquals(1, result.attentionMask[2]) // [SEP]
        // everything after is padding
        for (i in 3 until maxSeqLength) {
            assertEquals("Expected pad at position $i", 0, result.attentionMask[i])
        }
    }

    @Test
    fun `empty text produces only CLS and SEP then padding`() {
        val result = tokenizer.tokenize("")
        assertEquals(1, result.attentionMask[0]) // [CLS]
        assertEquals(1, result.attentionMask[1]) // [SEP]
        for (i in 2 until maxSeqLength) {
            assertEquals(0, result.attentionMask[i])
        }
    }

    @Test
    fun `long text is truncated so output stays within maxSeqLength`() {
        // Build text far longer than maxSeqLength tokens
        val longText = "hello world hello world hello world hello world hello world"
        val result = tokenizer.tokenize(longText)
        assertEquals(maxSeqLength, result.inputIds.size)
        // SEP must still be present within the window
        val lastRealIdx = result.attentionMask.indexOfLast { it == 1 }
        assertTrue(lastRealIdx < maxSeqLength)
        assertEquals("[SEP]", result.tokens[lastRealIdx])
    }

    @Test
    fun `known tokens produce valid (non-unknown) ids`() {
        val result = tokenizer.tokenize("hello world")
        val unkId = vocab.indexOf("[UNK]")
        // Position 0 = [CLS], 1 = hello (id=4), 2 = world (id=5)
        assertNotEquals(unkId, result.inputIds[1])
        assertNotEquals(unkId, result.inputIds[2])
    }

    @Test
    fun `text is lowercased before tokenization`() {
        val lower = tokenizer.tokenize("hello")
        val upper = tokenizer.tokenize("HELLO")
        // Both should produce the same token sequence
        assertArrayEquals(lower.inputIds, upper.inputIds)
    }

    @Test
    fun `whitespace-only text behaves like empty text`() {
        val result = tokenizer.tokenize("   ")
        assertEquals(1, result.attentionMask[0]) // [CLS]
        assertEquals(1, result.attentionMask[1]) // [SEP]
        assertEquals(0, result.attentionMask[2]) // PAD
    }

    @Test
    fun `padding positions have pad token id`() {
        val result = tokenizer.tokenize("hello")
        val padId = vocab.indexOf("[PAD]")
        for (i in 3 until maxSeqLength) {
            assertEquals("Expected PAD id at position $i", padId, result.inputIds[i])
        }
    }
}

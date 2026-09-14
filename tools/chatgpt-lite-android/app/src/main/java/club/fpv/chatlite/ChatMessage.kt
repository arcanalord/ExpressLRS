package club.fpv.chatlite

import androidx.compose.runtime.Immutable

@Immutable
data class ChatMessage(
    val id: String,
    val role: String,
    val content: String,
    val createdAt: Long = System.currentTimeMillis(),
)

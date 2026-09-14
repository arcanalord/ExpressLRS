package club.fpv.chatlite

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class ChatViewModel(app: Application) : AndroidViewModel(app) {
    private val store = ChatStore(app)
    private val backend = ChatBackend()

    private val _messages = MutableStateFlow(store.loadMessages())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _streamingText = MutableStateFlow("")
    val streamingText: StateFlow<String> = _streamingText.asStateFlow()

    private val _isStreaming = MutableStateFlow(false)
    val isStreaming: StateFlow<Boolean> = _isStreaming.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _backendUrl = MutableStateFlow(store.backendUrl())
    val backendUrl: StateFlow<String> = _backendUrl.asStateFlow()

    private val _proxyToken = MutableStateFlow(store.proxyToken())
    val proxyToken: StateFlow<String> = _proxyToken.asStateFlow()

    private val _model = MutableStateFlow(store.model())
    val model: StateFlow<String> = _model.asStateFlow()

    private var streamJob: Job? = null
    private var chatEpoch: Long = 0L

    fun saveConfig(backendUrl: String, proxyToken: String, model: String) {
        store.saveConfig(backendUrl, proxyToken, model)
        _backendUrl.value = backendUrl.trim()
        _proxyToken.value = proxyToken.trim()
        _model.value = model.trim().ifBlank { ChatStore.DEFAULT_MODEL }
    }

    fun clearError() {
        _error.value = null
    }

    fun newChat() {
        chatEpoch++
        stop()
        _messages.value = emptyList()
        _streamingText.value = ""
        _isStreaming.value = false
        viewModelScope.launch(Dispatchers.IO) { store.clear() }
    }

    fun stop() {
        streamJob?.cancel()
        streamJob = null
    }

    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || _isStreaming.value) return
        if (_backendUrl.value.isBlank()) {
            _error.value = "Сначала укажи адрес Lite backend в настройках."
            return
        }

        val user = ChatMessage(
            id = UUID.randomUUID().toString(),
            role = "user",
            content = trimmed,
        )
        val nextMessages = _messages.value + user
        _messages.value = nextMessages
        _error.value = null
        persist(nextMessages)

        val epoch = chatEpoch
        streamJob = viewModelScope.launch {
            _isStreaming.value = true
            _streamingText.value = ""
            val builder = StringBuilder(1024)
            var lastPublish = 0L
            try {
                backend.stream(
                    backendUrl = _backendUrl.value,
                    proxyToken = _proxyToken.value,
                    model = _model.value,
                    messages = nextMessages.takeLast(MAX_CONTEXT_MESSAGES),
                )
                    .catch { throw it }
                    .collect { delta ->
                        builder.append(delta)
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastPublish >= UI_FRAME_MS) {
                            _streamingText.value = builder.toString()
                            lastPublish = now
                        }
                    }
            } catch (_: CancellationException) {
                // Stop button is expected cancellation. Keep a partial reply if one exists.
            } catch (t: Throwable) {
                _error.value = t.message ?: "Ошибка сети"
            } finally {
                val finalText = builder.toString()
                if (epoch == chatEpoch && finalText.isNotBlank()) {
                    _streamingText.value = finalText
                    val assistant = ChatMessage(
                        id = UUID.randomUUID().toString(),
                        role = "assistant",
                        content = finalText,
                    )
                    val completed = _messages.value + assistant
                    _messages.value = completed
                    persist(completed)
                }
                if (epoch == chatEpoch) {
                    _streamingText.value = ""
                    _isStreaming.value = false
                }
                streamJob = null
            }
        }
    }

    private fun persist(messages: List<ChatMessage>) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                store.saveMessages(messages)
            } catch (t: Throwable) {
                _error.value = "Не удалось сохранить историю: ${t.message}"
            }
        }
    }

    private companion object {
        const val MAX_CONTEXT_MESSAGES = 20
        const val UI_FRAME_MS = 33L
    }
}

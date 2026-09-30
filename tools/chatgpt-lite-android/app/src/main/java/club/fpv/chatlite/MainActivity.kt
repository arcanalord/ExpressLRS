package club.fpv.chatlite

import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel

class MainActivity : ComponentActivity() {
    private val vm: ChatViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { ChatLiteApp(vm) }
    }
}

@Composable
private fun ChatLiteApp(vm: ChatViewModel = viewModel()) {
    val context = LocalContext.current
    val isDark = !LocalInspectionMode.current &&
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    MaterialTheme(colorScheme = if (isDark) darkColorScheme() else lightColorScheme()) {
        Surface(Modifier.fillMaxSize()) {
            ChatScreen(
                vm = vm,
                onOpenChatGpt = {
                    CustomTabsIntent.Builder()
                        .setShowTitle(true)
                        .build()
                        .launchUrl(context, Uri.parse("https://chatgpt.com/"))
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatScreen(vm: ChatViewModel, onOpenChatGpt: () -> Unit) {
    val messages by vm.messages.collectAsState()
    val isStreaming by vm.isStreaming.collectAsState()
    val error by vm.error.collectAsState()
    val backendUrl by vm.backendUrl.collectAsState()
    val model by vm.model.collectAsState()

    var input by rememberSaveable { mutableStateOf("") }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var visibleCount by rememberSaveable { mutableIntStateOf(DEFAULT_WINDOW) }
    val listState = rememberLazyListState()

    val visibleMessages = remember(messages, visibleCount) { messages.takeLast(visibleCount) }

    LaunchedEffect(messages.size, isStreaming) {
        val loadMoreRow = if (messages.size > visibleMessages.size) 1 else 0
        val target = loadMoreRow + visibleMessages.size + if (isStreaming) 1 else 0
        if (target > 0) listState.scrollToItem(target - 1)
    }

    if (showSettings) {
        AdvancedSettingsDialog(
            backendUrl = backendUrl,
            model = model,
            onDismiss = { showSettings = false },
            onSave = { url, selectedModel ->
                vm.saveConfig(url, "", selectedModel)
                showSettings = false
            },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Chat Lite")
                        Text(
                            if (backendUrl.isBlank()) "вход по аккаунту" else "нативный Lite · $model",
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                },
                actions = {
                    TextButton(onClick = { showSettings = true }) { Text("Расширенные") }
                    if (backendUrl.isNotBlank()) TextButton(onClick = vm::newChat) { Text("Новый") }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).imePadding(),
        ) {
            if (backendUrl.isBlank()) {
                AccountModeCard(onOpenChatGpt, onAdvanced = { showSettings = true })
                Box(Modifier.weight(1f).fillMaxWidth())
            } else {
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (messages.size > visibleMessages.size) {
                            item(key = "__load_more__") {
                                OutlinedButton(
                                    onClick = { visibleCount += WINDOW_STEP },
                                    modifier = Modifier.fillMaxWidth(),
                                ) { Text("Показать ещё ${minOf(WINDOW_STEP, messages.size - visibleMessages.size)} сообщений") }
                            }
                        }

                        items(items = visibleMessages, key = { it.id }, contentType = { it.role }) { message ->
                            MessageBubble(message)
                        }

                        if (isStreaming) {
                            item(key = "__streaming__", contentType = "streaming") { StreamingBubble(vm) }
                        }
                    }
                }

                error?.let { message ->
                    Card(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(message, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                            TextButton(onClick = vm::clearError) { Text("OK") }
                        }
                    }
                }

                Composer(
                    value = input,
                    onValueChange = { input = it },
                    isStreaming = isStreaming,
                    onSend = {
                        val send = input
                        input = ""
                        vm.send(send)
                    },
                    onStop = vm::stop,
                )
            }
        }
    }
}

@Composable
private fun AccountModeCard(onOpenChatGpt: () -> Unit, onAdvanced: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Вход по аккаунту", style = MaterialTheme.typography.titleMedium)
            Text(
                "Chat Lite откроет ChatGPT в защищённой вкладке Chrome. Она использует ту же браузерную сессию, в которой ты уже вошёл. Само Android-приложение не получает пароль, cookie или токен аккаунта.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                "Это единственный режим, который использует твою обычную подписку ChatGPT. Нативный API-режим оплачивается отдельно и не связан с подпиской.",
                style = MaterialTheme.typography.bodySmall,
            )
            Button(onClick = onOpenChatGpt, modifier = Modifier.fillMaxWidth()) {
                Text("Открыть ChatGPT по аккаунту")
            }
            TextButton(onClick = onAdvanced) { Text("Расширенный нативный режим") }
        }
    }
}

@Composable
private fun MessageBubble(message: ChatMessage) {
    val user = message.role == "user"
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (user) Arrangement.End else Arrangement.Start,
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(if (user) 0.86f else 0.96f),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (user) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
            ),
        ) {
            SelectionContainer {
                Text(message.content, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun StreamingBubble(vm: ChatViewModel) {
    val text by vm.streamingText.collectAsState()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start) {
        Card(
            modifier = Modifier.fillMaxWidth(0.96f),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Text(if (text.isEmpty()) "…" else text, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun Composer(
    value: String,
    onValueChange: (String) -> Unit,
    isStreaming: Boolean,
    onSend: () -> Unit,
    onStop: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.weight(1f),
            minLines = 1,
            maxLines = 6,
            placeholder = { Text("Сообщение") },
            enabled = !isStreaming,
        )
        Spacer(Modifier.width(8.dp))
        if (isStreaming) {
            Button(
                onClick = onStop,
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
            ) { Text("Стоп") }
        } else {
            Button(onClick = onSend, enabled = value.isNotBlank()) { Text("→") }
        }
    }
}

@Composable
private fun AdvancedSettingsDialog(
    backendUrl: String,
    model: String,
    onDismiss: () -> Unit,
    onSave: (String, String) -> Unit,
) {
    var url by remember(backendUrl) { mutableStateOf(backendUrl) }
    var selectedModel by remember(model) { mutableStateOf(model) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Расширенный нативный режим") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Не нужен для входа по аккаунту. Этот режим работает через отдельный backend/API и оплачивается отдельно от подписки ChatGPT. API-ключ в APK не хранится.",
                    style = MaterialTheme.typography.bodySmall,
                )
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    label = { Text("Backend URL") },
                    placeholder = { Text("https://example.vercel.app") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = selectedModel,
                    onValueChange = { selectedModel = it },
                    label = { Text("Модель") },
                    singleLine = true,
                )
                Text(
                    "Быстро: openai/gpt-5.6-luna-fast\nСильнее: openai/gpt-5.6-sol",
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                )
                TextButton(onClick = { onSave("", selectedModel) }) { Text("Отключить нативный режим") }
            }
        },
        confirmButton = { Button(onClick = { onSave(url, selectedModel) }) { Text("Сохранить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

private const val DEFAULT_WINDOW = 40
private const val WINDOW_STEP = 40

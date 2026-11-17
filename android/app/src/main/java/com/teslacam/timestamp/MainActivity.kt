package com.teslacam.timestamp

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.HapticFeedbackConstants
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.DefaultItemAnimator
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.teslacam.timestamp.data.ClipFile
import com.teslacam.timestamp.data.TimeFormats
import com.teslacam.timestamp.databinding.ActivityMainBinding
import com.teslacam.timestamp.databinding.ItemResultBinding
import com.teslacam.timestamp.databinding.SheetPlayerBinding
import com.teslacam.timestamp.databinding.SheetPreviewBinding
import com.teslacam.timestamp.databinding.SheetResultsBinding
import com.teslacam.timestamp.ui.ClipAdapter
import com.teslacam.timestamp.ui.ClipCard
import com.teslacam.timestamp.ui.HeaderAdapter
import com.teslacam.timestamp.ui.MainViewModel
import com.teslacam.timestamp.ui.PreviewState
import com.teslacam.timestamp.ui.SimpleVideoPlayer
import com.teslacam.timestamp.ui.ThumbnailLoader
import com.teslacam.timestamp.ui.UiState
import com.teslacam.timestamp.usb.UsbInfo
import java.util.Locale

class MainActivity : AppCompatActivity(), HeaderAdapter.Callbacks {

    private lateinit var binding: ActivityMainBinding
    private val viewModel: MainViewModel by viewModels()

    private lateinit var thumbnails: ThumbnailLoader
    private lateinit var headerAdapter: HeaderAdapter
    private lateinit var clipAdapter: ClipAdapter

    private var pendingPermissionAction: (() -> Unit)? = null
    private var lastResultsCount = 0
    private var lastShownError: String? = null
    private var lastWarning: String? = null
    private var shownPreview: PreviewState? = null
    private var doneVisible = false
    private var lastSelection: Set<String> = emptySet()
    private var lastGroupsSize = -1

    private val pickTree = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) viewModel.scanTree(uri)
    }

    private val pickDocument = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) viewModel.scanDocument(uri)
    }

    private val requestPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val action = pendingPermissionAction
            pendingPermissionAction = null
            if (granted) action?.invoke() else toast(getString(R.string.status_permission))
        }

    private val storageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            refreshUsbPill(viewModel.state.value ?: UiState())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        thumbnails = ThumbnailLoader(this)
        headerAdapter = HeaderAdapter(this)
        clipAdapter = ClipAdapter(
            thumbnails = thumbnails,
            onToggleGroup = { groupId, checked -> viewModel.setGroupSelected(groupId, checked) },
            onToggleFile = { file, checked -> viewModel.setFileSelected(file.id, checked) },
            onPreviewClip = { _, file -> viewModel.requestPreviewFor(file.id) }
        )

        binding.recyclerClip.layoutManager = LinearLayoutManager(this)
        binding.recyclerClip.adapter = ConcatAdapter(headerAdapter, clipAdapter)
        (binding.recyclerClip.itemAnimator as? DefaultItemAnimator)?.supportsChangeAnimations = false
        binding.recyclerClip.itemAnimator = DefaultItemAnimator().apply { supportsChangeAnimations = false }

        setupBottomBar()

        viewModel.state.observe(this) { state ->
            render(state)
            handleOneShot(state)
        }
        refreshUsbPill(UiState())
        handleViewIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        thumbnails.shutdown()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleViewIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(UsbAttached)
            addAction(UsbDetached)
            addAction(Intent.ACTION_MEDIA_MOUNTED)
            addAction(Intent.ACTION_MEDIA_UNMOUNTED)
        }
        runCatching {
            ContextCompat.registerReceiver(this, storageReceiver, filter, ContextCompat.RECEIVER_EXPORTED)
        }
    }

    override fun onStop() {
        runCatching { unregisterReceiver(storageReceiver) }
        super.onStop()
    }

    // ------------------------------------------------------------ header callbacks

    override fun onPickFolder() {
        haptic()
        runCatching { pickTree.launch(null) }.onFailure { toast("无法打开文件选择器") }
    }

    override fun onPickFile() {
        haptic()
        runCatching { pickDocument.launch(arrayOf("video/mp4", "video/*")) }
            .onFailure { toast("无法打开文件选择器") }
    }

    override fun onPickPath() {
        haptic()
        showPathDialog()
    }

    override fun onRescan() {
        haptic()
        viewModel.rescan()
    }

    override fun onPreview() {
        haptic()
        viewModel.requestPreview()
    }

    override fun onStyleChanged(
        positionIndex: Int,
        sizeIndex: Int,
        showDate: Boolean,
        showDetails: Boolean
    ) {
        haptic()
        viewModel.setStyle(positionIndex, sizeIndex, showDate, showDetails)
    }

    override fun onSelectAll() {
        haptic()
        viewModel.selectAll(true)
    }

    override fun onClearSelection() {
        haptic()
        viewModel.selectAll(false)
    }

    // ------------------------------------------------------------------ rendering

    private fun render(state: UiState) {
        // Selecting a different clip after a finished batch must bring the primary action back.
        if (state.selected != lastSelection || state.groups.size != lastGroupsSize) {
            lastSelection = state.selected
            lastGroupsSize = state.groups.size
            if (state.selected.isNotEmpty()) doneVisible = false
        }
        headerAdapter.submit(state)
        clipAdapter.submitList(buildCards(state))
        refreshUsbPill(state)

        if (state.scanning) {
            binding.progressBar.isIndeterminate = true
        } else {
            binding.progressBar.isIndeterminate = false
        }

        when {
            state.running -> renderRunning(state)
            doneVisible && state.results.isNotEmpty() -> renderDone(state)
            else -> renderIdle(state)
        }
    }

    private fun buildCards(state: UiState): List<ClipCard> = state.groups.map { group ->
        ClipCard(
            group = group,
            selected = group.files.filter { state.selected.contains(it.id) }.map { it.id }.toSet(),
            fullySelected = state.isGroupFullySelected(group),
            partlySelected = state.isGroupPartlySelected(group)
        )
    }

    private fun renderIdle(state: UiState) {
        binding.barIdle.visibility = View.VISIBLE
        binding.barRunning.visibility = View.GONE
        binding.barDone.visibility = View.GONE

        val count = state.selectedCount
        if (count == 0) {
            binding.tvSummary.text = getString(R.string.summary_none)
            binding.tvSummaryHint.text = state.status
        } else {
            val size = TimeFormats.fileSize(state.selectedSizeBytes)
            binding.tvSummary.text = getString(R.string.summary_selected, count, size)
            val position = com.teslacam.timestamp.media.OverlayPosition.entries[state.positionIndex].label
            val textSize = com.teslacam.timestamp.media.OverlayStyle.SIZE_LABELS[state.sizeIndex]
            binding.tvSummaryHint.text = "位置 " + position + " · 字号 " + textSize +
                if (state.showDetails) " · 含摄像头/地点" else ""
        }
        binding.btnGenerate.isEnabled = count > 0 && !state.scanning
        binding.btnGenerate.text = if (count > 0) {
            getString(R.string.action_generate_count, count)
        } else {
            getString(R.string.action_generate)
        }
    }

    private fun renderRunning(state: UiState) {
        binding.barIdle.visibility = View.GONE
        binding.barRunning.visibility = View.VISIBLE
        binding.barDone.visibility = View.GONE

        val percent = (state.progress * 100f).toInt().coerceIn(0, 100)
        binding.tvRunningTitle.text = String.format(Locale.US, "正在合成 %d%%", percent)
        binding.tvRunningSubtitle.text = state.status
        binding.progressBar.progress = percent
    }

    private fun renderDone(state: UiState) {
        binding.barIdle.visibility = View.GONE
        binding.barRunning.visibility = View.GONE
        binding.barDone.visibility = View.VISIBLE
        binding.tvDoneTitle.text = getString(R.string.done_title, state.results.size)
        binding.tvDoneSubtitle.text = getString(R.string.done_subtitle)
        binding.btnPlayLatest.text = getString(R.string.action_play_latest)
    }

    private fun setupBottomBar() {
        binding.btnGenerate.setOnClickListener {
            haptic()
            doneVisible = false
            viewModel.generate()
        }
        binding.btnCancel.setOnClickListener {
            haptic()
            viewModel.cancelWork()
        }
        binding.btnHelp.setOnClickListener {
            haptic()
            showHelp()
        }
        binding.btnAllResults.setOnClickListener {
            haptic()
            val state = viewModel.state.value
            if (state == null || state.results.isEmpty()) {
                toast("没有可查看的结果")
            } else {
                showResultsSheet(state)
            }
        }
        binding.btnPlayLatest.setOnClickListener {
            haptic()
            val latest = viewModel.state.value?.results?.lastOrNull()
            if (latest == null) {
                toast("没有可播放的结果")
            } else {
                playInApp(latest.uri, latest.title)
            }
        }
    }

    // ---------------------------------------------------------------------- one shot

    private fun handleOneShot(state: UiState) {
        val preview = state.preview
        if (preview != null && preview !== shownPreview) {
            shownPreview = preview
            showPreviewSheet(preview)
        }
        if (state.results.isNotEmpty() && !state.running && state.results.size != lastResultsCount) {
            lastResultsCount = state.results.size
            doneVisible = true
            if (state.error != null) lastShownError = state.error
            viewModel.dismissError()
            showResultsSheet(state)
            return
        }
        val error = state.error
        if (error != null && error != lastShownError) {
            lastShownError = error
            doneVisible = false
            MaterialAlertDialogBuilder(this)
                .setTitle(R.string.notice_title)
                .setMessage(error)
                .setPositiveButton(R.string.action_ok, null)
                .show()
            viewModel.dismissError()
        }
        val message = state.message
        if (message != null) {
            toast(message)
            viewModel.dismissMessage()
        }
        val warning = state.warnings.firstOrNull()
        if (warning != null && warning != lastWarning) {
            lastWarning = warning
            toast(warning)
        }
    }

    private fun refreshUsbPill(state: UiState) {
        val names = runCatching { UsbInfo.attachedNames(this) }.getOrDefault(emptyList())
        val connected = names.isNotEmpty()
        binding.usbDot.setBackgroundResource(if (connected) R.drawable.bg_dot_on else R.drawable.bg_dot_off)
        binding.tvUsbPill.text = if (connected) {
            names.first().take(14)
        } else {
            getString(R.string.usb_disconnected)
        }
    }

    // ----------------------------------------------------------------------- sheets

    private fun showPreviewSheet(preview: PreviewState) {
        val sheetBinding = SheetPreviewBinding.inflate(layoutInflater)
        val dialog = BottomSheetDialog(this)
        dialog.setContentView(sheetBinding.root)
        sheetBinding.ivPreview.setImageBitmap(preview.bitmap)
        sheetBinding.tvPreviewCaption.text = preview.caption
        sheetBinding.btnPreviewClose.setOnClickListener { dialog.dismiss() }
        sheetBinding.btnPreviewGenerate.setOnClickListener {
            dialog.dismiss()
            doneVisible = false
            viewModel.generate()
        }
        dialog.setOnDismissListener {
            shownPreview = null
            viewModel.dismissPreview()
        }
        dialog.show()
    }

    private fun showResultsSheet(state: UiState) {
        val sheetBinding = SheetResultsBinding.inflate(layoutInflater)
        val dialog = BottomSheetDialog(this)
        dialog.setContentView(sheetBinding.root)
        sheetBinding.tvResultSummary.text = getString(R.string.result_message, state.results.size)
        if (state.failures.isNotEmpty()) {
            sheetBinding.tvResultFailures.visibility = View.VISIBLE
            sheetBinding.tvResultFailures.text =
                state.failures.size.toString() + " 个未完成：\n" + state.failures.joinToString("\n")
        } else {
            sheetBinding.tvResultFailures.visibility = View.GONE
        }
        sheetBinding.containerResults.removeAllViews()
        state.results.forEach { result ->
            val row = ItemResultBinding.inflate(layoutInflater, sheetBinding.containerResults, false)
            row.tvResultName.text = result.title
            row.tvResultInfo.text = (result.durationMs / 1000).toString() + " 秒 · " +
                TimeFormats.fileSize(result.sizeBytes)
            row.btnResultPlay.setOnClickListener {
                dialog.dismiss()
                playInApp(result.uri, result.displayName)
            }
            row.btnResultShare.setOnClickListener { shareVideo(result.uri) }
            sheetBinding.containerResults.addView(row.root)
        }
        sheetBinding.btnResultsClose.setOnClickListener { dialog.dismiss() }
        dialog.show()
    }

    private fun playInApp(uri: Uri, title: String) {
        val sheetBinding = SheetPlayerBinding.inflate(layoutInflater)
        val dialog = BottomSheetDialog(this)
        dialog.setContentView(sheetBinding.root)
        sheetBinding.tvPlayerTitle.text = title
        sheetBinding.tvPlayerInfo.text = "相册 · Movies/TeslaTimestamp"
        sheetBinding.btnPlayerClose.setOnClickListener { dialog.dismiss() }
        sheetBinding.btnPlayerShare.setOnClickListener { shareVideo(uri) }

        val player = SimpleVideoPlayer(this, sheetBinding.texturePlayer)
        player.onPrepared = { mediaPlayer ->
            sheetBinding.tvPlayerInfo.text =
                "时长 " + (mediaPlayer.duration / 1000) + " 秒 · 循环播放 · 相册 Movies/TeslaTimestamp"
        }
        player.onError = { message -> toast(message) }
        player.play(uri)
        dialog.setOnDismissListener { player.release() }
        dialog.show()
    }

    private fun shareVideo(uri: Uri) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "video/mp4"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching {
            startActivity(Intent.createChooser(intent, getString(R.string.action_share)))
        }.onFailure { toast("没有可分享的应用") }
    }

    // --------------------------------------------------------------------- dialogs

    private fun showPathDialog() {
        val density = resources.displayMetrics.density
        val input = EditText(this).apply {
            hint = getString(R.string.dialog_path_hint)
            setText("/sdcard/Download/TeslaCam")
            inputType = InputType.TYPE_CLASS_TEXT
            setSingleLine()
            setPadding((16 * density).toInt(), (12 * density).toInt(), (16 * density).toInt(), 0)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.dialog_path_title)
            .setView(input)
            .setNegativeButton(R.string.action_cancel, null)
            .setPositiveButton(R.string.dialog_path_confirm) { _, _ ->
                ensureStoragePermission { viewModel.scanPath(input.text.toString()) }
            }
            .show()
    }

    private fun showHelp() {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.help_title)
            .setMessage(R.string.help_body)
            .setPositiveButton(R.string.action_ok, null)
            .show()
    }

    private fun handleViewIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val type = intent.type
        val looksLikeVideo = type?.startsWith("video/") == true ||
            uri.toString().lowercase().contains(".mp4")
        if (looksLikeVideo) {
            ensureStoragePermission { viewModel.scanDocument(uri) }
        }
    }

    private fun ensureStoragePermission(action: () -> Unit) {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED) {
            action()
        } else {
            pendingPermissionAction = action
            requestPermission.launch(permission)
        }
    }

    private fun haptic() {
        runCatching {
            binding.root.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        }
    }

    private fun toast(text: String) {
        android.widget.Toast.makeText(this, text, android.widget.Toast.LENGTH_SHORT).show()
    }

    private companion object {
        const val UsbAttached = "android.hardware.usb.action.USB_DEVICE_ATTACHED"
        const val UsbDetached = "android.hardware.usb.action.USB_DEVICE_DETACHED"
    }
}

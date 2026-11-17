package com.teslacam.timestamp.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.teslacam.timestamp.R
import com.teslacam.timestamp.databinding.ItemEmptyBinding
import com.teslacam.timestamp.databinding.ItemHeaderSourceBinding
import com.teslacam.timestamp.databinding.ItemHeaderSelectBinding
import com.teslacam.timestamp.databinding.ItemHeaderStyleBinding

/** Two sticky-on-scroll header cards (data source + overlay style) plus the empty state. */
class HeaderAdapter(private val callbacks: Callbacks) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    interface Callbacks {
        fun onPickFolder()
        fun onPickFile()
        fun onPickPath()
        fun onRescan()
        fun onPreview()
        fun onStyleChanged(positionIndex: Int, sizeIndex: Int, showDate: Boolean, showDetails: Boolean)
        fun onSelectAll()
        fun onClearSelection()
    }

    private companion object {
        const val TYPE_SOURCE = 0
        const val TYPE_STYLE = 1
        const val TYPE_SELECT = 2
        const val TYPE_EMPTY = 3
    }

    private var state: UiState = UiState()
    private var suppress = false

    fun submit(newState: UiState) {
        val hadEmpty = state.groups.isEmpty()
        state = newState
        notifyItemRangeChanged(0, itemCount)
        if (hadEmpty != newState.groups.isEmpty()) {
            notifyDataSetChanged()
        }
    }

    override fun getItemCount(): Int = 3

    override fun getItemViewType(position: Int): Int = when (position) {
        0 -> TYPE_SOURCE
        1 -> TYPE_STYLE
        else -> if (state.groups.isEmpty()) TYPE_EMPTY else TYPE_SELECT
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_SOURCE -> SourceHolder(ItemHeaderSourceBinding.inflate(inflater, parent, false))
            TYPE_STYLE -> StyleHolder(ItemHeaderStyleBinding.inflate(inflater, parent, false))
            TYPE_SELECT -> SelectHolder(ItemHeaderSelectBinding.inflate(inflater, parent, false))
            else -> EmptyHolder(ItemEmptyBinding.inflate(inflater, parent, false))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (holder) {
            is SourceHolder -> holder.bind(state)
            is StyleHolder -> holder.bind(state)
            is SelectHolder -> holder.bind(state)
            else -> Unit
        }
    }

    inner class SourceHolder(private val binding: ItemHeaderSourceBinding) :
        RecyclerView.ViewHolder(binding.root) {

        init {
            binding.btnPickFolder.setOnClickListener { callbacks.onPickFolder() }
            binding.btnPickFile.setOnClickListener { callbacks.onPickFile() }
            binding.btnPickPath.setOnClickListener { callbacks.onPickPath() }
            binding.btnRescan.setOnClickListener { callbacks.onRescan() }
        }

        fun bind(state: UiState) {
            val label = when {
                state.scanning -> state.scanMessage.ifBlank { binding.root.context.getString(R.string.status_scanning) }
                else -> state.sourceLabel
            }
            binding.tvSourceName.text = label
            val enabled = !state.running && !state.scanning
            binding.btnPickFolder.isEnabled = enabled
            binding.btnPickFile.isEnabled = enabled
            binding.btnPickPath.isEnabled = enabled
            binding.btnRescan.isEnabled = enabled && state.sourceLabel != binding.root.context.getString(R.string.source_none)
            binding.btnRescan.alpha = if (binding.btnRescan.isEnabled) 1f else 0.4f
        }
    }

    inner class StyleHolder(private val binding: ItemHeaderStyleBinding) :
        RecyclerView.ViewHolder(binding.root) {

        private val positionIds = intArrayOf(
            R.id.btnPosTL,
            R.id.btnPosTR,
            R.id.btnPosBL,
            R.id.btnPosBR
        )
        private val sizeIds = intArrayOf(R.id.btnSizeS, R.id.btnSizeM, R.id.btnSizeL)

        init {
            binding.btnPreview.setOnClickListener { callbacks.onPreview() }
            binding.groupPosition.addOnButtonCheckedListener { _, checkedId, isChecked ->
                if (!suppress && isChecked) {
                    val index = positionIds.indexOf(checkedId)
                    if (index >= 0) emitStyle(positionIndex = index)
                }
            }
            binding.groupSize.addOnButtonCheckedListener { _, checkedId, isChecked ->
                if (!suppress && isChecked) {
                    val index = sizeIds.indexOf(checkedId)
                    if (index >= 0) emitStyle(sizeIndex = index)
                }
            }
            binding.chipDate.setOnCheckedChangeListener { _, checked ->
                if (!suppress) emitStyle(showDate = checked)
            }
            binding.chipDetails.setOnCheckedChangeListener { _, checked ->
                if (!suppress) emitStyle(showDetails = checked)
            }
        }

        private fun emitStyle(
            positionIndex: Int = state.positionIndex,
            sizeIndex: Int = state.sizeIndex,
            showDate: Boolean = state.showDate,
            showDetails: Boolean = state.showDetails
        ) {
            callbacks.onStyleChanged(positionIndex, sizeIndex, showDate, showDetails)
        }

        fun bind(state: UiState) {
            suppress = true
            val positionId = positionIds.getOrNull(state.positionIndex) ?: R.id.btnPosTL
            if (binding.groupPosition.checkedButtonId != positionId) {
                binding.groupPosition.check(positionId)
            }
            val sizeId = sizeIds.getOrNull(state.sizeIndex) ?: R.id.btnSizeM
            if (binding.groupSize.checkedButtonId != sizeId) {
                binding.groupSize.check(sizeId)
            }
            if (binding.chipDate.isChecked != state.showDate) {
                binding.chipDate.isChecked = state.showDate
            }
            if (binding.chipDetails.isChecked != state.showDetails) {
                binding.chipDetails.isChecked = state.showDetails
            }
            binding.btnPreview.isEnabled = state.groups.isNotEmpty() && !state.running && !state.scanning
            binding.btnPreview.text = if (state.previewLoading) {
                binding.root.context.getString(R.string.status_preview)
            } else {
                binding.root.context.getString(R.string.action_preview)
            }
            suppress = false
        }
    }

    inner class SelectHolder(private val binding: ItemHeaderSelectBinding) :
        RecyclerView.ViewHolder(binding.root) {

        init {
            binding.btnSelectAll.setOnClickListener { callbacks.onSelectAll() }
            binding.btnClearSelection.setOnClickListener { callbacks.onClearSelection() }
        }

        fun bind(state: UiState) {
            val total = state.groups.sumOf { it.files.size }
            binding.tvSelectionSummary.text =
                "共 " + state.groups.size + " 个片段 · " + total + " 个视频"
            binding.btnClearSelection.isEnabled = state.selected.isNotEmpty() && !state.running
            binding.btnSelectAll.isEnabled = !state.running
        }
    }

    inner class EmptyHolder(binding: ItemEmptyBinding) : RecyclerView.ViewHolder(binding.root)
}

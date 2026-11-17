package com.teslacam.timestamp.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.teslacam.timestamp.R
import com.teslacam.timestamp.data.ClipFile
import com.teslacam.timestamp.data.ClipGroup
import com.teslacam.timestamp.data.TeslaNaming
import com.teslacam.timestamp.data.TimeFormats
import com.teslacam.timestamp.databinding.ItemClipBinding

data class ClipCard(
    val group: ClipGroup,
    val selected: Set<String>,
    val fullySelected: Boolean,
    val partlySelected: Boolean
)

/**
 * One card per Tesla clip: thumbnail, start time, category metadata and a chip per camera so the
 * user can select individual camera videos (front / back / left / right).
 */
class ClipAdapter(
    private val thumbnails: ThumbnailLoader,
    private val onToggleGroup: (String, Boolean) -> Unit,
    private val onToggleFile: (ClipFile, Boolean) -> Unit,
    private val onPreviewClip: (ClipGroup, ClipFile) -> Unit
) : ListAdapter<ClipCard, ClipAdapter.ClipHolder>(DIFF) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ClipHolder {
        val binding = ItemClipBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ClipHolder(binding)
    }

    override fun onBindViewHolder(holder: ClipHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ClipHolder(private val binding: ItemClipBinding) : RecyclerView.ViewHolder(binding.root) {

        fun bind(card: ClipCard) {
            val group = card.group
            binding.tvClipTime.text = group.title
            binding.tvClipMeta.text = binding.root.context.getString(
                R.string.clip_meta,
                group.category.label,
                group.files.size,
                TimeFormats.fileSize(group.files.sumOf { it.sizeBytes })
            )

            binding.ivThumb.setOnClickListener { view ->
                val file = group.files.firstOrNull() ?: return@setOnClickListener
                onPreviewClip(group, file)
            }

            binding.cbGroup.setOnCheckedChangeListener(null)
            binding.cbGroup.isChecked = card.fullySelected
            binding.cbGroup.alpha = if (card.partlySelected && !card.fullySelected) 0.6f else 1f
            binding.cbGroup.setOnCheckedChangeListener { _, checked ->
                onToggleGroup(group.id, checked)
            }

            val context = binding.root.context
            val strokeColor = if (card.fullySelected || card.partlySelected) {
                androidx.core.content.ContextCompat.getColor(context, R.color.brand_red)
            } else {
                androidx.core.content.ContextCompat.getColor(context, R.color.outline)
            }
            binding.root.strokeColor = strokeColor
            binding.root.strokeWidth = if (card.fullySelected || card.partlySelected) 2 else 1

            bindCameraChips(card)
            val thumbnailSource = group.files.firstOrNull()?.source
            if (thumbnailSource != null) {
                thumbnails.load(thumbnailSource, binding.ivThumb)
            } else {
                binding.ivThumb.setImageDrawable(null)
            }
        }

        private fun bindCameraChips(card: ClipCard) {
            val chips: ChipGroup = binding.chipGroupCameras
            chips.removeAllViews()
            card.group.files.forEach { file ->
                val chip = Chip(chips.context)
                chip.text = TeslaNaming.cameraLabel(file.camera)
                chip.isCheckable = true
                chip.isCheckedIconVisible = true
                chip.isChecked = card.selected.contains(file.id)
                chip.textAlignment = android.view.View.TEXT_ALIGNMENT_CENTER
                chip.contentDescription = chip.text
                chip.alpha = if (chip.isChecked) 1f else 0.75f
                chip.setOnCheckedChangeListener { view, checked ->
                    view.alpha = if (checked) 1f else 0.75f
                    onToggleFile(file, checked)
                }
                chips.addView(chip)
            }
        }
    }

    private companion object {
        val DIFF = object : DiffUtil.ItemCallback<ClipCard>() {
            override fun areItemsTheSame(oldItem: ClipCard, newItem: ClipCard): Boolean =
                oldItem.group.id == newItem.group.id &&
                    oldItem.group.files.map { it.id } == newItem.group.files.map { it.id }

            override fun areContentsTheSame(oldItem: ClipCard, newItem: ClipCard): Boolean =
                areItemsTheSame(oldItem, newItem) &&
                    oldItem.selected == newItem.selected &&
                    oldItem.fullySelected == newItem.fullySelected &&
                    oldItem.partlySelected == newItem.partlySelected
        }
    }
}

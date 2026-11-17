package com.teslacam.timestamp.usb

import android.content.Context
import android.hardware.usb.UsbManager
import android.os.storage.StorageManager

/** Describes the USB hardware the app can see. */
object UsbInfo {

    fun attachedNames(context: Context): List<String> {
        val names = mutableListOf<String>()
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
        usbManager?.deviceList?.values?.forEach { device ->
            val name = runCatching {
                device.productName ?: device.manufacturerName ?: device.deviceName
            }.getOrNull()
            if (!name.isNullOrBlank() && !names.contains(name)) names += name
        }
        val storageManager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
        val removable = storageManager?.storageVolumes?.filter { it.isRemovable } ?: emptyList()
        removable.forEach { volume ->
            val label = runCatching { volume.getDescription(context) }.getOrNull()
            if (!label.isNullOrBlank() && !names.contains(label)) names += label
        }
        return names
    }

    fun isConnected(context: Context): Boolean = attachedNames(context).isNotEmpty()
}

package com.teslacam.timestamp.saep

import android.content.Context

internal object SaepStatus {
    fun isEnabled(context: Context): Boolean {
        return try {
            val stub = Class.forName("android.security.obric.robots.RobotsHelperStub")
            val instance = stub.getMethod("getInstance").invoke(null) ?: return false
            val result = try {
                stub.getMethod("isRobotsEnabled", Context::class.java)
                    .invoke(instance, context.applicationContext)
            } catch (_: NoSuchMethodException) {
                stub.getMethod("isRobotsEnabled").invoke(instance)
            }
            result == true
        } catch (_: ReflectiveOperationException) {
            false
        } catch (_: SecurityException) {
            false
        } catch (_: LinkageError) {
            false
        }
    }
}

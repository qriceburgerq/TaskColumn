package com.antigravity.taskcolumn

import android.app.Application

class TaskColumnApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        lateinit var instance: TaskColumnApplication
            private set
    }
}

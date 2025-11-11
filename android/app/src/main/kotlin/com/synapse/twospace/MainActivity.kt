package com.synapse.twospace

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "two_space_app/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val ok = installApk(path)
                    result.success(ok)
                }
                "canRequestInstallPackages" -> {
                    val can = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(can)
                }
                "openInstallSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "saveFileToGallery" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val ok = saveFileToGallery(path)
                    result.success(ok)
                }
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val text = call.argument<String>("text")
                    if (path == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val ok = shareFile(path, text)
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(path: String): Boolean {
        try {
            val apkFile = File(path)
            if (!apkFile.exists()) return false
            val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(this, "$packageName.fileprovider", apkFile)
            } else {
                Uri.fromFile(apkFile)
            }
            val intent = Intent(Intent.ACTION_VIEW)
            intent.setDataAndType(apkUri, "application/vnd.android.package-archive")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(intent)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    private fun saveFileToGallery(path: String): Boolean {
        try {
            val src = File(path)
            if (!src.exists()) return false
            val pictures = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES)
            val destDir = File(pictures, "TwoSpace")
            if (!destDir.exists()) destDir.mkdirs()
            val dest = File(destDir, src.name)
            src.copyTo(dest, overwrite = true)
            android.media.MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), null, null)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }

    private fun shareFile(path: String, text: String?): Boolean {
        try {
            val file = File(path)
            if (!file.exists()) return false
            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            } else {
                Uri.fromFile(file)
            }
            val intent = Intent(Intent.ACTION_SEND)
            val mime = java.net.URLConnection.guessContentTypeFromName(file.name) ?: "*/*"
            intent.type = mime
            intent.putExtra(Intent.EXTRA_STREAM, uri)
            if (text != null) intent.putExtra(Intent.EXTRA_TEXT, text)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(intent, "Поделиться"))
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
}
